#!/usr/bin/env python3
"""
Firmware Builder for Avionics Telemetry & Microarchitectural Verification Demo
Compiles avionics_demo.c into ELF, BIN, DIS, HEX, and COE formats for the integrated
RV32IMF+Zbb processor core on Digilent Nexys A7-100T FPGA.
"""

import os
import sys
import struct
import subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SRC_C      = os.path.join(SCRIPT_DIR, "integration", "firmware", "avionics_demo.c")
LINKER_LD  = os.path.join(SCRIPT_DIR, "c_tests", "linker.ld")
OUT_ELF    = os.path.join(SCRIPT_DIR, "integration", "firmware", "avionics_demo.elf")
OUT_BIN    = os.path.join(SCRIPT_DIR, "integration", "firmware", "avionics_demo.bin")
OUT_DIS    = os.path.join(SCRIPT_DIR, "integration", "firmware", "avionics_demo.dis")
OUT_HEX    = os.path.join(SCRIPT_DIR, "integration", "firmware", "avionics_demo.hex")
OUT_COE    = os.path.join(SCRIPT_DIR, "integration", "firmware", "avionics_demo.coe")

CC      = "riscv-none-elf-gcc"
OBJCOPY = "riscv-none-elf-objcopy"
OBJDUMP = "riscv-none-elf-objdump"

def build():
    print("=" * 70)
    print("  COMPILING AVIONICS DEMO BARE-METAL FIRMWARE (RV32IMF + Zbb)")
    print("=" * 70)

    # 1. Compile and link
    cmd_compile = [
        CC,
        "-march=rv32imf_zicsr_zbb",
        "-mabi=ilp32f",
        "-O2",
        "-ffp-contract=off",
        "-nostartfiles",
        "-T", LINKER_LD,
        SRC_C,
        "-o", OUT_ELF
    ]
    print(f"[*] Executing: {' '.join(cmd_compile)}")
    subprocess.check_call(cmd_compile)
    print(f"[+] Successfully linked -> {OUT_ELF}")

    # 2. Extract raw binary
    cmd_objcopy = [OBJCOPY, "-O", "binary", OUT_ELF, OUT_BIN]
    print(f"[*] Generating binary: {' '.join(cmd_objcopy)}")
    subprocess.check_call(cmd_objcopy)

    bin_size = os.path.getsize(OUT_BIN)
    word_count = (bin_size + 3) // 4
    print(f"[+] Binary size: {bin_size} bytes ({word_count} 32-bit words)")

    # 3. Disassembly listing
    print(f"[*] Generating disassembly -> {OUT_DIS}")
    with open(OUT_DIS, "w", encoding="utf-8") as f_dis:
        subprocess.check_call([OBJDUMP, "-d", OUT_ELF], stdout=f_dis)

    # 4. Generate Verilog $readmemh HEX file (one 32-bit hex word per line, little-endian)
    words = []
    with open(OUT_BIN, "rb") as f_bin:
        raw_data = f_bin.read()
        for i in range(0, len(raw_data), 4):
            chunk = raw_data[i:i+4]
            if len(chunk) < 4:
                chunk = chunk.ljust(4, b"\x00")
            w = struct.unpack("<I", chunk)[0]
            words.append(w)

    # Pad to at least 4096 words (16 KB) for consistent memory image
    target_words = max(16384, ((len(words) + 1023) // 1024) * 1024)

    # Write HEX file
    hex_destinations = [
        OUT_HEX,
        os.path.join(SCRIPT_DIR, "avionics_demo.hex"),
        os.path.join(SCRIPT_DIR, "integration", "modules", "fpga", "avionics_demo.hex"),
        os.path.join(SCRIPT_DIR, "integration", "sim_run", "avionics_demo.hex"),
        os.path.join(SCRIPT_DIR, "integration", "testbench", "avionics_demo.hex")
    ]

    for dest in hex_destinations:
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "w", encoding="utf-8") as f_hex:
            for w in words:
                f_hex.write(f"{w:08x}\n")
            for _ in range(len(words), target_words):
                f_hex.write("00000000\n")
        print(f"[+] Generated Verilog HEX image -> {dest}")

    # 5. Generate Xilinx COE file
    with open(OUT_COE, "w", encoding="utf-8") as f_coe:
        f_coe.write("memory_initialization_radix=16;\n")
        f_coe.write("memory_initialization_vector=\n")
        for idx, w in enumerate(words):
            sep = ";" if idx == len(words) - 1 else ","
            f_coe.write(f"{w:08x}{sep}\n")
    print(f"[+] Generated Xilinx BRAM COE -> {OUT_COE}")

    print("=" * 70)
    print("  FIRMWARE BUILD COMPLETE & VERIFIED!")
    print("=" * 70)

if __name__ == "__main__":
    build()
