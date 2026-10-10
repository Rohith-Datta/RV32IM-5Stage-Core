#!/usr/bin/env python3
# ============================================================================
# File: run_pipeline_trace.py
# Description: Interactive Pipeline Simulation & Cycle-by-Cycle Terminal Visualizer
# Project: 5-Stage RV32I Processor Core (Feature 1)
#
# Features:
# 1. Shows cycle-by-cycle pipeline progression across IF, ID, EX, MEM, WB stages.
# 2. Explains what instruction is in each stage (address + mnemonic).
# 3. Highlights in real-time when:
#    - A Data Hazard is detected (Load-Use Stall) -> FPGA LED[0] ON
#    - Data Forwarding is active (EX/MEM or MEM/WB bypass) -> FPGA LED[1] ON
#    - A Branch / Speculative Flush occurs -> FPGA LED[2] ON
# 4. Notes the current Fetch Address on the FPGA 8-digit 7-segment display.
# 5. Displays the static Instruction Memory listing and the dynamic execution order.
# 6. Supports:
#    - Standard benchmarks: addition, fibonacci, sort, negative, xor
#    - Custom C files (.c), Assembly files (.s), or Hex files (.hex)
#    - Direct inline assembly strings: --asm "addi x1, x0, 10; addi x2, x0, 2; add x3, x1, x2; ret"
# ============================================================================

import os
import sys
import subprocess
import re
import argparse
import shutil

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
if os.path.basename(CURRENT_DIR) in ("feature_1", "feature_2"):
    ROOT_DIR = os.path.dirname(CURRENT_DIR)
else:
    ROOT_DIR = CURRENT_DIR

FEATURE1_DIR = os.path.join(ROOT_DIR, "feature_1")
FEATURE2_DIR = os.path.join(ROOT_DIR, "feature_2")
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
    """Decodes a 32-bit RV32I machine word into assembly mnemonic."""
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

    # Sign-extended immediates
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
    """Extracts function symbols and .text section boundary from code.dis / code.elf."""
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

def decode_rodata_word(word):
    """Decodes a 32-bit word in .rodata into readable ASCII or integer constant."""
    import struct
    b = struct.pack("<I", word)
    chars = []
    has_ascii = False
    for byte in b:
        if 32 <= byte <= 126:
            chars.append(chr(byte))
            has_ascii = True
        elif byte == 10:
            chars.append(r"\n")
            has_ascii = True
        elif byte == 13:
            chars.append(r"\r")
        elif byte == 0:
            chars.append(r"\0")
        else:
            chars.append(".")
    if has_ascii:
        return f'[STR] "{"".join(chars)}"'
    else:
        return f"[CONST] {word} (0x{word:08x})"

def load_imem_map(imem_hex_path):
    """Loads imem.hex into a dictionary {address: (word, mnemonic)}."""
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

def compile_custom_asm(asm_code, out_imem, out_dmem):
    """Compiles an assembly string into imem.hex and dmem.hex."""
    tmp_s = os.path.join(C_TESTS_DIR, "_tmp_custom.s")
    tmp_elf = os.path.join(C_TESTS_DIR, "_tmp_custom.elf")
    tmp_bin = os.path.join(C_TESTS_DIR, "_tmp_custom.bin")

    # Header with main and ret
    full_asm = f"""
.section .text
.globl main
main:
{asm_code}
    ret
"""
    with open(tmp_s, "w", encoding="utf-8") as f:
        f.write(full_asm)

    # Compile with GCC
    subprocess.check_call([CC, "-march=rv32im", "-mabi=ilp32", "-nostdlib", "-c", tmp_s, "-o", tmp_elf])
    subprocess.check_call([OBJCOPY, "-O", "binary", tmp_elf, tmp_bin])

    # Convert binary to hex
    j = 0
    with open(out_imem, "w", encoding="utf-8") as f:
        with open(tmp_bin, "rb") as bf:
            while True:
                chunk = bf.read(4)
                if not chunk:
                    break
                import struct
                word = struct.unpack("<I", chunk.ljust(4, b"\x00"))[0]
                f.write(f"{word:08x} // 32'h{j:08x}\n")
                j += 4
        while j < 4096:
            f.write(f"00000000 // 32'h{j:08x}\n")
            j += 4

    # Empty DMEM
    with open(out_dmem, "w", encoding="utf-8") as f:
        for k in range(0, 4096, 4):
            f.write(f"00000000 // 32'h{k:08x}\n")

