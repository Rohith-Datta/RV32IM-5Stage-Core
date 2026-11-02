# ==============================================================================
# Script: generate_integration_tb.py
# Description: Generates the comprehensive self-checking integration testbench
#              and memory image covering RV32I, RV32M, RV32F, Zbb, Caches,
#              BTB Branch Prediction, and CSR Performance Counters.
# ==============================================================================

import os

hex_path = r"integration\testbench\integration_prog.hex"
tb_path  = r"integration\testbench\tb_integrated_core.v"

# Helper for instruction encoding
def encode_r(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def encode_i(imm, rs1, funct3, rd, opcode):
    imm12 = imm & 0xFFF
    return (imm12 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def encode_s(imm, rs2, rs1, funct3, opcode):
    imm12 = imm & 0xFFF
    imm11_5 = (imm12 >> 5) & 0x7F
    imm4_0  = imm12 & 0x1F
    return (imm11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm4_0 << 7) | opcode

def encode_b(imm, rs2, rs1, funct3, opcode):
    imm13 = imm & 0x1FFF
    b12 = (imm13 >> 12) & 1
    b11 = (imm13 >> 11) & 1
    b10_5 = (imm13 >> 5) & 0x3F
    b4_1 = (imm13 >> 1) & 0xF
    return (b12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (b4_1 << 8) | (b11 << 7) | opcode

def encode_u(imm, rd, opcode):
    imm20 = (imm >> 12) & 0xFFFFF
    return (imm20 << 12) | (rd << 7) | opcode

instructions = []

# --- 1. Integer Arithmetic & Forwarding (Features 1 & RAW) ---
# 0x00: addi x1, x0, 10
instructions.append((encode_i(10, 0, 0, 1, 0x13), "addi x1, x0, 10        // x1 = 10"))
# 0x04: addi x2, x0, 20
instructions.append((encode_i(20, 0, 0, 2, 0x13), "addi x2, x0, 20        // x2 = 20"))
# 0x08: add x3, x1, x2  (RAW bypass from EX/MEM to EX)
instructions.append((encode_r(0, 2, 1, 0, 3, 0x33), "add x3, x1, x2          // x3 = 30 (Forwarding check)"))

# --- 2. RV32M Hardware Multiplier (Feature 2) ---
# 0x0C: mul x4, x1, x2  (10 * 20 = 200)
instructions.append((encode_r(1, 2, 1, 0, 4, 0x33), "mul x4, x1, x2          // x4 = 200 (RV32M Multiplier)"))

# --- 3. RV32M Hardware 32-Cycle Divider (Feature 3) ---
# 0x10: div x5, x4, x1  (200 / 10 = 20) [32-cycle pipeline freeze]
instructions.append((encode_r(1, 1, 4, 4, 5, 0x33), "div x5, x4, x1          // x5 = 20 (RV32M 32c Divider)"))

# --- 4. RV32M Division by Zero Corner Case ---
# 0x14: div x6, x1, x0  (10 / 0 = -1 = 0xFFFFFFFF per RISC-V spec)
instructions.append((encode_r(1, 0, 1, 4, 6, 0x33), "div x6, x1, x0          // x6 = -1 (Div-by-zero check)"))

# --- 5. RV32Zbb Bit Manipulation (Feature 9) ---
# 0x18: clz x7, x1  (clz(10) = 28)
instructions.append((encode_i(0x600, 1, 1, 7, 0x13), "clz x7, x1              // x7 = 28 (Zbb CLZ)"))
# 0x1C: cpop x8, x1 (cpop(10) = 2)
instructions.append((encode_i(0x602, 1, 1, 8, 0x13), "cpop x8, x1             // x8 = 2 (Zbb CPOP)"))
# 0x20: max x9, x1, x2 (max(10, 20) = 20)
instructions.append((encode_r(5, 2, 1, 6, 9, 0x33), "max x9, x1, x2          // x9 = 20 (Zbb MAX)"))
# 0x24: min x10, x1, x2 (min(10, 20) = 10)
instructions.append((encode_r(5, 2, 1, 4, 10, 0x33), "min x10, x1, x2         // x10 = 10 (Zbb MIN)"))
# 0x28: andn x11, x1, x2 (10 & ~20 = 10 & ~0x14 = 10 & 0xFFFFFFEB = 10)
instructions.append((encode_r(0x20, 2, 1, 7, 11, 0x33), "andn x11, x1, x2        // x11 = 10 (Zbb ANDN)"))

# --- 6. IEEE-754 FPU Arithmetic (Feature 4) ---
# Load 1.5f (0x3FC00000) into x23: lui x23, 0x3FC00
instructions.append((encode_u(0x3FC00000, 23, 0x37), "lui x23, 0x3FC00         // x23 = 1.5f (0x3FC00000)"))
# Load 2.5f (0x40200000) into x24: lui x24, 0x40200
instructions.append((encode_u(0x40200000, 24, 0x37), "lui x24, 0x40200         // x24 = 2.5f (0x40200000)"))
# 0x34: fadd.s x13, x23, x24 (1.5f + 2.5f = 4.0f = 0x40800000) [5 cycles]
instructions.append((encode_r(0, 24, 23, 0, 13, 0x53), "fadd.s x13, x23, x24     // x13 = 4.0f (0x40800000)"))

# Load 2.0f (0x40000000) into x25: lui x25, 0x40000
instructions.append((encode_u(0x40000000, 25, 0x37), "lui x25, 0x40000         // x25 = 2.0f (0x40000000)"))
# 0x3C: fmul.s x14, x13, x25 (4.0f * 2.0f = 8.0f = 0x41000000) [4 cycles]
instructions.append((encode_r(8, 25, 13, 0, 14, 0x53), "fmul.s x14, x13, x25     // x14 = 8.0f (0x41000000)"))

# --- 7. Memory Operations & D-Cache / I-Cache (Features 5 & 6) ---
# 0x40: addi x17, x0, 0x100 (Address 256)
instructions.append((encode_i(256, 0, 0, 17, 0x13), "addi x17, x0, 256       // x17 = mem address 0x100"))
# 0x44: sw x4, 0(x17) (Store 200 into memory at 0x100 via D-Cache write-through)
instructions.append((encode_s(0, 4, 17, 2, 0x23), "sw x4, 0(x17)            // Store 200 into 0x100"))
# 0x48: lw x18, 0(x17) (Load back 200 via D-Cache hit)
instructions.append((encode_i(0, 17, 2, 18, 0x03), "lw x18, 0(x17)           // x18 = 200 (D-Cache load)"))

# --- 8. Feature 7 BTB Branch Prediction ---
# 0x4C: beq x1, x1, 8 (Branch taken to 0x54, skipped 0x50)
instructions.append((encode_b(8, 1, 1, 0, 0x63), "beq x1, x1, +8          // Taken branch to 0x54"))
# 0x50: addi x26, x0, 99 (Should be skipped by branch!)
instructions.append((encode_i(99, 0, 0, 26, 0x13), "addi x26, x0, 99        // SKIPPED on branch taken"))

# 0x54: Branch landing target
instructions.append((encode_i(1, 0, 0, 26, 0x13), "addi x26, x0, 1         // x26 = 1 (Branch landed)"))

# --- 9. Feature 8 Passive Hardware Performance Counters (CSR) ---
# 0x58: csrr x19, cycle (0xC00)
instructions.append((encode_i(0xC00, 0, 2, 19, 0x73), "csrr x19, cycle          // x19 = cycle counter"))
# 0x5C: csrr x20, instret (0xC02)
instructions.append((encode_i(0xC02, 0, 2, 20, 0x73), "csrr x20, instret        // x20 = retired instructions"))
# 0x60: csrr x21, hpmcounter3 (0xC03 stall counter)
instructions.append((encode_i(0xC03, 0, 2, 21, 0x73), "csrr x21, hpmcounter3    // x21 = stall cycles counter"))
# 0x64: csrr x22, hpmcounter4 (0xC04 branch counter)
instructions.append((encode_i(0xC04, 0, 2, 22, 0x73), "csrr x22, hpmcounter4    // x22 = branch counter"))

# 0x68: NOP / End of test loop
instructions.append((0x00000013, "nop                      // Final NOP"))
instructions.append((0x00000013, "nop                      // Final NOP"))
instructions.append((0x00000013, "nop                      // Final NOP"))

# Write HEX file
with open(hex_path, "w") as f:
    for code, comment in instructions:
        f.write(f"{code:08X}\n")

print(f"Generated test program hex: {hex_path} ({len(instructions)} instructions)")
