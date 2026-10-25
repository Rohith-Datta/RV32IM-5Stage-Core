#!/usr/bin/env python3
# ==============================================================================
# File: tools/elf2hex.py
# Description: Pure-Python ELF32 to .hex Memory Converter for FPGA BRAM
# Converts RISC-V 32-bit ELF files to Vivado-compatible imem.hex and dmem.hex
# No external dependencies (works on Windows, Linux, macOS)
# ==============================================================================

import os
import sys
import struct
import argparse

def parse_elf32(elf_bytes):
    """
    Parses a 32-bit Little-Endian ELF file and extracts loadable segments.
    Returns:
        imem_bytes: dict of {addr: byte} for instruction memory (< 0x00002000)
        dmem_bytes: dict of {addr: byte} for data memory
    """
    if len(elf_bytes) < 52:
        raise ValueError("File is too small to be a valid ELF32 binary.")
    
    # 1. Verify Magic
    if elf_bytes[0:4] != b'\x7fELF':
        raise ValueError("Invalid ELF magic header.")
    
    ei_class = elf_bytes[4]    # 1 = 32-bit, 2 = 64-bit
    ei_data  = elf_bytes[5]    # 1 = Little-endian, 2 = Big-endian
    
    if ei_class != 1:
        raise ValueError("Expected ELF32 (32-bit) binary.")
    if ei_data != 1:
        raise ValueError("Expected Little-Endian byte order.")
    
    # 2. Unpack ELF Header (52 bytes)
    # e_ident[16], e_type[2], e_machine[2], e_version[4], e_entry[4], e_phoff[4], e_shoff[4], e_flags[4],
    # e_ehsize[2], e_phentsize[2], e_phnum[2], e_shentsize[2], e_shnum[2], e_shstrndx[2]
    header = struct.unpack("<16sHHIIIIIHHHHHH", elf_bytes[:52])
    e_entry     = header[4]
    e_phoff     = header[5]
    e_shoff     = header[6]
    e_phentsize = header[9]
    e_phnum     = header[10]
    e_shentsize = header[11]
    e_shnum     = header[12]
    e_shstrndx  = header[13]

    imem_dict = {}
    dmem_dict = {}

    # 3. Read Program Headers
    # p_type[4], p_offset[4], p_vaddr[4], p_paddr[4], p_filesz[4], p_memsz[4], p_flags[4], p_align[4] (32 bytes)
    for i in range(e_phnum):
        ph_offset = e_phoff + i * e_phentsize
        ph_data = elf_bytes[ph_offset : ph_offset + 32]
        p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align = struct.unpack("<IIIIIIII", ph_data)
        
        # PT_LOAD = 1
        if p_type == 1 and p_filesz > 0:
            segment_bytes = elf_bytes[p_offset : p_offset + p_filesz]
            is_exec = (p_flags & 1) != 0 # PF_X = 1
            
            # Destination selection:
            # Code/executable or vaddr < 0x200 goes to imem
            # Data/non-executable or vaddr >= 0x200 goes to dmem
            for byte_idx, b in enumerate(segment_bytes):
                addr = p_vaddr + byte_idx
                if is_exec or addr < 0x200:
                    imem_dict[addr] = b
                else:
                    dmem_dict[addr] = b

    # If no program headers or empty, try reading Section Headers
    if not imem_dict and e_shnum > 0 and e_shoff > 0:
        # Read shstrtab to get section names
        shstrtab_offset = e_shoff + e_shstrndx * e_shentsize
        _, _, _, _, strtab_offset, strtab_size, _, _, _, _ = struct.unpack("<IIIIIIIIII", elf_bytes[shstrtab_offset : shstrtab_offset + 40])
        shstrtab = elf_bytes[strtab_offset : strtab_offset + strtab_size]

        for i in range(e_shnum):
            sh_offset = e_shoff + i * e_shentsize
            sh_data = elf_bytes[sh_offset : sh_offset + 40]
            sh_name, sh_type, sh_flags, sh_addr, sh_offset_data, sh_size, _, _, _, _ = struct.unpack("<IIIIIIIIII", sh_data)
            
            # Extract section name
            name_end = shstrtab.find(b'\x00', sh_name)
            sec_name = shstrtab[sh_name:name_end].decode('ascii', errors='ignore') if name_end != -1 else ""

            # SHF_ALLOC = 0x2, SHF_EXECINSTR = 0x4
            if (sh_flags & 0x2) and sh_size > 0:
                sec_bytes = elf_bytes[sh_offset_data : sh_offset_data + sh_size]
                is_exec = (sh_flags & 0x4) != 0
                for byte_idx, b in enumerate(sec_bytes):
                    addr = sh_addr + byte_idx
                    if is_exec or sec_name in [".text", ".init"]:
                        imem_dict[addr] = b
                    else:
                        dmem_dict[addr] = b

    return e_entry, imem_dict, dmem_dict