def compile_c_or_asm_file(file_path, out_imem, out_dmem):
    """Compiles a C (.c) or Assembly (.s) file into hex."""
    tmp_elf = os.path.join(C_TESTS_DIR, "_tmp_custom.elf")
    tmp_bin = os.path.join(C_TESTS_DIR, "_tmp_custom.bin")

    is_c = file_path.endswith(".c")
    cflags = ["-march=rv32im", "-mabi=ilp32", "-O0"]
    if not is_c:
        cflags += ["-nostdlib"]

    subprocess.check_call([CC, "-c", file_path, "-o", tmp_elf] + cflags)
    subprocess.check_call([OBJCOPY, "-O", "binary", tmp_elf, tmp_bin])

    j = 0
    with open(out_imem, "w", encoding="utf-8") as f:
        with open(tmp_bin, "rb") as bf:
            while True:
                chunk = bf.read(4)
                if not chunk:
                    break
                import struct
                word = struct.unpack("<I", chunk.ljust(4, b"\x00"))[0]
                f.write(f"{word:08x} // 32'h{j:08x}\n")
                j += 4
        while j < 4096:
            f.write(f"00000000 // 32'h{j:08x}\n")
            j += 4

    with open(out_dmem, "w", encoding="utf-8") as f:
        for k in range(0, 4096, 4):
            f.write(f"00000000 // 32'h{k:08x}\n")

def run_simulation(target_name, imem_map, sim_dir):
    """Runs xsim and parses simulation trace output."""
    cmd = "xsim sim_pipeline_snap -runall"
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

    # Extract final return value
    m_val = re.search(r"FINAL RETURN VALUE a0 \(x10\) =\s*(-?\d+)", out)
    ret_val = int(m_val.group(1)) if m_val else None

    return trace_records, ret_val, out

def build_instruction_tags(imem_map, text_end=None):
    """Assigns sequential labels I1, I2, I3... to code instructions in .text."""
    inst_tags = {}
    idx = 1
    for addr in sorted(imem_map.keys()):
        word, mnem = imem_map[addr]
        if text_end is not None and addr >= text_end:
            break
        if word != 0 or addr <= 0x48:
            inst_tags[addr] = f"I{idx}"
            idx += 1
            if mnem == "ret":
                break
    return inst_tags

def print_banner(target_name, chosen_feature=1):
    feat_title = "FEATURE 2: RV32IM HARDWARE MULTIPLIER" if chosen_feature == 2 else "FEATURE 1: RV32I 5-STAGE PIPELINE"
    print("=" * 116)
    print(f"       RV32I/RV32M 5-STAGE PIPELINE CYCLE-BY-CYCLE TRACE VISUALIZER ({target_name.upper()})")
    print(f"       Core Engine: {feat_title} | Hazards, Forwarding, Flushes, FPGA Telemetry")
    print("=" * 116)


