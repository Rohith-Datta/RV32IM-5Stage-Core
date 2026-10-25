#!/usr/bin/env python3
# ==============================================================================
# File: tools/riscv_as.py
# Description: Pure-Python RV32IMF Assembler and ELF32 Generator
# Assembles RISC-V assembly (.s / .asm) into ELF binary, imem.hex, and dmem.hex
# Works on any machine without requiring riscv-none-elf-gcc
# ==============================================================================

import os
import sys
import re
import struct
import argparse

# Register mapping (ABI names + x0-x31 + f0-f31)
REG_MAP = {
    "zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4,
    "t0": 5, "t1": 6, "t2": 7, "s0": 8, "fp": 8, "s1": 9,
    "a0": 10, "a1": 11, "a2": 12, "a3": 13, "a4": 14, "a5": 15, "a6": 16, "a7": 17,
    "s2": 18, "s3": 19, "s4": 20, "s5": 21, "s6": 22, "s7": 23, "s8": 24, "s9": 25, "s10": 26, "s11": 27,
    "t3": 28, "t4": 29, "t5": 30, "t6": 31,
}
for i in range(32):
    REG_MAP[f"x{i}"] = i
    REG_MAP[f"f{i}"] = i
# Floating point ABI names
FP_ABI = {
    "ft0": 0, "ft1": 1, "ft2": 2, "ft3": 3, "ft4": 4, "ft5": 5, "ft6": 6, "ft7": 7,
    "fs0": 8, "fs1": 9, "fa0": 10, "fa1": 11, "fa2": 12, "fa3": 13, "fa4": 14, "fa5": 15,
    "fa6": 16, "fa7": 17, "fs2": 18, "fs3": 19, "fs4": 20, "fs5": 21, "fs6": 22, "fs7": 23,
    "fs8": 24, "fs9": 25, "fs10": 26, "fs11": 27, "ft8": 28, "ft9": 29, "ft10": 30, "ft11": 31
}
REG_MAP.update(FP_ABI)

def parse_reg(reg_str):
    reg = reg_str.strip().lower()
    if reg in REG_MAP:
        return REG_MAP[reg]
    raise ValueError(f"Unknown register name: '{reg_str}'")

def parse_imm(imm_str, symbols=None, current_pc=0):
    s = imm_str.strip()
    if symbols and s in symbols:
        return symbols[s]
    # Check for %hi / %lo
    m_hi = re.match(r'%hi\((.*)\)', s)
    if m_hi:
        target = parse_imm(m_hi.group(1), symbols, current_pc)
        return (target + 0x800) >> 12
    m_lo = re.match(r'%lo\((.*)\)', s)
    if m_lo:
        target = parse_imm(m_lo.group(1), symbols, current_pc)
        return target & 0xFFF

    if s.startswith("0x") or s.startswith("0X"):
        return int(s, 16)
    if s.startswith("0b") or s.startswith("0B"):
        return int(s, 2)
    return int(s, 10)

