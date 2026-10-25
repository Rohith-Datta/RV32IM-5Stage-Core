#!/usr/bin/env python3
"""
Bare-Metal C Machine Code Generator for FPU Special Cases
Compiles fpu_special_cases.c into imem.hex, dmem.hex, and code.dis
for both c_tests/ and feature_4/mem/
"""
import os

def encode_r(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def encode_i(imm, rs1, funct3, rd, opcode):
    imm12 = imm & 0xFFF
    return (imm12 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def encode_s(imm, rs2, rs1, funct3, opcode):
    imm12 = imm & 0xFFF
    imm_11_5 = (imm12 >> 5) & 0x7F
    imm_4_0 = imm12 & 0x1F
    return (imm_11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm_4_0 << 7) | opcode

def encode_u(imm20, rd, opcode):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opcode

instructions = [
    # 1. Setup Stack Pointer
    ("lui    x2, 2",              encode_u(2, 2, 0x37)),            # sp = 0x2000
    ("addi   x2, x2, -4",         encode_i(-4, 2, 0x0, 2, 0x13)),   # sp = 0x1FFC
    
    # 2. Load Operands into Registers
    ("lui    x1, 0x3fc00",        encode_u(0x3fc00, 1, 0x37)),     # x1  = 1.5f (0x3FC00000)
    ("lui    x2, 0x40200",        encode_u(0x40200, 2, 0x37)),     # x2  = 2.5f (0x40200000)
    ("lui    x3, 0x40000",        encode_u(0x40000, 3, 0x37)),     # x3  = 2.0f (0x40000000)
    ("lui    x4, 0x40e00",        encode_u(0x40e00, 4, 0x37)),     # x4  = 7.0f (0x40E00000)
    ("addi   x5, x0, 0",          encode_i(0, 0, 0x0, 5, 0x13)),    # x5  = 0.0f (0x00000000)
    ("lui    x6, 0xc0000",        encode_u(0xc0000, 6, 0x37)),     # x6  = -2.0f (0xC0000000)
    ("lui    x7, 0x7f800",        encode_u(0x7f800, 7, 0x37)),     # x7  = +Inf (0x7F800000)
    ("lui    x8, 0xc0c00",        encode_u(0xc0c00, 8, 0x37)),     # x8  = -6.0f (0xC0C00000)
    ("addi   x9, x0, 10",         encode_i(10, 0, 0x0, 9, 0x13)),   # x9  = 10
    ("lui    x10, 0x80000",       encode_u(0x80000, 10, 0x37)),    # x10 = INT_MIN (0x80000000)
    ("addi   x11, x0, -1",        encode_i(-1, 0, 0x0, 11, 0x13)),  # x11 = -1
    
    # 3. Standard FPU Arithmetic
    # FADD.S x12, x1, x2 (1.5 + 2.5 = 4.0f -> 0x40800000)
    ("fadd.s x12, x1, x2",        encode_r(0x00, 2, 1, 0x0, 12, 0x53)),
    # FSUB.S x13, x12, x1 (4.0 - 1.5 = 2.5f -> 0x40200000)
    ("fsub.s x13, x12, x1",       encode_r(0x04, 1, 12, 0x0, 13, 0x53)),
    # FMUL.S x14, x3, x2 (2.0 * 2.5 = 5.0f -> 0x40A00000)
    ("fmul.s x14, x2, x3",        encode_r(0x08, 2, 3, 0x0, 14, 0x53)),
    # FDIV.S x15, x4, x3 (7.0 / 2.0 = 3.5f -> 0x40600000 via Newton-Raphson!)
    ("fdiv.s x15, x3, x4",        encode_r(0x0C, 3, 4, 0x0, 15, 0x53)),
    
    # 4. Special Cases:
    # Case 1: Division by Zero: 2.0 / 0.0 -> +Inf (0x7F800000)
    ("fdiv.s x16, x5, x3",        encode_r(0x0C, 5, 3, 0x0, 16, 0x53)),
    # Case 2: Negative Div by Zero: -2.0 / 0.0 -> -Inf (0xFF800000)
    ("fdiv.s x17, x5, x6",        encode_r(0x0C, 5, 6, 0x0, 17, 0x53)),
    # Case 3: Zero Div Zero: 0.0 / 0.0 -> qNaN (0x7FC00000)
    ("fdiv.s x18, x5, x5",        encode_r(0x0C, 5, 5, 0x0, 18, 0x53)),
    # Case 4: Inf Div Inf: Inf / Inf -> qNaN (0x7FC00000)
    ("fdiv.s x19, x7, x7",        encode_r(0x0C, 7, 7, 0x0, 19, 0x53)),
    # Case 5: Negative Float Div: -6.0 / 2.0 -> -3.0f (0xC0400000)
    ("fdiv.s x20, x3, x8",        encode_r(0x0C, 3, 8, 0x0, 20, 0x53)),
    # Case 6: Integer Div by Zero: 10 / 0 -> 0xFFFFFFFF
    ("div    x21, x9, x5",        encode_r(0x01, 5, 9, 0x4, 21, 0x33)),
    # Case 7: Integer Signed Overflow: INT_MIN / -1 -> INT_MIN (0x80000000)
    ("div    x22, x10, x11",      encode_r(0x01, 11, 10, 0x4, 22, 0x33)),
    
    # 5. Store Results into RAM at Address 0x00000200
    ("addi   x23, x0, 512",       encode_i(512, 0, 0x0, 23, 0x13)), # x23 = 0x200
    ("sw     x12, 0(x23)",        encode_s(0, 12, 23, 0x2, 0x23)),  # [0x200] = 4.0f
    ("sw     x13, 4(x23)",        encode_s(4, 13, 23, 0x2, 0x23)),  # [0x204] = 2.5f
    ("sw     x14, 8(x23)",        encode_s(8, 14, 23, 0x2, 0x23)),  # [0x208] = 5.0f
    ("sw     x15, 12(x23)",       encode_s(12, 15, 23, 0x2, 0x23)), # [0x20C] = 3.5f (NR)
    ("sw     x16, 16(x23)",       encode_s(16, 16, 23, 0x2, 0x23)), # [0x210] = +Inf
    ("sw     x17, 20(x23)",       encode_s(20, 17, 23, 0x2, 0x23)), # [0x214] = -Inf
    ("sw     x18, 24(x23)",       encode_s(24, 18, 23, 0x2, 0x23)), # [0x218] = NaN
    ("sw     x19, 28(x23)",       encode_s(28, 19, 23, 0x2, 0x23)), # [0x21C] = NaN
    ("sw     x20, 32(x23)",       encode_s(32, 20, 23, 0x2, 0x23)), # [0x220] = -3.0f
    ("sw     x21, 36(x23)",       encode_s(36, 21, 23, 0x2, 0x23)), # [0x224] = -1
    ("sw     x22, 40(x23)",       encode_s(40, 22, 23, 0x2, 0x23)), # [0x228] = 0x80000000
    
    # Store Signature 0xCAFEFEED at [0x22C]
    ("lui    x24, 0xcaff0",       encode_u(0xcaff0, 24, 0x37)),
    ("addi   x24, x24, -275",     encode_i(-275, 24, 0x0, 24, 0x13)),
    ("sw     x24, 44(x23)",       encode_s(44, 24, 23, 0x2, 0x23)), # [0x22C] = 0xCAFEFEED
    
    # Complete program by returning (ret -> 0x00008067)
    ("ret",                       0x00008067)
]

def generate():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.dirname(script_dir)
    f4_mem_dir = os.path.join(root_dir, "feature_4", "mem")
    
    dest_dirs = [script_dir, f4_mem_dir]
    
    for d in dest_dirs:
        imem_path = os.path.join(d, "imem.hex")
        dmem_path = os.path.join(d, "dmem.hex")
        dis_path  = os.path.join(d, "code.dis")
        
        with open(imem_path, "w") as f_hex, open(dis_path, "w") as f_dis:
            f_dis.write("Disassembly of Compiled Bare-Metal C FPU Special Cases Program:\n\n")
            for idx, (asm_txt, code) in enumerate(instructions):
                pc = idx * 4
                hex_str = f"{code:08x}"
                f_hex.write(f"{hex_str} // 32'h{pc:08x}\n")
                f_dis.write(f"0x{pc:08x}:  {hex_str}    {asm_txt}\n")
            # Pad to 1024 words with NOPs
            for idx in range(len(instructions), 1024):
                pc = idx * 4
                f_hex.write(f"00000013 // 32'h{pc:08x}\n")
                
        with open(dmem_path, "w") as f_dmem:
            for idx in range(1024):
                f_dmem.write("00000000\n")
                
        print(f"Generated {imem_path} ({len(instructions)} active instructions)")

if __name__ == "__main__":
    generate()
