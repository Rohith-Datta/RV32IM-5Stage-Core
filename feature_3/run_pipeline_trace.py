#!/usr/bin/env python3
# ============================================================================
# File: run_pipeline_trace.py
# Description: Interactive Pipeline Simulation & Cycle-by-Cycle Terminal Visualizer
# Project: 5-Stage RV32IM Processor Core (Feature 3: Hardware Divider)
#
# Features:
# 1. Shows cycle-by-cycle pipeline progression across IF, ID, EX, MEM, WB stages.
# 2. Explains what instruction is in each stage (address + mnemonic).
# 3. Highlights in real-time when:
#    - Multi-cycle Divider Interlock Stall occurs (32 cycles) -> FPGA LED[0] & LED[5] ON
#    - Data Hazard is detected (Load-Use Stall) -> FPGA LED[0] ON
#    - Data Forwarding is active (EX/MEM or MEM/WB bypass) -> FPGA LED[1] ON
#    - A Branch / Speculative Flush occurs -> FPGA LED[2] ON
# 4. Notes the current Fetch Address on the FPGA 8-digit 7-segment display.
# 5. Displays the static Instruction Memory listing and the dynamic execution order.
# 6. Supports:
#    - Standard benchmarks: division, multiplication, addition, fibonacci, sort, negative, xor
#    - Custom C files (.c), Assembly files (.s), or Hex files (.hex)
# ============================================================================

import os
import sys
import subprocess
import re
import argparse
import shutil

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
if os.path.basename(CURRENT_DIR) in ("feature_1", "feature_2", "feature_3"):
    ROOT_DIR = os.path.dirname(CURRENT_DIR)
else:
    ROOT_DIR = CURRENT_DIR

FEATURE1_DIR = os.path.join(ROOT_DIR, "feature_1")
FEATURE2_DIR = os.path.join(ROOT_DIR, "feature_2")
FEATURE3_DIR = os.path.join(ROOT_DIR, "feature_3")
C_TESTS_DIR  = os.path.join(ROOT_DIR, "c_tests")

CC      = "riscv-none-elf-gcc"
OBJCOPY = "riscv-none-elf-objcopy"
OBJDUMP = "riscv-none-elf-objdump"

REG_NAMES = [
    'zero', 'ra', 'sp', 'gp', 'tp', 't0', 't1', 't2',
    's0', 's1', 'a0', 'a1', 'a2', 'a3', 'a4', 'a5',
    'a6', 'a7', 's2', 's3', 's4', 's5', 's6', 's7',
    's8', 's9', 's10', 's11', 't3', 't4', 't5', 't6'
]