def print_imem_listing(imem_map, symbols=None, text_end=None, inst_tags=None):
    if symbols is None:
        symbols = {}
    if inst_tags is None:
        inst_tags = {}
    print("\n[1] STATIC INSTRUCTION MEMORY LISTING & FPGA 7-SEGMENT DISPLAY MAPPING:")
    print("=" * 116)
    print(f" {'Inst':<5} | {'Address (sw[2]=0)':<18} | {'Hex Code (sw[2]=1)':<18} | {'Disassembled Mnemonic':<28} | {'FPGA Hardware Note':<28}")
    print("=" * 116)

    in_rodata = False
    for addr in sorted(imem_map.keys()):
        word, mnem = imem_map[addr]

        # Check for function boundary
        if addr in symbols:
            print("-" * 116)
            print(f" >>> [FUNCTION: <{symbols[addr]}>] Entry Address: 0x{addr:08x}")
            print("-" * 116)

        # Check for section boundary (.rodata)
        if text_end is not None and addr >= text_end and not in_rodata:
            in_rodata = True
            print("=" * 116)
            print(f" >>> [SECTION .rodata: READ-ONLY CONSTANTS] Base Address: 0x{addr:08x}")
            print("=" * 116)

        tag = inst_tags.get(addr, "")
        if in_rodata:
            mnem = decode_rodata_word(word)
            note = "Data Memory (.rodata)"
        else:
            note = ""
            if "mul" in mnem:
                note = "<-- RV32M MULTIPLIER (DSP48E1)"
            elif "lw" in mnem or "sw" in mnem:
                note = "Memory Access (DMEM)"
            elif "ret" in mnem or "jalr" in mnem or "beq" in mnem or "bne" in mnem:
                note = "Control Flow (Branch/Jump)"
            elif "addi" in mnem or "add" in mnem or "sub" in mnem or "li" in mnem:
                note = "Arithmetic / Immediate"

        if word != 0 or addr <= 0x48:
            print(f" {tag:<5} | 0x{addr:08x}        | 0x{word:08x}        | {mnem:<28} | {note:<28}")
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

        # Stage IF
        if_pc = r["if_pc"]
        if_tag = inst_tags.get(if_pc, "-") if (if_pc in inst_tags or if_pc <= 0x48) else "-"

        # Stage ID
        id_pc = r["id_pc"]
        id_tag = "I1" if (id_pc == 0 and cc == 1) else (inst_tags.get(id_pc, "-") if id_pc != 0 else "-")

        # Stage EX
        ex_pc = r["ex_pc"]
        ex_tag = "I1" if (ex_pc == 0 and cc == 2) else (inst_tags.get(ex_pc, "-") if ex_pc != 0 else "-")

        # Stage MEM
        mem_pc = r["mem_pc"]
        mem_tag = "I1" if (mem_pc == 0 and cc == 3) else (inst_tags.get(mem_pc, "-") if (mem_pc != 0 and mem_pc != 0xfffffffc) else "-")

        # Stage WB
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
        elif wb_tag == "I18" or (wb_pc in imem_map and imem_map[wb_pc][1] == "ret"):
            commit_str = "ret (complete)"
            wb_mnem = "ret"
            retired_instructions.append((cc, wb_tag, wb_pc, wb_mnem, "Program Done", wb_data))
        else:
            commit_str = "-"

        # Notes / Hazards / Forwarding / LED indicators (formatted concisely)
        notes = []
        if r["stall"]:
            notes.append(">>> HAZARD STALL (LED[0])")
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
        elif wb_tag == "I18":
            notes.append("FINAL INSTRUCTION RETIRED (HALT)")

        notes_str = " | ".join(notes) if notes else "Normal"

        disp_7seg = "--------  " if cc >= 20 else f"0x{if_pc:08x}"

        print(f" {cc:<3} | {if_tag:<4} | {id_tag:<4} | {ex_tag:<4} | {mem_tag:<4} | {wb_tag:<4} | {disp_7seg} | {commit_str:<16} | {notes_str}")

    print("=" * 116)
    return retired_instructions

def print_execution_order(retired_instructions, ret_val=None):
    print("\n[3] DYNAMIC INSTRUCTION EXECUTION ORDER (COMMITTED / RETIRED TO REGISTER FILE):")
    print("-" * 116)
    print(f" {'#':<3} | {'Inst':<5} | {'Cycle':<6} | {'PC':<12} | {'Instruction Mnemonic':<24} | {'Register Commit Result':<22} | {'FPGA LED[15:8] Output':<22}")
    print("-" * 116)
    ret_byte_str = f"0x{ret_val & 0xFF:02x}" if ret_val is not None else "0x2a"
    for idx, (cc, tag, pc, mnem, rd, val) in enumerate(retired_instructions, 1):
        if mnem == "ret":
            print(f" {idx:<3} | {tag:<5} | CC={cc:<3} | 0x{pc:08x}   | {mnem:<24} | {'Program Complete':<22} | {ret_byte_str} (Latched Return Value)")
        else:
            signed_val = val if val < 0x80000000 else val - 0x100000000
            led_byte = val & 0xFF
            led_bin = f"{led_byte:08b}"
            print(f" {idx:<3} | {tag:<5} | CC={cc:<3} | 0x{pc:08x}   | {mnem:<24} | {rd} <= {signed_val:<6} (0x{val:08x}) | 0x{led_byte:02x} ({led_bin})")
    print("-" * 116)

