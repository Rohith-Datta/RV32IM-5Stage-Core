#!/usr/bin/env python3
"""
Test Runner for C Programs on the Pipelined RV32 Core across Features (1, 2, 3, 4, 5, 6).

Usage:
    python run_c_tests.py                      # Runs all C tests on Feature 5 (default)
    python run_c_tests.py sort                 # Runs bubble sort on Feature 5
    python run_c_tests.py --feature 5 addition # Runs addition on Feature 5 (L1 D-Cache)
    python run_c_tests.py --feature 5 all      # Runs all tests on Feature 5
    python run_c_tests.py --feature 1 all      # Runs all tests on Feature 1
    python run_c_tests.py multiplication       # Runs hardware multiplication on Feature 5
    python run_c_tests.py division             # Runs hardware division on Feature 5
"""

import os
import sys
import subprocess
import re
import argparse

ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
BUILD_HEX = os.path.join(ROOT_DIR, "c_tests", "build_hex.py")

TESTS = {
    "addition":       {"expected": 102, "desc": "100 + 2 = 102"},
    "fibonacci":      {"expected": 8,   "desc": "fib(5) = 8"},
    "sort":           {"expected": 3,   "desc": "sort({6,3,9}) -> arr[0] = 3"},
    "multiplication": {"expected": 42,  "desc": "6 * 7 = 42"},
    "division":       {"expected": 16,  "desc": "100/7 + 100%7 = 14 + 2 = 16"},
    "negative":       {"expected": -1,  "desc": "4 - 5 = -1"},
    "xor":            {"expected": 2,   "desc": "4 ^ 6 = 2"}
}

def get_sim_config(feature_num):
    feat_str = str(feature_num)
    sim_dir = os.path.join(ROOT_DIR, f"feature_{feat_str}", "simulation")
    if feat_str in ("5", "6"):
        top_mod = "tb_pipeline_base"
        snapshot = "snap_tb_base"
    else:
        top_mod = "tb_pipeline_base"
        snapshot = "sim_pipeline_snap"
    return sim_dir, top_mod, snapshot

def run_test(test_name, feature_num=5):
    if test_name not in TESTS:
        print(f"[-] Unknown test: {test_name}. Available: {list(TESTS.keys())}")
        return False
    
    info = TESTS[test_name]
    sim_dir, top_mod, snapshot = get_sim_config(feature_num)
    
    print(f"\n========================================================")
    print(f"[*] Running Test: {test_name.upper()} ({info['desc']}) on Feature {feature_num}")
    print(f"    Simulation Dir: {sim_dir}")
    print(f"========================================================")
    
    # 1. Build hex
    build_cmd = [sys.executable, BUILD_HEX, test_name]
    res = subprocess.run(build_cmd, cwd=ROOT_DIR, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"[-] Build failed:\n{res.stderr}")
        return False
    
    # 2. Elaborate snapshot if needed
    xelab_cmd = f"xelab -top {top_mod} -snapshot {snapshot} -debug typical"
    elab_res = subprocess.run(xelab_cmd, cwd=sim_dir, capture_output=True, text=True, shell=True)
    if elab_res.returncode != 0:
        print(f"[-] Elaboration failed:\n{elab_res.stderr}\n{elab_res.stdout}")
        return False
        
    # 3. Run simulation via xsim
    sim_cmd = f"xsim {snapshot} -runall"
    proc = subprocess.run(sim_cmd, cwd=sim_dir, capture_output=True, text=True, shell=True)
    out = proc.stdout
    
    # Print relevant simulation log lines
    lines = out.splitlines()
    for line in lines:
        if any(k in line for k in ["time: ", "PROGRAM EXECUTION", "FINAL", "IPC", "Total Elapsed", "Retired", "L1 D-Cache"]):
            print("  " + line)
    
    # Parse final return value
    m = re.search(r"FINAL RETURN VALUE a0 \(x10\)\s*=\s*(-?\d+)", out)
    if m:
        ret_val = int(m.group(1))
        if ret_val == info["expected"]:
            print(f"\n[+] SUCCESS: Return value matches expected {info['expected']}! (PASS)")
            return True
        else:
            print(f"\n[-] MISMATCH: Got {ret_val}, expected {info['expected']}! (FAIL)")
            return False
    else:
        print(f"\n[-] FAILED: Could not parse return value from simulation output.")
        return False

def main():
    parser = argparse.ArgumentParser(description="Pipelined RV32 Core C Test Runner")
    parser.add_argument("target", nargs="?", default="all",
                        help="Target test (addition, sort, fibonacci, multiplication, division, negative, xor, all)")
    parser.add_argument("--feature", "-f", type=int, default=5,
                        help="Processor feature to run on: 1, 2, 3, 4, 5, 6 (default: 5)")
    args = parser.parse_args()

    target = args.target.lower()
    feat = args.feature

    if target == "all":
        results = {}
        for name in TESTS:
            results[name] = run_test(name, feature_num=feat)
        
        print("\n" + "="*56)
        print(f"       FEATURE {feat} C PROGRAM TEST RESULTS SUMMARY")
        print("="*56)
        all_passed = True
        for name, passed in results.items():
            status = "PASS" if passed else "FAIL"
            print(f"  * {name:<14} : [{status}] (Expected: {TESTS[name]['expected']})")
            if not passed:
                all_passed = False
        print("="*56)
        if all_passed:
            print(f"[+] ALL {len(TESTS)} C TESTS PASSED ON FEATURE {feat} PIPELINE!")
        sys.exit(0 if all_passed else 1)
    else:
        passed = run_test(target, feature_num=feat)
        sys.exit(0 if passed else 1)

if __name__ == "__main__":
    main()
