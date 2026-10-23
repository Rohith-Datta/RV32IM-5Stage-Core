#!/usr/bin/env python3
# ============================================================================
# File: run_pipeline_trace.py
# Description: Interactive Pipeline Simulation & Cycle-by-Cycle Terminal Visualizer
# Project: 5-Stage RV32IMF Processor Core (Feature 5: Direct-Mapped L1 D-Cache)
#
# Features:
# 1. Shows cycle-by-cycle pipeline progression across IF, ID, EX, MEM, WB stages.
# 2. Explains what instruction is in each stage (address + mnemonic).
# 3. Highlights in real-time when:
#    - L1 D-Cache Read Miss Stall occurs (10 cycles) -> FPGA LED[0] & LED[9] ON
#    - L1 D-Cache Read Hit occurs -> FPGA LED[8] ON
#    - Multi-cycle Divider Interlock Stall occurs (32 cycles) -> FPGA LED[0] & LED[5] ON
#    - Multi-cycle FPU Interlock Stall occurs (4c/5c/15c) -> FPGA LED[0] & LED[6] ON
#    - Data Hazard is detected (Load-Use Stall) -> FPGA LED[0] ON
#    - Data Forwarding is active (EX/MEM or MEM/WB bypass) -> FPGA LED[1] ON
#    - A Branch / Speculative Flush occurs -> FPGA LED[2] ON
# 4. Notes the current Fetch Address on the FPGA 8-digit 7-segment display.
# 5. Displays the static Instruction Memory listing and the dynamic execution order.
# ============================================================================

import os
import sys
import subprocess
import re
import argparse
import shutil

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
if os.path.basename(CURRENT_DIR) in ("feature_1", "feature_2", "feature_3", "feature_4", "feature_5"):
    ROOT_DIR = os.path.dirname(CURRENT_DIR)
else:
    ROOT_DIR = CURRENT_DIR

FEATURE5_DIR = os.path.join(ROOT_DIR, "feature_5")
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
    """Decodes a 32-bit RV32I/M/F machine word into assembly mnemonic."""
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
    elif opcode == 0x53:  # OP_FP (RV32F)
        fp_names = {0x00: 'fadd.s', 0x04: 'fsub.s', 0x10: 'fmul.s', 0x0C: 'fdiv.s'}
        name = fp_names.get(funct7, f"fp_0x{funct7:02x}")
        return f"{name} {r_d}, {r_1}, {r_2}"
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

def main():
    parser = argparse.ArgumentParser(description="Feature 5: 5-Stage RV32IMF Processor Pipeline Trace Visualizer")
    parser.add_argument("target", nargs="?", default="addition", help="Target test program")
    args = parser.parse_args()

    print("=" * 116)
    print("       RV32IMF 5-STAGE PIPELINE TRACE VISUALIZER WITH L1 D-CACHE")
    print("       Core Engine: FEATURE 5 (Direct-Mapped 2 KB L1 Data Cache @ 50 MHz)")
    print("=" * 116)

    build_script = os.path.join(C_TESTS_DIR, "build_hex.py")
    print(f"[*] Building target program '{args.target}' via {build_script}...")
    subprocess.check_call([sys.executable, build_script, args.target], cwd=ROOT_DIR)

    f5_mem = os.path.join(FEATURE5_DIR, "mem")
    f5_imem_hex = os.path.join(f5_mem, "imem.hex")
    imem_map = load_imem_map(f5_imem_hex)

    print(f"\n[*] Loaded {len(imem_map)} instructions from {f5_imem_hex}")
    print("[*] Elaborating and simulating via Vivado xsim in feature_5/simulation...")

    sim_dir = os.path.join(FEATURE5_DIR, "simulation")
    subprocess.run("xelab -top tb_pipeline_base -snapshot snap_tb_base -debug typical", cwd=sim_dir, capture_output=True, text=True, shell=True)
    proc = subprocess.run("xsim snap_tb_base -runall", cwd=sim_dir, capture_output=True, text=True, shell=True)
    print(proc.stdout)

if __name__ == "__main__":
    main()