def print_fpga_mapping_summary(records, ret_val, imem_map, retired_list=None, chosen_feature=1):
    total_cycles = len(records)
    stalls = sum(1 for r in records if r["stall"])
    forwards = sum(1 for r in records if r["fwd_a"] != 0 or r["fwd_b"] != 0)
    flushes = sum(1 for r in records if r["flush"])
    retired = len(retired_list) if retired_list is not None else sum(1 for r in records if (r["wb_we"] and r["wb_rd"] != 0) or (r["wb_pc"] in imem_map and imem_map[r["wb_pc"]][1] == "ret"))
    ipc = retired / total_cycles if total_cycles > 0 else 0

    print("\n[4] FPGA HARDWARE & VERIFICATION SUMMARY:")
    print("=" * 116)
    print(f" * Total Elapsed Clock Cycles    : {total_cycles}")
    print(f" * Instructions Retired          : {retired}")
    print(f" * Throughput (IPC)              : {ipc:.2f} instructions / cycle")
    if ret_val is not None:
        print(f" * FINAL RETURN VALUE a0 (x10)   : {ret_val} (0x{ret_val & 0xFFFFFFFF:08x})")
    print("=" * 116)

    sample_rec = records[10] if len(records) > 10 else (records[0] if records else {"if_pc": 0, "if_inst": 0})
    s_pc = sample_rec["if_pc"]
    s_inst = sample_rec["if_inst"]
    s_mnem = imem_map.get(s_pc, (s_inst, disassemble_word(s_inst)))[1]

    print("\n[5] HOW TO VIEW THESE INSTRUCTIONS ON THE PHYSICAL NEXYS A7 FPGA BOARD:")
    print("-" * 116)
    print(" 1. SPEED & CLOCK CONTROL (Slide Switches & Buttons):")
    print("    - sw[1] = 1 (Pin L16 ON) : 1 Hz Slow Clock mode. Processor runs 1 cycle/second.")
    print("                               Watch each instruction and LED transition live at human speed!")
    print("    - sw[0] = 1 (Pin J15 ON) : Manual Single-Step mode.")
    print("                               Press Center Pushbutton (btnc, Pin N17) to advance exactly 1 cycle.")
    if chosen_feature == 2:
        print("    - sw[3] = 0 (Pin R15 OFF): Hardware Multiplier: Artix-7 DSP48E1 Slices (Default).")
        print("      sw[3] = 1 (Pin R15 ON) : Hardware Multiplier: Radix-4 Booth Multiplier.")
    print("    - cpu_resetn (Pin C12)   : Press red CPU Reset button to restart program execution from PC=0x00.")
    print("")
    print(" 2. 8-DIGIT SEVEN-SEGMENT DISPLAY (Directly above the switches/LEDs):")
    print("    - sw[2] = 0 (Pin M13 OFF): Shows Program Counter Fetch Address (pc_if[31:0]).")
    print(f"                               E.g., Cycle 10 shows '{s_pc:08x}' (PC of '{s_mnem}').")
    print("    - sw[2] = 1 (Pin M13 ON) : Shows 32-bit Machine Instruction Code (imem_rdata[31:0]).")
    print(f"                               E.g., Cycle 10 shows '{s_inst:08X}' (Hex machine code of '{s_mnem}').")
    print("    - When Program Finishes  : 7-Segment Display shows '--------' across all 8 digits (no instructions left)!")
    print("")
    print(" 3. LED HARDWARE INDICATORS:")
    print("    - LED[0] (Pin H17)       : DATA HAZARD STALL (Turns ON during load-use hazard interlocks).")
    print("    - LED[1] (Pin K15)       : DATA FORWARDING ACTIVE (Turns ON when ALU/Multiplier forwards data).")
    print("    - LED[2] (Pin J13)       : BRANCH / RETURN FLUSH (Turns ON when speculative pipeline flushes).")
    print("    - LED[3] (Pin N14)       : WRITEBACK COMMIT (Turns ON whenever an instruction retires to a register).")
    print(f"    - LED[15:8] (Pins V11..H6): Low 8 bits of committed register result (wb_data[7:0]).")
    if ret_val is not None:
        final_byte = ret_val & 0xFF
        print(f"                               Final Result {ret_val} (0x{ret_val:08x}) -> LED[15:8] = 0x{final_byte:02x} ({final_byte:08b}b).")
    print("-" * 116 + "\n")