def disassemble_word(word):
    """Decodes a 32-bit RV32I/M machine word into assembly mnemonic."""
    if word == 0x00000013:
        return "nop"
    if word == 0x00008067:
        return "ret"
    if word == 0x00000000:
        return "bubble (nop)"

    opcode = word & 0x7F
    rd = (word >> 7) & 0x1F
    funct3 = (word >> 12) & 0x7
    rs1 = (word >> 15) & 0x1F
    rs2 = (word >> 20) & 0x1F
    funct7 = (word >> 25) & 0x7F

    imm_i = (word >> 20) - ((word >> 31) << 12)
    imm_s = ((word >> 7) & 0x1F) | (((word >> 25) & 0x7F) << 5)
    if imm_s >= 0x800:
        imm_s -= 0x1000
    imm_b = (((word >> 8) & 0xF) << 1) | (((word >> 25) & 0x3F) << 5) | (((word >> 7) & 0x1) << 11) | (((word >> 31) & 0x1) << 12)
    if imm_b >= 0x1000:
        imm_b -= 0x2000
    imm_u = word & 0xFFFFF000
    imm_j = (((word >> 21) & 0x3FF) << 1) | (((word >> 20) & 0x1) << 11) | (((word >> 12) & 0xFF) << 12) | (((word >> 31) & 0x1) << 20)
    if imm_j >= 0x100000:
        imm_j -= 0x200000

    r_d = REG_NAMES[rd]
    r_1 = REG_NAMES[rs1]
    r_2 = REG_NAMES[rs2]

    if opcode == 0x13:  # OP-IMM
        names = ['addi', 'slli', 'slti', 'sltiu', 'xori', 'srli/srai', 'ori', 'andi']
        if funct3 == 0:
            if rs1 == 0:
                return f"li {r_d}, {imm_i}"
            return f"addi {r_d}, {r_1}, {imm_i}"
        return f"{names[funct3]} {r_d}, {r_1}, {imm_i}"
    elif opcode == 0x33:  # OP / RV32M
        if funct7 == 0x01:
            m_names = ['mul', 'mulh', 'mulhsu', 'mulhu', 'div', 'divu', 'rem', 'remu']
            return f"{m_names[funct3]} {r_d}, {r_1}, {r_2}"
        if funct3 == 0:
            return f"sub {r_d}, {r_1}, {r_2}" if funct7 == 0x20 else f"add {r_d}, {r_1}, {r_2}"
        names = ['add/sub', 'sll', 'slt', 'sltu', 'xor', 'srl/sra', 'or', 'and']
        return f"{names[funct3]} {r_d}, {r_1}, {r_2}"
    elif opcode == 0x03:  # LOAD
        names = ['lb', 'lh', 'lw', 'res', 'lbu', 'lhu']
        return f"{names[funct3]} {r_d}, {imm_i}({r_1})"
    elif opcode == 0x23:  # STORE
        names = ['sb', 'sh', 'sw']
        return f"{names[funct3]} {r_2}, {imm_s}({r_1})"
    elif opcode == 0x63:  # BRANCH
        names = ['beq', 'bne', 'res', 'res', 'blt', 'bge', 'bltu', 'bgeu']
        return f"{names[funct3]} {r_1}, {r_2}, {imm_b:+d}"
    elif opcode == 0x6F:  # JAL
        return f"j {imm_j:+d}" if rd == 0 else f"jal {r_d}, {imm_j:+d}"
    elif opcode == 0x67:  # JALR
        return f"jalr {r_d}, {r_1}, {imm_i}"
    elif opcode == 0x37:  # LUI
        return f"lui {r_d}, 0x{imm_u >> 12:x}"
    elif opcode == 0x17:  # AUIPC
        return f"auipc {r_d}, 0x{imm_u >> 12:x}"

    return f"0x{word:08x}"

def load_symbols():
    dis_file = os.path.join(C_TESTS_DIR, "code.dis")
    elf_file = os.path.join(C_TESTS_DIR, "code.elf")
    symbols = {}
    text_end = None

    if os.path.exists(dis_file):
        try:
            with open(dis_file, "r", encoding="utf-8") as f:
                for line in f:
                    m = re.match(r'([0-9a-fA-F]{8})\s+<([^>]+)>:', line)
                    if m:
                        symbols[int(m.group(1), 16)] = m.group(2)
        except Exception:
            pass

    if os.path.exists(elf_file):
        try:
            p = subprocess.run([OBJDUMP, "-h", elf_file], capture_output=True, text=True)
            for line in p.stdout.splitlines():
                m = re.search(r'\.text\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)', line)
                if m:
                    size = int(m.group(1), 16)
                    vma = int(m.group(2), 16)
                    text_end = vma + size
        except Exception:
            pass
    return symbols, text_end

