# RISC-V C Test Programs for RV32I Core

This directory contains standalone bare-metal C programs used to verify the RV32I 5-stage pipelined processor core. Each program compiles directly with `riscv-none-elf-gcc`, extracts machine code into `.bin` and `.hex` memory image files, and runs on the processor core with real-time terminal output logging.

---

## Available C Programs

| File | Program Description | Expected Return Value (`a0` / `x10`) | Notes |
|---|---|---|---|
| [`addition.c`](addition.c) | Integer addition (`100 + 2`) | **`102`** (`0x00000066`) | Tests standard ALU ADD and load/store |
| [`fibonacci.c`](fibonacci.c) | Iterative Fibonacci sequence (`fib(5)`) | **`8`** (`0x00000008`) | Tests conditional branching (`bge`), loops, data forwarding |
| [`sort.c`](sort.c) | Bubble Sort on array `{6, 3, 9}` | **`3`** (`0x00000003`) | Tests memory arrays, load-use stall hazards, nested loops |
| [`negative.c`](negative.c) | Negative subtraction (`4 - 5`) | **`-1`** (`0xFFFFFFFF`) | Tests two's complement sign extension & subtraction |
| [`xor.c`](xor.c) | Bitwise XOR (`4 ^ 6`) | **`2`** (`0x00000002`) | Tests bitwise logical operations |

---

## How to Run Tests

### Option 1: Top-Level Python Test Runner (Recommended)
From the repository root:
```bash
# Run all tests sequentially with automated PASS/FAIL checking:
python run_c_tests.py all

# Or run individual tests:
python run_c_tests.py addition
python run_c_tests.py fibonacci
python run_c_tests.py sort
python run_c_tests.py negative
python run_c_tests.py xor
```

### Option 2: Using Makefile
From the `feature_1/simulation/` directory:
```bash
make addition
make fibonacci
make sort
make negative
make xor
```

### Option 3: Manual Compilation & Simulation
```bash
# 1. Compile C file to RV32I hex images
python c_tests/build_hex.py addition

# 2. Simulate via Vivado xsim
cd feature_1/simulation
xvlog -i ../modules -f filelist.txt tb_pipeline_base.v
xelab -top tb_pipeline_base -snapshot sim_pipeline_snap -debug typical
xsim sim_pipeline_snap -runall
```

---

## Terminal Output Format
When executed, the simulation prints cycle-by-cycle fetch progression and register writeback results matching standard verification log format:

```text
next_pc = 00000000
next_pc = 00000004
next_pc = 00000008
next_pc = 0000000c
next_pc = 00000010
next_pc = 00000014
next_pc = 00000018
time:              175 ,result =          0
next_pc = 0000001c
time:              185 ,result =        100
next_pc = 00000020
next_pc = 00000024
time:              205 ,result =          2
next_pc = 00000028
next_pc = 0000002c
time:              225 ,result =        100
next_pc = 0000002c
time:              235 ,result =          2
next_pc = 00000030
next_pc = 00000034
time:              255 ,result =        102
next_pc = 00000038
...
All instructions are Fetched
next_pc = 00000000

=================================================================
           PROGRAM EXECUTION COMPLETED SUCCESSFULLY!             
=================================================================
Total Elapsed Cycles : 25
Instructions Retired : 12
Load-Use Stalls      : 2
Branch Flush Cycles  : 1
Calculated IPC       : 0.48
FINAL RETURN VALUE a0 (x10) = 102 (0x00000066)
FINAL TEMP RESULT  a5 (x15) = 102 (0x00000066)
=================================================================
```