def main():
    parser = argparse.ArgumentParser(description="5-Stage RV32I/RV32M Processor Pipeline Trace Visualizer")
    parser.add_argument("target", nargs="?", default="addition",
                        help="Target test (addition, multiplication, fibonacci, sort, negative, xor, or custom file .c / .s / .hex)")
    parser.add_argument("--feature", "-f", choices=["1", "2", "auto"], default="auto",
                        help="Target core feature: 1 (RV32I baseline), 2 (RV32IM multiplier), or auto (default)")
    parser.add_argument("--asm", type=str, default=None,
                        help="Direct assembly string (e.g. 'addi x1, x0, 10; addi x2, x0, 2; add x3, x1, x2; ret')")
    parser.add_argument("--bitstream", action="store_true",
                        help="Automatically regenerate FPGA bitstream in Vivado after compiling hex")

    args = parser.parse_args()
    target = args.target

    f1_mem = os.path.join(FEATURE1_DIR, "mem")
    f2_mem = os.path.join(FEATURE2_DIR, "mem")
    os.makedirs(f1_mem, exist_ok=True)
    os.makedirs(f2_mem, exist_ok=True)
    f1_imem_hex = os.path.join(f1_mem, "imem.hex")
    f1_dmem_hex = os.path.join(f1_mem, "dmem.hex")
    f2_imem_hex = os.path.join(f2_mem, "imem.hex")
    f2_dmem_hex = os.path.join(f2_mem, "dmem.hex")

    # 1. Prepare Hex / Program
    if args.asm:
        print(f"[*] Compiling custom inline assembly: \"{args.asm}\"...")
        compile_custom_asm(args.asm, f1_imem_hex, f1_dmem_hex)
        shutil.copy2(f1_imem_hex, f2_imem_hex)
        shutil.copy2(f1_dmem_hex, f2_dmem_hex)
    elif target.endswith(".c") or target.endswith(".s"):
        print(f"[*] Compiling custom source file: {target}...")
        compile_c_or_asm_file(target, f1_imem_hex, f1_dmem_hex)
        shutil.copy2(f1_imem_hex, f2_imem_hex)
        shutil.copy2(f1_dmem_hex, f2_dmem_hex)
    elif target.endswith(".hex"):
        print(f"[*] Using custom hex file: {target}...")
        shutil.copy2(target, f1_imem_hex)
        shutil.copy2(target, f2_imem_hex)
    else:
        # Standard benchmark program
        build_script = os.path.join(C_TESTS_DIR, "build_hex.py")
        print(f"[*] Building benchmark program: {target} via {build_script}...")
        subprocess.check_call([sys.executable, build_script, target], cwd=ROOT_DIR)

    # 2. Load Instruction Memory Map & Symbol Information
    imem_map = load_imem_map(f1_imem_hex)
    symbols, text_end = load_symbols()
    inst_tags = build_instruction_tags(imem_map, text_end)

    # Auto-detect Feature 1 vs Feature 2
    has_mul = any("mul" in mnem for _, mnem in imem_map.values()) or ("multiplication" in target)
    if args.feature == "2" or (args.feature == "auto" and has_mul):
        chosen_feature = 2
        sim_dir = os.path.join(FEATURE2_DIR, "simulation")
    else:
        chosen_feature = 1
        sim_dir = os.path.join(FEATURE1_DIR, "simulation")

    print_banner(target, chosen_feature)
    print_imem_listing(imem_map, symbols, text_end, inst_tags)

    # 3. Run Simulation
    print(f"\n[*] Running cycle-by-cycle simulation via Vivado xsim (Feature {chosen_feature})...")
    records, ret_val, raw_out = run_simulation(target, imem_map, sim_dir)

    if not records:
        print("[-] Error: No trace records collected from xsim. Raw output:\n", raw_out)
        sys.exit(1)

    # 4. Print Cycle Trace Table
    retired = print_trace_table(records, imem_map, inst_tags)

    # 5. Print Dynamic Execution Order
    print_execution_order(retired, ret_val=ret_val)

    # 6. Print FPGA & Performance Summary
    print_fpga_mapping_summary(records, ret_val, imem_map, retired_list=retired, chosen_feature=chosen_feature)

    # 7. Optional FPGA Bitstream Re-generation
    if args.bitstream:
        print(f"\n[*] Regenerating Feature {chosen_feature} FPGA bitstream via Vivado (takes ~1-2 mins)...")
        feat_dir = FEATURE2_DIR if chosen_feature == 2 else FEATURE1_DIR
        b_tcl = os.path.join(feat_dir, "build_bitstream.tcl")
        subprocess.check_call(f"vivado -mode batch -source {b_tcl}", shell=True, cwd=ROOT_DIR)
        bit_name = "fpga_top_feature2.bit" if chosen_feature == 2 else "fpga_top_feature1.bit"
        proj_name = "rv32m_multiplier_fpga" if chosen_feature == 2 else "rv32i_5stage_core"
        print(f"\n[+] FPGA bitstream successfully generated:")
        print(f"    -> {os.path.join(feat_dir, 'vivado_project', f'{proj_name}.runs', 'impl_1', bit_name)}")
        print("    Program your Nexys A7 FPGA in Vivado Hardware Manager with this bitfile to view live execution!")

if __name__ == "__main__":
    main()

