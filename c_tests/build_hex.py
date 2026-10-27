import os
import subprocess
import sys
import shutil
import argparse

C_TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(C_TESTS_DIR)

CC      = "riscv-none-elf-gcc"
OBJCOPY = "riscv-none-elf-objcopy"
OBJDUMP = "riscv-none-elf-objdump"

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
    "xor.c":               "xor.c",
    "dcache":              "dcache_test.c",
    "dcache_test":         "dcache_test.c",
    "dcache.c":            "dcache_test.c",
    "dcache_test.c":       "dcache_test.c",
    "fpu":                 "fpu.c",
    "fpu_test":            "fpu.c",
    "fpu.c":               "fpu.c",
    "fpu_test.c":          "fpu.c"
}

DEFAULT_FEATURE_MAP = {
    "addition":            1,
    "code_addition":       1,
    "addition.c":          1,
    "multiplication":      2,
    "code_multiplication": 2,
    "multiplication.c":    2,
    "division":            3,
    "code_division":       3,
    "division.c":          3,
    "fpu":                 4,
    "fpu_test":            4,
    "fpu.c":               4,
    "fpu_test.c":          4,
    "dcache":              5,
    "dcache_test":         5,
    "dcache.c":            5,
    "dcache_test.c":       5,
    "fibonacci":           6,
    "code_fibonacci":      6,
    "fibonacci.c":         6,
    "sort":                1,
    "negative":            1,
    "xor":                 1
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

def deploy_to_feature(feat_idx, imem_hex, dmem_hex, dis_file, elf_file, src_file, prog_name):
    feat_dir = os.path.join(ROOT_DIR, f"feature_{feat_idx}")
    if not os.path.exists(feat_dir):
        print(f"[!] Directory {feat_dir} not found, skipping.")
        return

    mem_dir = os.path.join(feat_dir, "mem")
    os.makedirs(mem_dir, exist_ok=True)
    shutil.copy2(imem_hex, os.path.join(mem_dir, "imem.hex"))
    shutil.copy2(dmem_hex, os.path.join(mem_dir, "dmem.hex"))
    shutil.copy2(dis_file, os.path.join(mem_dir, "code.dis"))
    shutil.copy2(elf_file, os.path.join(mem_dir, "code.elf"))
    if src_file and os.path.exists(src_file):
        dest_src = os.path.join(mem_dir, os.path.basename(src_file))
        shutil.copy2(src_file, dest_src)

    for sub in ["simulation", "vivado_project"]:
        target_sub = os.path.join(feat_dir, sub)
        if os.path.exists(target_sub):
            shutil.copy2(imem_hex, os.path.join(target_sub, "imem.hex"))
            shutil.copy2(dmem_hex, os.path.join(target_sub, "dmem.hex"))

    # Also update synth_1 directory if it exists
    for root, dirs, files in os.walk(os.path.join(feat_dir, "vivado_project")):
        if os.path.basename(root) == "synth_1":
            shutil.copy2(imem_hex, os.path.join(root, "imem.hex"))
            shutil.copy2(dmem_hex, os.path.join(root, "dmem.hex"))

    print(f"[+] Loaded imem.hex & dmem.hex -> Feature {feat_idx} (mem, simulation, vivado_project)")

def build(prog_name, target_feature=None, rebuild_bitstream=False):
    # Resolve source file
    if os.path.exists(prog_name):
        src_file = os.path.abspath(prog_name)
        base_name = os.path.splitext(os.path.basename(src_file))[0]
    elif prog_name in PROGRAMS:
        src_file = os.path.join(C_TESTS_DIR, PROGRAMS[prog_name])
        base_name = prog_name
    else:
        print(f"[-] Unknown program: {prog_name}. Available: {list(PROGRAMS.keys())}")
        sys.exit(1)

    elf_file = os.path.join(C_TESTS_DIR, "code.elf")
    imem_bin = os.path.join(C_TESTS_DIR, "imem.bin")
    dmem_bin = os.path.join(C_TESTS_DIR, "dmem.bin")
    dis_file = os.path.join(C_TESTS_DIR, "code.dis")
    imem_hex = os.path.join(C_TESTS_DIR, "imem.hex")
    dmem_hex = os.path.join(C_TESTS_DIR, "dmem.hex")
    obj_file = os.path.join(C_TESTS_DIR, "code.o")
    linker_ld = os.path.join(C_TESTS_DIR, "linker.ld")

    # Select ISA flags based on target
    if "fpu" in base_name:
        march = "rv32imf"
    elif any(k in base_name for k in ["multiplication", "division", "fibonacci", "dcache"]):
        march = "rv32im"
    else:
        march = "rv32i"

    cflags = ["-march=" + march, "-mabi=ilp32", "-O0"]
    print(f"[*] Compiling {os.path.basename(src_file)} ({march}) -> code.o...")
    subprocess.check_call([CC, "-c", src_file, "-o", obj_file, "-I", C_TESTS_DIR, "-ffunction-sections"] + cflags)

    print(f"[*] Linking code.o -> code.elf (Entry=main at 0x00000000 via linker.ld)...")
    subprocess.check_call(["riscv-none-elf-ld", "-T", linker_ld, obj_file, "-o", elf_file])

    print(f"[*] Extracting full memory image -> imem.bin & dmem.bin...")
    subprocess.check_call([OBJCOPY, "-O", "binary", elf_file, imem_bin])
    shutil.copyfile(imem_bin, dmem_bin)

    print(f"[*] Generating disassembly -> code.dis...")
    with open(dis_file, "w") as df:
        subprocess.check_call([OBJDUMP, "-d", elf_file], stdout=df)

    print(f"[*] Converting binary -> hex...")
    bin2hex(imem_bin, imem_hex)
    bin2hex(dmem_bin, dmem_hex)

    # Determine target features
    if target_feature is None:
        # Default to the feature specifically designed for this program
        def_feat = DEFAULT_FEATURE_MAP.get(base_name, "all")
        if def_feat == "all":
            features_to_deploy = list(range(1, 9))
        else:
            features_to_deploy = [def_feat]
    elif str(target_feature).lower() == "all":
        features_to_deploy = list(range(1, 9))
    else:
        try:
            features_to_deploy = [int(target_feature)]
        except ValueError:
            print(f"[-] Invalid feature number: {target_feature}")
            sys.exit(1)

    # Deploy to selected feature(s)
    for feat in features_to_deploy:
        deploy_to_feature(feat, imem_hex, dmem_hex, dis_file, elf_file, src_file, base_name)

    # Optional Vivado bitstream rebuild
    if rebuild_bitstream:
        for feat in features_to_deploy:
            feat_dir = os.path.join(ROOT_DIR, f"feature_{feat}")
            b_tcl = os.path.join(feat_dir, "build_bitstream.tcl")
            if os.path.exists(b_tcl):
                print(f"[*] Rebuilding bitstream for Feature {feat} via Vivado...")
                subprocess.check_call(f"vivado.bat -mode batch -source {b_tcl} -notrace", shell=True, cwd=feat_dir)
                print(f"[+] Bitstream for Feature {feat} generated successfully!")

    print(f"\n[OK] imem.hex successfully built and loaded for Feature(s): {features_to_deploy}")

def main():
    parser = argparse.ArgumentParser(description="Compile and load imem.hex / dmem.hex for each feature separately")
    parser.add_argument("program", nargs="?", default="addition", help="Program name (addition, multiplication, division, fpu, dcache_test, fibonacci, sort, negative, xor) or path to custom .c file")
    parser.add_argument("--feature", "-f", default=None, help="Target feature number (1, 2, 3, 4, 5, 6, 7, 8, or 'all'). If omitted, automatically selects the default feature.")
    parser.add_argument("--bitstream", "-b", action="store_true", help="Automatically rebuild FPGA bitstream in Vivado after updating hex files")

    args = parser.parse_args()
    build(args.program, args.feature, args.bitstream)

if __name__ == "__main__":
    main()