def load_imem_map(imem_hex_path):
    imem = {}
    if not os.path.exists(imem_hex_path):
        return imem

    addr = 0
    with open(imem_hex_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            token = line.split()[0].split("//")[0]
            try:
                word = int(token, 16)
                if word != 0 or addr < 0x80:
                    imem[addr] = (word, disassemble_word(word))
                addr += 4
            except ValueError:
                continue
    return imem

def run_simulation(target_name, imem_map, sim_dir):
    cmd = "xsim snap_tb_base -runall"
    proc = subprocess.run(cmd, cwd=sim_dir, capture_output=True, text=True, shell=True)
    out = proc.stdout

    trace_records = []
    trace_re = re.compile(
        r"\[TRACE\]\s+CC=(\d+)\s+\|\s+IF_PC=([0-9a-fA-F]+)\s+\|\s+IF_INST=([0-9a-fA-F]+)\s+\|\s+ID_PC=([0-9a-fA-F]+)\s+\|\s+EX_PC=([0-9a-fA-F]+)\s+\|\s+MEM_PC=([0-9a-fA-F]+)\s+\|\s+WB_PC=([0-9a-fA-F]+)\s+\|\s+FWD_A=(\d+)\s+\|\s+FWD_B=(\d+)\s+\|\s+STALL=(\d+)\s+\|\s+FLUSH=(\d+)\s+\|\s+WB_WE=(\d+)\s+\|\s+WB_RD=(\d+)\s+\|\s+WB_DATA=([0-9a-fA-F]+)"
    )

    for line in out.splitlines():
        m = trace_re.search(line)
        if m:
            trace_records.append({
                "cc": int(m.group(1)),
                "if_pc": int(m.group(2), 16),
                "if_inst": int(m.group(3), 16),
                "id_pc": int(m.group(4), 16),
                "ex_pc": int(m.group(5), 16),
                "mem_pc": int(m.group(6), 16),
                "wb_pc": int(m.group(7), 16),
                "fwd_a": int(m.group(8)),
                "fwd_b": int(m.group(9)),
                "stall": int(m.group(10)),
                "flush": int(m.group(11)),
                "wb_we": int(m.group(12)),
                "wb_rd": int(m.group(13)),
                "wb_data": int(m.group(14), 16),
            })

    m_val = re.search(r"FINAL RETURN VALUE a0 \(x10\) =\s*(-?\d+)", out)
    ret_val = int(m_val.group(1)) if m_val else None

    return trace_records, ret_val, out

def build_instruction_tags(imem_map, text_end=None):
    inst_tags = {}
    idx = 1
    for addr in sorted(imem_map.keys()):
        word, mnem = imem_map[addr]
        if text_end is not None and addr >= text_end:
            break
        if word != 0 or addr <= 0x64:
            inst_tags[addr] = f"I{idx}"
            idx += 1
            if mnem == "ret":
                break
    return inst_tags

def print_banner(target_name):
    print("=" * 116)
    print(f"       RV32IM 5-STAGE PIPELINE TRACE VISUALIZER ({target_name.upper()})")
    print("       Core Engine: FEATURE 3 (RV32M Hardware Multipliers & Radix-2 Restoring Divider)")
    print("=" * 116)

def print_trace_table(records, imem_map, inst_tags):
    print("\n[2] CYCLE-BY-CYCLE PIPELINE EXECUTION TRACE TABLE & FPGA HARDWARE STATE:")
    print("=" * 116)
    header = f" {'CC':<3} | {'IF':<4} | {'ID':<4} | {'EX':<4} | {'MEM':<4} | {'WB':<4} | {'7-Seg PC':<10} | {'Register Commit':<16} | {'Pipeline Status & FPGA LEDs'}"
    print(header)
    print("=" * 116)

    retired_instructions = []

    for r in records:
        cc = r["cc"]
        if_pc = r["if_pc"]
        if_tag = inst_tags.get(if_pc, "-") if (if_pc in inst_tags or if_pc <= 0x64) else "-"

        id_pc = r["id_pc"]
        id_tag = "I1" if (id_pc == 0 and cc == 1) else (inst_tags.get(id_pc, "-") if id_pc != 0 else "-")

        ex_pc = r["ex_pc"]
        ex_tag = "I1" if (ex_pc == 0 and cc == 2) else (inst_tags.get(ex_pc, "-") if ex_pc != 0 else "-")

        mem_pc = r["mem_pc"]
        mem_tag = "I1" if (mem_pc == 0 and cc == 3) else (inst_tags.get(mem_pc, "-") if (mem_pc != 0 and mem_pc != 0xfffffffc) else "-")

        wb_we = r["wb_we"]
        wb_rd = r["wb_rd"]
        wb_data = r["wb_data"]
        wb_pc = r["wb_pc"]
        wb_tag = "I1" if (wb_pc == 0 and cc == 4) else (inst_tags.get(wb_pc, "-") if (wb_pc != 0 and wb_pc != 0xfffffffc) else "-")

        signed_wb_data = wb_data if wb_data < 0x80000000 else wb_data - 0x100000000

        if wb_we and wb_rd != 0:
            commit_str = f"{REG_NAMES[wb_rd]} <= {signed_wb_data}"
            wb_mnem = imem_map.get(wb_pc, (0, "retire"))[1]
            retired_instructions.append((cc, wb_tag, wb_pc, wb_mnem, REG_NAMES[wb_rd], wb_data))
        elif wb_pc in imem_map and imem_map[wb_pc][1] == "ret":
            commit_str = "ret (complete)"
            wb_mnem = "ret"
            retired_instructions.append((cc, wb_tag, wb_pc, wb_mnem, "Program Done", wb_data))
        else:
            commit_str = "-"

        notes = []
        # Check if EX is executing DIV/REM
        ex_mnem = imem_map.get(ex_pc, (0, ""))[1]
        is_div_rem = any(d in ex_mnem for d in ['div', 'divu', 'rem', 'remu'])
        if r["stall"] and is_div_rem:
            notes.append(">>> DIVIDER BUSY (LED[0], LED[5])")
        elif r["stall"]:
            notes.append("HAZARD STALL (LED[0])")

        if r["fwd_a"] != 0 or r["fwd_b"] != 0:
            fwd_info = []
            if r["fwd_a"] == 1: fwd_info.append("A:EX")
            elif r["fwd_a"] == 2: fwd_info.append("A:MEM")
            if r["fwd_b"] == 1: fwd_info.append("B:EX")
            elif r["fwd_b"] == 2: fwd_info.append("B:MEM")
            notes.append(f"FWD {' '.join(fwd_info)} (LED[1])")

        if r["flush"]:
            notes.append("BRANCH FLUSH (LED[2])")

        if wb_we and wb_rd != 0:
            led_byte = wb_data & 0xFF
            notes.append(f"RETIRE (LED[3], 0x{led_byte:02x})")

        notes_str = " | ".join(notes) if notes else "Normal"
        disp_7seg = f"0x{if_pc:08x}"

        print(f" {cc:<3} | {if_tag:<4} | {id_tag:<4} | {ex_tag:<4} | {mem_tag:<4} | {wb_tag:<4} | {disp_7seg} | {commit_str:<16} | {notes_str}")

    print("=" * 116)
    return retired_instructions

def main():
    parser = argparse.ArgumentParser(description="Feature 3: 5-Stage RV32IM Processor Pipeline Trace Visualizer")
    parser.add_argument("target", nargs="?", default="division",
                        help="Target test (division, multiplication, addition, fibonacci, sort, negative, xor)")
    args = parser.parse_args()
    target = args.target

    f3_mem = os.path.join(FEATURE3_DIR, "mem")
    os.makedirs(f3_mem, exist_ok=True)
    f3_imem_hex = os.path.join(f3_mem, "imem.hex")
    f3_dmem_hex = os.path.join(f3_mem, "dmem.hex")

    build_script = os.path.join(C_TESTS_DIR, "build_hex.py")
    print(f"[*] Building benchmark program: {target} via {build_script}...")
    subprocess.check_call([sys.executable, build_script, target], cwd=ROOT_DIR)

    imem_map = load_imem_map(f3_imem_hex)
    symbols, text_end = load_symbols()
    inst_tags = build_instruction_tags(imem_map, text_end)
    sim_dir = os.path.join(FEATURE3_DIR, "simulation")

    print_banner(target)

    print(f"\n[*] Running cycle-by-cycle simulation via Vivado xsim (Feature 3)...")
    records, ret_val, raw_out = run_simulation(target, imem_map, sim_dir)

    if not records:
        print("[-] Error: No trace records collected from xsim. Raw output:\n", raw_out)
        sys.exit(1)

    retired = print_trace_table(records, imem_map, inst_tags)
    print("\n=================================================================")
    print("           PROGRAM EXECUTION SUMMARY")
    print("=================================================================")
    print(f" * Target Program             : {target}")
    print(f" * Total Elapsed Clock Cycles : {len(records)}")
    print(f" * Instructions Retired       : {len(retired)}")
    if ret_val is not None:
        print(f" * FINAL RETURN VALUE a0 (x10): {ret_val} (0x{ret_val & 0xFFFFFFFF:08x})")
    print("=================================================================\n")

if __name__ == "__main__":
    main()
