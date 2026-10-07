#!/usr/bin/env python3
"""
Test Runner for C Programs on the 5-Stage RV32I Processor Core.

Usage:
    python run_c_tests.py              # Runs all 5 C tests
    python run_c_tests.py addition     # Runs addition test
    python run_c_tests.py fibonacci    # Runs fibonacci test
    python run_c_tests.py sort         # Runs bubble sort test
    python run_c_tests.py negative     # Runs negative number test
    python run_c_tests.py xor          # Runs bitwise XOR test
"""

import os
import sys
import subprocess
import re

ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
SIM_DIR = os.path.join(ROOT_DIR, "feature_1", "simulation")
BUILD_HEX = os.path.join(ROOT_DIR, "c_tests", "build_hex.py")

TESTS = {
    "addition":  {"expected": 102, "desc": "100 + 2 = 102"},
    "fibonacci": {"expected": 8,   "desc": "fib(5) = 8"},
    "sort":      {"expected": 3,   "desc": "sort({6,3,9}) -> arr[0] = 3"},
    "negative":  {"expected": -1,  "desc": "4 - 5 = -1"},
    "xor":       {"expected": 2,   "desc": "4 ^ 6 = 2"}
}

def run_test(test_name):
    if test_name not in TESTS:
        print(f"[-] Unknown test: {test_name}. Available: {list(TESTS.keys())}")
        return False
    
    info = TESTS[test_name]
    print(f"\n========================================================")
    print(f"[*] Running Test: {test_name.upper()} ({info['desc']})")
    print(f"========================================================")
    
    # 1. Build hex
    build_cmd = [sys.executable, BUILD_HEX, test_name]
    res = subprocess.run(build_cmd, cwd=SIM_DIR, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"[-] Build failed:\n{res.stderr}")
        return False
    
    # 2. Run simulation via xsim
    sim_cmd = "xsim sim_pipeline_snap -runall"
    proc = subprocess.run(sim_cmd, cwd=SIM_DIR, capture_output=True, text=True, shell=True)
    out = proc.stdout
    
    # Print the relevant simulation log
    lines = out.splitlines()
    in_log = False
    for line in lines:
        if "next_pc = " in line or "time: " in line or "PROGRAM EXECUTION" in line or "FINAL" in line or "IPC" in line:
            print(line)
    
    # Parse final return value
    m = re.search(r"FINAL RETURN VALUE a0 \(x10\) =\s*(-?\d+)", out)
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
    target = sys.argv[1].lower() if len(sys.argv) > 1 else "all"
    
    if target == "all":
        results = {}
        for name in TESTS:
            results[name] = run_test(name)
        
        print("\n" + "="*50)
        print("                TEST RESULTS SUMMARY")
        print("="*50)
        all_passed = True
        for name, passed in results.items():
            status = "PASS" if passed else "FAIL"
            print(f"  * {name:<12} : [{status}] (Expected: {TESTS[name]['expected']})")
            if not passed:
                all_passed = False
        print("="*50)
        if all_passed:
            print("[+] ALL C PROGRAM TESTS PASSED ON 5-STAGE CORE!")
        sys.exit(0 if all_passed else 1)
    else:
        passed = run_test(target)
        sys.exit(0 if passed else 1)

if __name__ == "__main__":
    main()
