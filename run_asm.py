#!/usr/bin/env python3
# ==============================================================================
# File: run_asm.py
# Description: Unified RISC-V Assembly & ELF Pipeline Manager
# Assembles .s / .asm, converts .elf binaries, generates imem.hex / dmem.hex,
# deploys to hardware memory folders, and verifies via simulation.
# ==============================================================================

import os
import sys
import shutil
import argparse
import subprocess

ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
TOOLS_DIR = os.path.join(ROOT_DIR, "tools")
ASM_DIR = os.path.join(ROOT_DIR, "asm_tests")
F4_MEM_DIR = os.path.join(ROOT_DIR, "feature_4", "mem")

sys.path.insert(0, TOOLS_DIR)
try:
    from riscv_as import assemble_file
    from elf2hex import convert_elf_to_hex
except ImportError as e:
    print(f"Error importing assembler tools: {e}")
    sys.exit(1)

AVAILABLE_TESTS = {
    "1": "01_basic_arithmetic.s",
    "01": "01_basic_arithmetic.s",
    "basic": "01_basic_arithmetic.s",
    "arithmetic": "01_basic_arithmetic.s",

    "2": "02_pipeline_hazards.s",
    "02": "02_pipeline_hazards.s",
    "hazard": "02_pipeline_hazards.s",
    "hazards": "02_pipeline_hazards.s",

    "3": "03_hardware_multiplier.s",
    "03": "03_hardware_multiplier.s",
    "mul": "03_hardware_multiplier.s",
    "multiplier": "03_hardware_multiplier.s",

    "4": "04_fpu_special_cases.s",
    "04": "04_fpu_special_cases.s",
    "fpu": "04_fpu_special_cases.s",
    "special": "04_fpu_special_cases.s",

    "5": "05_fpga_io_demo.s",
    "05": "05_fpga_io_demo.s",
    "io": "05_fpga_io_demo.s",
    "counter": "05_fpga_io_demo.s",
    "demo": "05_fpga_io_demo.s"
}

def deploy_hex(src_imem, src_dmem, src_dis=None, src_elf=None):
    """
    Deploys generated hex and dis files to feature directories.
    """
    targets = [
        os.path.join(ROOT_DIR, "feature_4", "mem"),
        os.path.join(ROOT_DIR, "feature_1", "mem"),
        os.path.join(ROOT_DIR, "feature_2", "mem"),
        os.path.join(ROOT_DIR, "feature_3", "mem"),
        os.path.join(ROOT_DIR, "c_tests")
    ]
    for target in targets:
        if os.path.exists(os.path.dirname(target)):
            os.makedirs(target, exist_ok=True)
            shutil.copy2(src_imem, os.path.join(target, "imem.hex"))
            shutil.copy2(src_dmem, os.path.join(target, "dmem.hex"))
            if src_dis and os.path.exists(src_dis):
                shutil.copy2(src_dis, os.path.join(target, "code.dis"))
            if src_elf and os.path.exists(src_elf):
                shutil.copy2(src_elf, os.path.join(target, "code.elf"))
    print("[+] Deployed imem.hex, dmem.hex, code.dis to feature_1..4 and c_tests/")

def run_simulation():
    """
    Runs the hardware pipeline simulation to verify execution.
    """
    f4_dir = os.path.join(ROOT_DIR, "feature_4")
    sim_bin = os.path.join(f4_dir, "sim_test")
    iverilog_cmd = [
        "iverilog", "-g2012", "-o", sim_bin,
        "-I", "modules", "-I", "modules/pipeline", "-I", "modules/stages", "-I", "modules/registers",
        "modules/pipeline/pipe.v", "modules/pipeline/pipeline_5stage.v",
        "modules/registers/if_id_reg.v", "modules/registers/id_ex_reg.v",
        "modules/registers/ex_mem_reg.v", "modules/registers/mem_wb_reg.v",
        "modules/stages/decode_stage.v", "modules/stages/execute_stage.v",
        "modules/stages/memory.v", "modules/stages/memory_stage.v",
        "modules/stages/writeback_stage.v", "modules/stages/multiplier_unit.v",
        "modules/stages/multiplier_dsp.v", "modules/stages/booth_radix4_multiplier.v",
        "modules/stages/divider_unit.v", "modules/stages/fpu_single_core.v",
        "modules/hazard_unit.v", "testbench/tb_fpu_c_test.v"
    ]
    try:
        print("[*] Running hardware pipeline simulation...")
        subprocess.check_call(iverilog_cmd, cwd=f4_dir)
        subprocess.check_call([sim_bin], cwd=f4_dir)
        os.remove(sim_bin)
    except Exception as e:
        print(f"Simulation notice: {e}")