def enc_r(f7, rs2, rs1, f3, rd, op):
    return ((f7 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | ((f3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (op & 0x7F)

def enc_i(imm, rs1, f3, rd, op):
    return ((imm & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | ((f3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (op & 0x7F)

def enc_s(imm, rs2, rs1, f3, op):
    imm11_5 = (imm >> 5) & 0x7F
    imm4_0  = imm & 0x1F
    return (imm11_5 << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | ((f3 & 0x7) << 12) | (imm4_0 << 7) | (op & 0x7F)

def enc_b(imm, rs2, rs1, f3, op):
    b12   = (imm >> 12) & 0x1
    b10_5 = (imm >> 5) & 0x3F
    b4_1  = (imm >> 1) & 0xF
    b11   = (imm >> 11) & 0x1
    return (b12 << 31) | (b10_5 << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | ((f3 & 0x7) << 12) | (b4_1 << 8) | (b11 << 7) | (op & 0x7F)

def enc_u(imm, rd, op):
    return ((imm & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | (op & 0x7F)

def enc_j(imm, rd, op):
    b20    = (imm >> 20) & 0x1
    b10_1  = (imm >> 1) & 0x3FF
    b11    = (imm >> 11) & 0x1
    b19_12 = (imm >> 12) & 0xFF
    return (b20 << 31) | (b10_1 << 21) | (b11 << 20) | (b19_12 << 12) | ((rd & 0x1F) << 7) | (op & 0x7F)

# Memory offset parser: 4(sp) or -8(x2)
def parse_mem_op(mem_str):
    m = re.match(r'([^(]+)\(([^)]+)\)', mem_str.strip())
    if m:
        offset_str = m.group(1).strip()
        reg_str = m.group(2).strip()
        return offset_str, reg_str
    raise ValueError(f"Invalid memory operand format: '{mem_str}'")

class RISCVAssembler:
    def __init__(self):
        self.symbols = {}
        self.instructions = [] # (pc, original_line, mnemonic, args)
        self.data_bytes = bytearray()
        self.data_base = 0x00000200 # RAM offset for data section
        self.current_section = ".text"

    def assemble_source(self, source_text):
        lines = source_text.splitlines()
        
        # -------------------------------------------------------------
        # PASS 1: Parse labels, instructions, pseudo-instructions, directives
        # -------------------------------------------------------------
        current_pc = 0x00000000
        current_data_addr = self.data_base
        
        raw_ops = []

        for line_num, orig_line in enumerate(lines, start=1):
            line = orig_line.strip()
            # Remove comments (// or # or /* */)
            line = re.sub(r'//.*$', '', line)
            line = re.sub(r'#.*$', '', line)
            line = re.sub(r'/\*.*?\*/', '', line).strip()
            if not line:
                continue

            # Check Section Directives
            if line.startswith("."):
                parts = line.split(None, 1)
                directive = parts[0]
                rest = parts[1].strip() if len(parts) > 1 else ""

                if directive in [".text", ".section .text"]:
                    self.current_section = ".text"
                elif directive in [".data", ".rodata", ".section .data"]:
                    self.current_section = ".data"
                elif directive in [".globl", ".global"]:
                    pass # ignore symbol visibility
                elif directive == ".equ":
                    eq_parts = [p.strip() for p in rest.split(",", 1)]
                    val = parse_imm(eq_parts[1], self.symbols)
                    self.symbols[eq_parts[0]] = val
                elif directive == ".word":
                    vals = [p.strip() for p in rest.split(",")]
                    for v in vals:
                        val_num = parse_imm(v, self.symbols)
                        self.data_bytes.extend(struct.pack("<I", val_num & 0xFFFFFFFF))
                        current_data_addr += 4
                elif directive == ".byte":
                    vals = [p.strip() for p in rest.split(",")]
                    for v in vals:
                        val_num = parse_imm(v, self.symbols)
                        self.data_bytes.append(val_num & 0xFF)
                        current_data_addr += 1
                elif directive in [".string", ".asciz"]:
                    m_str = re.search(r'"(.*)"', rest)
                    if m_str:
                        s_val = bytes(m_str.group(1), "utf-8").decode("unicode_escape").encode("utf-8") + b'\x00'
                        self.data_bytes.extend(s_val)
                        current_data_addr += len(s_val)
                continue

            # Check for Label(s)
            while ":" in line:
                colon_idx = line.find(":")
                label_name = line[:colon_idx].strip()
                if label_name:
                    if self.current_section == ".text":
                        self.symbols[label_name] = current_pc
                    else:
                        self.symbols[label_name] = current_data_addr
                line = line[colon_idx + 1:].strip()

            if not line:
                continue

            # Parse Instruction & Arguments
            parts = line.split(None, 1)
            mnemonic = parts[0].lower()
            arg_str = parts[1] if len(parts) > 1 else ""
            args = [a.strip() for a in arg_str.split(",") if a.strip()]

            # Handle Pseudo-Instructions that expand to multiple real instructions
            if mnemonic == "li":
                # li rd, imm -> lui rd, hi / addi rd, rd, lo OR addi rd, x0, imm
                rd = args[0]
                imm_val = parse_imm(args[1], self.symbols)
                if -2048 <= imm_val <= 2047:
                    raw_ops.append((current_pc, orig_line, "addi", [rd, "zero", str(imm_val)]))
                    current_pc += 4
                else:
                    hi = (imm_val + 0x800) >> 12
                    lo = imm_val - (hi << 12)
                    raw_ops.append((current_pc, orig_line, "lui", [rd, f"0x{hi & 0xFFFFF:x}"]))
                    current_pc += 4
                    raw_ops.append((current_pc, orig_line, "addi", [rd, rd, str(lo)]))
                    current_pc += 4
            elif mnemonic == "la":
                # la rd, symbol -> lui rd, %hi(symbol) / addi rd, rd, %lo(symbol)
                rd = args[0]
                sym = args[1]
                raw_ops.append((current_pc, orig_line, "lui", [rd, f"%hi({sym})"]))
                current_pc += 4
                raw_ops.append((current_pc, orig_line, "addi", [rd, rd, f"%lo({sym})"]))
                current_pc += 4
            elif mnemonic == "nop":
                raw_ops.append((current_pc, orig_line, "addi", ["zero", "zero", "0"]))
                current_pc += 4
            elif mnemonic == "ret":
                raw_ops.append((current_pc, orig_line, "jalr", ["zero", "ra", "0"]))
                current_pc += 4
            elif mnemonic == "j":
                raw_ops.append((current_pc, orig_line, "jal", ["zero", args[0]]))
                current_pc += 4
            elif mnemonic == "jr":
                raw_ops.append((current_pc, orig_line, "jalr", ["zero", args[0], "0"]))
                current_pc += 4
            elif mnemonic == "mv":
                raw_ops.append((current_pc, orig_line, "addi", [args[0], args[1], "0"]))
                current_pc += 4
            elif mnemonic == "not":
                raw_ops.append((current_pc, orig_line, "xori", [args[0], args[1], "-1"]))
                current_pc += 4
            elif mnemonic == "neg":
                raw_ops.append((current_pc, orig_line, "sub", [args[0], "zero", args[1]]))
                current_pc += 4
            elif mnemonic == "beqz":
                raw_ops.append((current_pc, orig_line, "beq", [args[0], "zero", args[1]]))
                current_pc += 4
            elif mnemonic == "bnez":
                raw_ops.append((current_pc, orig_line, "bne", [args[0], "zero", args[1]]))
                current_pc += 4
            else:
                raw_ops.append((current_pc, orig_line, mnemonic, args))
                current_pc += 4

        # -------------------------------------------------------------
        # PASS 2: Encode machine instructions
        # -------------------------------------------------------------
        compiled_words = []
        disassembly = []

        for pc, orig_line, mnemonic, args in raw_ops:
            word = self.encode_inst(pc, mnemonic, args)
            compiled_words.append((pc, word, orig_line, mnemonic, args))
            disassembly.append(f"0x{pc:08x}:  {word:08x}    {orig_line.strip()}")

        return compiled_words, disassembly

    def encode_inst(self, pc, m, args):
        # 1. R-Type (Opcode: 0x33)
        r_ops = {
            "add": (0x00, 0x0), "sub": (0x20, 0x0), "sll": (0x00, 0x1), "slt": (0x00, 0x2),
            "sltu": (0x00, 0x3), "xor": (0x00, 0x4), "srl": (0x00, 0x5), "sra": (0x20, 0x5),
            "or": (0x00, 0x6), "and": (0x00, 0x7),
            # M-Extension
            "mul": (0x01, 0x0), "mulh": (0x01, 0x1), "mulhsu": (0x01, 0x2), "mulhu": (0x01, 0x3),
            "div": (0x01, 0x4), "divu": (0x01, 0x5), "rem": (0x01, 0x6), "remu": (0x01, 0x7),
        }
        if m in r_ops:
            rd = parse_reg(args[0])
            rs1 = parse_reg(args[1])
            rs2 = parse_reg(args[2])
            f7, f3 = r_ops[m]
            return enc_r(f7, rs2, rs1, f3, rd, 0x33)

        # 2. FPU R-Type (Opcode: 0x53)
        fp_ops = {
            "fadd.s": 0x00, "fsub.s": 0x04, "fmul.s": 0x08, "fdiv.s": 0x0C
        }
        if m in fp_ops:
            rd = parse_reg(args[0])
            rs1 = parse_reg(args[1])
            rs2 = parse_reg(args[2])
            f7 = fp_ops[m]
            return enc_r(f7, rs2, rs1, 0x0, rd, 0x53)

        # 3. I-Type Arithmetic (Opcode: 0x13)
        i_ops = {
            "addi": 0x0, "slti": 0x2, "sltiu": 0x3, "xori": 0x4, "ori": 0x6, "andi": 0x7
        }
        if m in i_ops:
            rd = parse_reg(args[0])
            rs1 = parse_reg(args[1])
            imm = parse_imm(args[2], self.symbols, pc)
            return enc_i(imm, rs1, i_ops[m], rd, 0x13)

        if m in ["slli", "srli", "srai"]:
            rd = parse_reg(args[0])
            rs1 = parse_reg(args[1])
            shamt = parse_imm(args[2], self.symbols, pc) & 0x1F
            if m == "slli": return enc_r(0x00, shamt, rs1, 0x1, rd, 0x13)
            if m == "srli": return enc_r(0x00, shamt, rs1, 0x5, rd, 0x13)
            if m == "srai": return enc_r(0x20, shamt, rs1, 0x5, rd, 0x13)

        # 4. Load Instructions (Opcode: 0x03 / 0x07)
        load_ops = {
            "lb": (0x0, 0x03), "lh": (0x1, 0x03), "lw": (0x2, 0x03),
            "lbu": (0x4, 0x03), "lhu": (0x5, 0x03), "flw": (0x2, 0x07)
        }
        if m in load_ops:
            rd = parse_reg(args[0])
            offset_str, rs1_str = parse_mem_op(args[1])
            rs1 = parse_reg(rs1_str)
            imm = parse_imm(offset_str, self.symbols, pc)
            f3, op = load_ops[m]
            return enc_i(imm, rs1, f3, rd, op)

        # 5. Store Instructions (Opcode: 0x23 / 0x27)
        store_ops = {
            "sb": (0x0, 0x23), "sh": (0x1, 0x23), "sw": (0x2, 0x23), "fsw": (0x2, 0x27)
        }
        if m in store_ops:
            rs2 = parse_reg(args[0])
            offset_str, rs1_str = parse_mem_op(args[1])
            rs1 = parse_reg(rs1_str)
            imm = parse_imm(offset_str, self.symbols, pc)
            f3, op = store_ops[m]
            return enc_s(imm, rs2, rs1, f3, op)

        # 6. Branch Instructions (Opcode: 0x63)
        b_ops = {
            "beq": 0x0, "bne": 0x1, "blt": 0x4, "bge": 0x5, "bltu": 0x6, "bgeu": 0x7
        }
        if m in b_ops:
            rs1 = parse_reg(args[0])
            rs2 = parse_reg(args[1])
            target = parse_imm(args[2], self.symbols, pc)
            offset = target - pc
            return enc_b(offset, rs2, rs1, b_ops[m], 0x63)

        # 7. U-Type Instructions
        if m == "lui":
            rd = parse_reg(args[0])
            imm = parse_imm(args[1], self.symbols, pc)
            return enc_u(imm, rd, 0x37)
        if m == "auipc":
            rd = parse_reg(args[0])
            imm = parse_imm(args[1], self.symbols, pc)
            return enc_u(imm, rd, 0x17)

        # 8. Jumps (Opcode: 0x6F / 0x67)
        if m == "jal":
            rd = parse_reg(args[0]) if len(args) == 2 else 1 # default ra
            target_str = args[1] if len(args) == 2 else args[0]
            target = parse_imm(target_str, self.symbols, pc)
            offset = target - pc
            return enc_j(offset, rd, 0x6F)

        if m == "jalr":
            rd = parse_reg(args[0])
            offset_str, rs1_str = parse_mem_op(args[1]) if "(" in args[1] else (args[2] if len(args) > 2 else "0", args[1])
            rs1 = parse_reg(rs1_str)
            imm = parse_imm(offset_str, self.symbols, pc)
            return enc_i(imm, rs1, 0x0, rd, 0x67)

        raise ValueError(f"Unsupported instruction or directive: '{m}' at PC=0x{pc:08x}")

    def generate_elf32(self, code_words, output_elf_path):
        """
        Generates a standard ELF32 executable binary containing the code and data.
        """
        code_bytes = bytearray()
        for _, word, _, _, _ in code_words:
            code_bytes.extend(struct.pack("<I", word))

        code_size = len(code_bytes)
        data_size = len(self.data_bytes)

        # ELF Header (52 bytes) + 2 Program Headers (32 bytes * 2 = 64 bytes)
        ehdr_size = 52
        ph_size = 32
        ph_count = 2 if data_size > 0 else 1
        headers_size = ehdr_size + ph_count * ph_size

        code_offset = headers_size
        data_offset = code_offset + code_size

        # Program Header 1: Code (.text)
        # Type=PT_LOAD(1), offset, vaddr=0x00000000, paddr=0x00000000, filesz, memsz, flags=PF_R|PF_X(5), align=4
        ph_code = struct.pack("<IIIIIIII", 1, code_offset, 0x00000000, 0x00000000, code_size, code_size, 5, 4)

        # Program Header 2: Data (.data)
        ph_data = b""
        if data_size > 0:
            # Type=PT_LOAD(1), offset, vaddr=self.data_base, paddr=self.data_base, filesz, memsz, flags=PF_R|PF_W(6), align=4
            ph_data = struct.pack("<IIIIIIII", 1, data_offset, self.data_base, self.data_base, data_size, data_size, 6, 4)

        # ELF Header
        # e_ident: \x7fELF (32-bit, Little-endian, version 1)
        e_ident = b'\x7fELF\x01\x01\x01\x00' + b'\x00' * 8
        e_type = 2      # ET_EXEC
        e_machine = 243 # EM_RISCV
        e_version = 1
        e_entry = 0x00000000
        e_phoff = ehdr_size
        e_shoff = 0
        e_flags = 0
        e_ehsize = ehdr_size
        e_phentsize = ph_size
        e_phnum = ph_count
        e_shentsize = 40
        e_shnum = 0
        e_shstrndx = 0

        ehdr = struct.pack("<16sHHIIIIIHHHHHH", e_ident, e_type, e_machine, e_version, e_entry,
                           e_phoff, e_shoff, e_flags, e_ehsize, e_phentsize, e_phnum,
                           e_shentsize, e_shnum, e_shstrndx)

        with open(output_elf_path, "wb") as f:
            f.write(ehdr)
            f.write(ph_code)
            if ph_data:
                f.write(ph_data)
            f.write(code_bytes)
            if self.data_bytes:
                f.write(self.data_bytes)

    def generate_hex_files(self, code_words, imem_hex_path, dmem_hex_path, total_words=1024):
        # 1. IMEM: Write instructions, pad remainder with NOP (00000013)
        with open(imem_hex_path, "w") as f_imem:
            for idx in range(total_words):
                pc = idx * 4
                if idx < len(code_words):
                    val = code_words[idx][1]
                else:
                    val = 0x00000013 # NOP
                f_imem.write(f"{val:08x} // 32'h{pc:08x}\n")

        # 2. DMEM: Write data words, pad with 00000000
        data_words = []
        for i in range(0, len(self.data_bytes), 4):
            chunk = self.data_bytes[i:i+4]
            if len(chunk) < 4:
                chunk = chunk.ljust(4, b'\x00')
            val = struct.unpack("<I", chunk)[0]
            data_words.append(val)

        with open(dmem_hex_path, "w") as f_dmem:
            for idx in range(total_words):
                addr = idx * 4
                # Data section starts at self.data_base
                data_word_idx = idx - (self.data_base // 4)
                if 0 <= data_word_idx < len(data_words):
                    val = data_words[data_word_idx]
                else:
                    val = 0x00000000
                f_dmem.write(f"{val:08x} // 32'h{addr:08x}\n")

def assemble_file(src_path, elf_path=None, imem_path=None, dmem_path=None, dis_path=None):
    with open(src_path, "r") as f:
        src_text = f.read()

    src_dir = os.path.dirname(os.path.abspath(src_path))
    base_name = os.path.splitext(os.path.basename(src_path))[0]
    elf_out  = elf_path or os.path.join(src_dir, f"{base_name}.elf")
    imem_out = imem_path or os.path.join(src_dir, "imem.hex")
    dmem_out = dmem_path or os.path.join(src_dir, "dmem.hex")
    dis_out  = dis_path or os.path.join(src_dir, f"{base_name}.dis")

    asmb = RISCVAssembler()
    code_words, dis = asmb.assemble_source(src_text)

    # 1. Write Disassembly
    with open(dis_out, "w") as f_dis:
        f_dis.write(f"; Disassembly of {src_path}\n; Total Instructions: {len(code_words)}\n\n")
        f_dis.write("\n".join(dis) + "\n")

    # 2. Write ELF32 binary
    asmb.generate_elf32(code_words, elf_out)

    # 3. Write imem.hex and dmem.hex
    asmb.generate_hex_files(code_words, imem_out, dmem_out, total_words=1024)

    print(f"[+] Successfully assembled {src_path}:")
    print(f"    - Instructions : {len(code_words)}")
    print(f"    - ELF Binary   : {elf_out}")
    print(f"    - Disassembly  : {dis_out}")
    print(f"    - IMEM Hex     : {imem_out} (1024 words, NOP-padded)")
    print(f"    - DMEM Hex     : {dmem_out} (1024 words)")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Pure Python RV32IMF Assembler & ELF Generator")
    parser.add_argument("source", help="Path to RISC-V assembly source (.s / .asm)")
    parser.add_argument("--elf", default=None, help="Output ELF file path")
    parser.add_argument("--imem", default=None, help="Output imem.hex path")
    parser.add_argument("--dmem", default=None, help="Output dmem.hex path")
    parser.add_argument("--dis", default=None, help="Output disassembly file path")
    args = parser.parse_args()

    if not os.path.exists(args.source):
        print(f"Error: Source file '{args.source}' not found.")
        sys.exit(1)

    assemble_file(args.source, args.elf, args.imem, args.dmem, args.dis)