def dict_to_words(byte_dict, max_words=1024, default_word=0x00000013):
    """
    Converts a sparse byte dictionary into a list of 32-bit little-endian words.
    """
    words = [default_word] * max_words
    if not byte_dict:
        return words

    max_addr = max(byte_dict.keys()) if byte_dict else 0
    words_needed = min(max_words, (max_addr // 4) + 1)
    
    for w in range(words_needed):
        b0 = byte_dict.get(w * 4 + 0, (default_word >> 0) & 0xFF)
        b1 = byte_dict.get(w * 4 + 1, (default_word >> 8) & 0xFF)
        b2 = byte_dict.get(w * 4 + 2, (default_word >> 16) & 0xFF)
        b3 = byte_dict.get(w * 4 + 3, (default_word >> 24) & 0xFF)
        words[w] = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
        
    return words

def write_hex(words, filename):
    """
    Writes words into Vivado-compatible hex format:
    xxxxxxxx // 32'hxx...
    """
    with open(filename, "w") as f:
        for idx, val in enumerate(words):
            addr = idx * 4
            f.write(f"{val:08x} // 32'h{addr:08x}\n")

def convert_elf_to_hex(elf_path, imem_hex_path, dmem_hex_path, words=1024):
    """
    Main entry point for converting an ELF file to imem.hex and dmem.hex
    """
    with open(elf_path, "rb") as f:
        elf_bytes = f.read()

    entry, imem_dict, dmem_dict = parse_elf32(elf_bytes)
    
    # 0x00000013 is NOP (addi x0, x0, 0)
    imem_words = dict_to_words(imem_dict, max_words=words, default_word=0x00000013)
    # 0x00000000 is 0
    dmem_words = dict_to_words(dmem_dict, max_words=words, default_word=0x00000000)

    write_hex(imem_words, imem_hex_path)
    write_hex(dmem_words, dmem_hex_path)
    
    active_instrs = sum(1 for w in imem_words if w != 0x00000013)
    active_data   = sum(1 for w in dmem_words if w != 0x00000000)
    print(f"[+] Converted {elf_path}:")
    print(f"    - Entry Point: 0x{entry:08x}")
    print(f"    - IMEM: {imem_hex_path} ({active_instrs} active instructions)")
    print(f"    - DMEM: {dmem_hex_path} ({active_data} active data words)")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert RISC-V ELF32 to Vivado hex files")
    parser.add_argument("elf", help="Path to input .elf file")
    parser.add_argument("--imem", default="imem.hex", help="Output path for imem.hex")
    parser.add_argument("--dmem", default="dmem.hex", help="Output path for dmem.hex")
    parser.add_argument("--words", type=int, default=1024, help="Memory size in 32-bit words (default: 1024)")
    args = parser.parse_args()

    if not os.path.exists(args.elf):
        print(f"Error: ELF file '{args.elf}' not found.")
        sys.exit(1)

    convert_elf_to_hex(args.elf, args.imem, args.dmem, words=args.words)