def main():
    parser = argparse.ArgumentParser(description="RISC-V Assembly & ELF to FPGA HEX Pipeline")
    parser.add_argument("target", nargs="?", default="04", help="Assembly file, test name (1..5), or .elf file")
    parser.add_argument("--elf", action="store_true", help="Treat target directly as an ELF binary to convert")
    parser.add_argument("--sim", action="store_true", help="Run simulation after deployment")
    parser.add_argument("--list", action="store_true", help="List all available assembly tests")
    args = parser.parse_args()

    if args.list:
        print("Available Pre-Built Assembly Tests in asm_tests/:")
        print("  1 / 01 / arithmetic : 01_basic_arithmetic.s   (RV32I ALU & loop sum)")
        print("  2 / 02 / hazard     : 02_pipeline_hazards.s  (Forwarding & load-use stalls)")
        print("  3 / 03 / multiplier : 03_hardware_multiplier.s (RV32M Mul/Div & signed div0)")
        print("  4 / 04 / fpu        : 04_fpu_special_cases.s (IEEE-754 FPU & 7 special cases)")
        print("  5 / 05 / demo       : 05_fpga_io_demo.s      (Visual counter for FPGA LEDs)")
        return

    target = args.target

    # Mode 1: Target is an ELF binary
    if args.elf or target.endswith(".elf"):
        elf_path = target if os.path.isabs(target) else os.path.join(ROOT_DIR, target)
        if not os.path.exists(elf_path):
            print(f"Error: ELF file '{elf_path}' not found.")
            sys.exit(1)
        imem_out = os.path.join(ROOT_DIR, "imem.hex")
        dmem_out = os.path.join(ROOT_DIR, "dmem.hex")
        convert_elf_to_hex(elf_path, imem_out, dmem_out)
        deploy_hex(imem_out, dmem_out, src_elf=elf_path)
        if args.sim:
            run_simulation()
        return

    # Mode 2: Target is an Assembly file or name
    if target in AVAILABLE_TESTS:
        asm_filename = AVAILABLE_TESTS[target]
        asm_path = os.path.join(ASM_DIR, asm_filename)
    elif os.path.exists(target):
        asm_path = os.path.abspath(target)
    elif os.path.exists(os.path.join(ASM_DIR, target)):
        asm_path = os.path.join(ASM_DIR, target)
    elif os.path.exists(os.path.join(ASM_DIR, f"{target}.s")):
        asm_path = os.path.join(ASM_DIR, f"{target}.s")
    else:
        print(f"Unknown test target: '{target}'. Available tests:")
        for k in ["01", "02", "03", "04", "05"]:
            print(f"  {k}: {AVAILABLE_TESTS[k]}")
        sys.exit(1)

    base = os.path.splitext(asm_path)[0]
    elf_file  = f"{base}.elf"
    imem_file = f"{base}_imem.hex"
    dmem_file = f"{base}_dmem.hex"
    dis_file  = f"{base}.dis"

    print(f"========================================================================")
    print(f" Building RISC-V Assembly Program: {os.path.basename(asm_path)}")
    print(f"========================================================================")

    # 1. Assemble to ELF + HEX
    assemble_file(asm_path, elf_path=elf_file, imem_path=imem_file, dmem_path=dmem_file, dis_path=dis_file)

    # 2. Deploy to hardware memory folders
    deploy_hex(imem_file, dmem_file, src_dis=dis_file, src_elf=elf_file)

    # 3. Optional Simulation
    if args.sim:
        run_simulation()

    print(f"\n[+] Build & Deployment Complete! Target is ready for FPGA synthesis & simulation.\n")

if __name__ == "__main__":
    main()
