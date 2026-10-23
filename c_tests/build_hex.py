import os
import subprocess
import sys
import shutil

C_TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(C_TESTS_DIR)
F1_MEM_DIR = os.path.join(ROOT_DIR, "feature_1", "mem")
F2_MEM_DIR = os.path.join(ROOT_DIR, "feature_2", "mem")
F3_MEM_DIR = os.path.join(ROOT_DIR, "feature_3", "mem")
F4_MEM_DIR = os.path.join(ROOT_DIR, "feature_4", "mem")
F5_MEM_DIR = os.path.join(ROOT_DIR, "feature_5", "mem")
F6_MEM_DIR = os.path.join(ROOT_DIR, "feature_6", "mem")

CC      = "riscv-none-elf-gcc"
OBJCOPY = "riscv-none-elf-objcopy"
OBJDUMP = "riscv-none-elf-objdump"
CFLAGS  = ["-march=rv32im", "-mabi=ilp32", "-O0"]

PROGRAMS = {
    "addition":            "addition.c",
    "code_addition":       "code_addition.c",
    "addition.c":          "addition.c",
    "multiplication":      "multiplication.c",
    "code_multiplication": "multiplication.c",
    "multiplication.c":    "multiplication.c",
    "division":            "division.c",
    "code_division":       "division.c",
    "division.c":          "division.c",
    "fibonacci":           "fibonacci.c",
    "code_fibonacci":      "code_fibonacci.c",
    "fibonacci.c":         "fibonacci.c",
    "sort":                "sort.c",
    "code_sort":           "code_sort.c",
    "sort.c":              "sort.c",
    "negative":            "negative.c",
    "code_negative":       "code_negative.c",
    "negative.c":          "negative.c",
    "xor":                 "xor.c",
    "code_xor":            "code_xor.c",
    "xor.c":               "xor.c"
}

def hex_change(val):
    h = hex(val)[2:]
    return "0" * (8 - len(h)) + h

def bin2hex(in_file, out_file, size=4096):
    j = 0
    with open(out_file, "w") as out_f:
        if os.path.exists(in_file) and os.path.getsize(in_file) > 0:
            with open(in_file, "rb") as in_f:
                while True:
                    data = in_f.read(4)
                    if not data:
                        break
                    if len(data) < 4:
                        data = data.ljust(4, b"\x00")
                    import struct
                    word = struct.unpack("<I", data)[0]
                    out_f.write(f"{hex_change(word)} // 32'h{hex_change(j)}\n")
                    j += 4
        while j < size:
            out_f.write(f"00000000 // 32'h{hex_change(j)}\n")
            j += 4

def build(prog_name):
    if prog_name not in PROGRAMS:
        print(f"Unknown program: {prog_name}. Available: {list(PROGRAMS.keys())}")
        sys.exit(1)
        
    src_file = os.path.join(C_TESTS_DIR, PROGRAMS[prog_name])
    elf_file = os.path.join(C_TESTS_DIR, "code.elf")
    imem_bin = os.path.join(C_TESTS_DIR, "imem.bin")
    dmem_bin = os.path.join(C_TESTS_DIR, "dmem.bin")
    dis_file = os.path.join(C_TESTS_DIR, "code.dis")
    
    imem_hex = os.path.join(C_TESTS_DIR, "imem.hex")
    dmem_hex = os.path.join(C_TESTS_DIR, "dmem.hex")
    
    obj_file = os.path.join(C_TESTS_DIR, "code.o")
    linker_ld = os.path.join(C_TESTS_DIR, "linker.ld")
    march = "rv32im" if ("multiplication" in prog_name or "division" in prog_name) else "rv32i"
    cflags = ["-march=" + march, "-mabi=ilp32", "-O0"]
    print(f"[*] Compiling {PROGRAMS[prog_name]} ({march}) -> code.o...")
    subprocess.check_call([CC, "-c", src_file, "-o", obj_file, "-I", C_TESTS_DIR, "-ffunction-sections"] + cflags)
    
    print(f"[*] Linking code.o -> code.elf (Entry=main at 0x00000000 via linker.ld)...")
    subprocess.check_call(["riscv-none-elf-ld", "-T", linker_ld, obj_file, "-o", elf_file])
    
    print(f"[*] Extracting full memory image -> imem.bin & dmem.bin...")
    subprocess.check_call([OBJCOPY, "-O", "binary", elf_file, imem_bin])
    # In Harvard architecture with separate BRAMs, DMEM must contain .rodata & .data
    # at their linked addresses so loads (lbu, lw) find strings and constants.
    shutil.copyfile(imem_bin, dmem_bin)
        
    print(f"[*] Generating disassembly -> code.dis...")
    with open(dis_file, "w") as df:
        subprocess.check_call([OBJDUMP, "-d", elf_file], stdout=df)
        
    print(f"[*] Converting binary -> hex...")
    bin2hex(imem_bin, imem_hex)
    bin2hex(dmem_bin, dmem_hex)
    
    # Copy to feature_1/mem .. feature_6/mem
    for mem_dir in [F1_MEM_DIR, F2_MEM_DIR, F3_MEM_DIR, F4_MEM_DIR, F5_MEM_DIR, F6_MEM_DIR]:
        os.makedirs(mem_dir, exist_ok=True)
        shutil.copy2(imem_hex, os.path.join(mem_dir, "imem.hex"))
        shutil.copy2(dmem_hex, os.path.join(mem_dir, "dmem.hex"))
        shutil.copy2(dis_file, os.path.join(mem_dir, "code.dis"))
        shutil.copy2(elf_file, os.path.join(mem_dir, "code.elf"))
        shutil.copy2(src_file, os.path.join(mem_dir, PROGRAMS[prog_name]))
    
    print(f"[+] Successfully built and deployed {prog_name} to feature_1..6 /mem/")

if __name__ == "__main__":
    prog = sys.argv[1] if len(sys.argv) > 1 else "addition"
    build(prog)
