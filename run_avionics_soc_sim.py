# ==============================================================================
# Script: run_avionics_soc_sim.py
# Description: Compiles and runs the full FPGA SoC Avionics Telemetry simulation
#              in Vivado Simulator (xvlog, xelab, xsim).
# ==============================================================================

import os
import glob
import subprocess
import shutil

ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
SIM_DIR  = os.path.join(ROOT_DIR, "integration", "sim_run_soc")

os.makedirs(SIM_DIR, exist_ok=True)

# Copy avionics_demo.hex to SIM_DIR
hex_src = os.path.join(ROOT_DIR, "avionics_demo.hex")
hex_dst = os.path.join(SIM_DIR, "avionics_demo.hex")
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
xelab_cmd = ["xelab", "-top", "tb_fpga_top_integrated", "-snapshot", "soc_snap", "-timescale", "1ns/1ps"]
print("Running xelab...")
res = subprocess.run(xelab_cmd, cwd=SIM_DIR, capture_output=True, text=True, shell=True)
if res.returncode != 0:
    print("xelab ERROR:\n", res.stdout, res.stderr)
    exit(1)
else:
    print("xelab elaboration completed successfully.")

# Step 3: xsim
xsim_cmd = ["xsim", "soc_snap", "-R"]
print("Running xsim...")
res = subprocess.run(xsim_cmd, cwd=SIM_DIR, capture_output=True, text=True, errors="replace", shell=True)
out_str = res.stdout.encode("ascii", errors="replace").decode("ascii") if res.stdout else ""
print("xsim Output:\n", out_str)
if res.stderr:
    err_str = res.stderr.encode("ascii", errors="replace").decode("ascii")
    print("xsim stderr:\n", err_str)
