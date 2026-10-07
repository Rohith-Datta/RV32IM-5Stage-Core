import os
import subprocess
import sys
import shutil

C_TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
MEM_DIR = os.path.join(os.path.dirname(C_TESTS_DIR), "feature_1", "mem")

CC      = "riscv-none-elf-gcc"
OBJCOPY = "riscv-none-elf-objcopy"
OBJDUMP = "riscv-none-elf-objdump"
CFLAGS  = ["-march=rv32i", "-mabi=ilp32", "-O0"]

PROGRAMS = {
    "addition":       "addition.c",
    "code_addition":  "code_addition.c",
    "addition.c":     "addition.c",
    "fibonacci":      "fibonacci.c",
    "code_fibonacci": "code_fibonacci.c",
    "fibonacci.c":    "fibonacci.c",
    "sort":           "sort.c",
    "code_sort":      "code_sort.c",
    "sort.c":         "sort.c",
    "negative":       "negative.c",
    "code_negative":  "code_negative.c",
    "negative.c":     "negative.c",
    "xor":            "xor.c",
    "code_xor":       "code_xor.c",
    "xor.c":          "xor.c"
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
    
    print(f"[*] Compiling {PROGRAMS[prog_name]} -> code.elf...")
    subprocess.check_call([CC, "-c", src_file, "-o", elf_file] + CFLAGS)
    
    print(f"[*] Extracting text section -> imem.bin...")
    subprocess.check_call([OBJCOPY, "-O", "binary", elf_file, imem_bin])
    
    print(f"[*] Extracting data section -> dmem.bin...")
    # Some programs may not have .data, so don't fail if section missing
    res = subprocess.run([OBJCOPY, "-j", ".data", "-O", "binary", elf_file, dmem_bin], capture_output=True)
    if not os.path.exists(dmem_bin) or res.returncode != 0:
        open(dmem_bin, "wb").close()
        
    print(f"[*] Generating disassembly -> code.dis...")
    with open(dis_file, "w") as df:
        subprocess.check_call([OBJDUMP, "-d", elf_file], stdout=df)
        
    print(f"[*] Converting binary -> hex...")
    bin2hex(imem_bin, imem_hex)
    bin2hex(dmem_bin, dmem_hex)
    
    # Copy to feature_1/mem
    os.makedirs(MEM_DIR, exist_ok=True)
    shutil.copy2(imem_hex, os.path.join(MEM_DIR, "imem.hex"))
    shutil.copy2(dmem_hex, os.path.join(MEM_DIR, "dmem.hex"))
    shutil.copy2(dis_file, os.path.join(MEM_DIR, "code.dis"))
    shutil.copy2(elf_file, os.path.join(MEM_DIR, "code.elf"))
    shutil.copy2(src_file, os.path.join(MEM_DIR, PROGRAMS[prog_name]))
    
    print(f"[+] Successfully built and deployed {prog_name} to feature_1/mem/")

if __name__ == "__main__":
    prog = sys.argv[1] if len(sys.argv) > 1 else "addition"
    build(prog)
