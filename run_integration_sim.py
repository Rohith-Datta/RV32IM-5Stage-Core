# ==============================================================================
# Script: run_integration_sim.py
# Description: Compiles and runs the integrated RV32IMF processor testbench
#              in Vivado Simulator (xvlog, xelab, xsim).
# ==============================================================================

import os
import glob
import subprocess
import shutil

ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
SIM_DIR  = os.path.join(ROOT_DIR, "integration", "sim_run")

os.makedirs(SIM_DIR, exist_ok=True)

# Copy hex file to SIM_DIR
hex_src = os.path.join(ROOT_DIR, "integration", "testbench", "integration_prog.hex")
hex_dst = os.path.join(SIM_DIR, "integration_prog.hex")
shutil.copy(hex_src, hex_dst)

# Gather all verilog files
v_files = []
v_files.extend(glob.glob(os.path.join(ROOT_DIR, "integration", "modules", "**", "*.v"), recursive=True))
v_files.extend(glob.glob(os.path.join(ROOT_DIR, "integration", "testbench", "*.v"), recursive=True))

inc_dir = os.path.join(ROOT_DIR, "integration", "modules")

print(f"Collected {len(v_files)} Verilog files.")

# Step 1: xvlog
xvlog_cmd = ["xvlog", "-i", inc_dir] + v_files
print("Running xvlog...")
res = subprocess.run(xvlog_cmd, cwd=SIM_DIR, capture_output=True, text=True, shell=True)
if res.returncode != 0:
    print("xvlog ERROR:\n", res.stdout, res.stderr)
    exit(1)
else:
    print("xvlog completed successfully.")

# Step 2: xelab
xelab_cmd = ["xelab", "-top", "tb_integrated_core", "-snapshot", "sim_snap", "-timescale", "1ns/1ps"]
print("Running xelab...")
res = subprocess.run(xelab_cmd, cwd=SIM_DIR, capture_output=True, text=True, shell=True)
if res.returncode != 0:
    print("xelab ERROR:\n", res.stdout, res.stderr)
    exit(1)
else:
    print("xelab elaboration completed successfully.")

# Step 3: xsim
xsim_cmd = ["xsim", "sim_snap", "-R"]
print("Running xsim...")
res = subprocess.run(xsim_cmd, cwd=SIM_DIR, capture_output=True, text=True, shell=True)
print("xsim Output:\n", res.stdout)
if res.stderr:
    print("xsim stderr:\n", res.stderr)
