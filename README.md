# Pipelined RV32IM RISC-V Core with Advanced Arithmetic, Cache Hierarchy, and System Extensions

**Group Number:** 13  
**Repository:** https://github.com/praneethsaibharath/RISCV

---

## Project Overview
This repository contains the design, implementation, verification, and full-system integration of an advanced **5-Stage Pipelined RV32I Processor Core** extended with hardware multiplication/division, single-precision IEEE 754 floating-point math, direct-mapped L1 instruction and data caches, static branch prediction, passive hardware performance counters, and the Zbb bit-manipulation extension.

---

## Integrated Architecture Diagram

```text
       +-------------------------------------------------------------+
       |         Feature 7: Branch Prediction (Static 32-entry BTB)  |
       +-------------------------------------------------------------+
                                      | (Predicted PC / Flush Recovery)
                                      v
+--------------+    +--------------+    +-----------------------+    +--------------+    +--------------+
|  Fetch (IF)  | -> | Decode (ID)  | -> |     Execute (EX)      | -> | Memory (MEM) | -> |Writeback (WB)|
+--------------+    +--------------+    +-----------------------+    +--------------+    +--------------+
       |                                            |                       |                   |
       v                                            |                       v                   v
+--------------+                                    |                +--------------+    +--------------+
|  Feature 6:  |                                    |                |  Feature 5:  |    |  Reg File /  |
|  L1 I-Cache  |                                    |                |  L1 D-Cache  |    |  Writeback   |
| (Direct-Map) |                                    |                | (Direct-Map) |    |              |
+--------------+                                    |                +--------------+    +--------------+
                                                    |
             +--------------------------------------+--------------------------------------+
             |                      |                      |                      |        |
             v                      v                      v                      v        v
      +--------------+       +--------------+       +--------------+       +------------+ +-------------+
      |  Feature 2:  |       |  Feature 3:  |       |  Feature 4:  |       | Feature 9: | | Feature 8:  |
      |   Hardware   |       |   Hardware   |       |   IEEE 754   |       |    Bit-    | | Performance |
      |  Multiplier  |       |   Divider    |       |     FPU      |       |Manipulation| |  Counters   |
      |   (RV32M)    |       |   (RV32M)    |       |   (RV32F)    |       |   (Zbb)    | |(Passive CSR)|
      +--------------+       +--------------+       +--------------+       +------------+ +-------------+
```

---

## Project Feature Breakdown & Execution Order

| # | Directory | Feature Name | Description & Deliverables |
|:---:|---|---|---|
| **1** | [`feature_1/`](feature_1/) | **5-Stage Pipeline: with Hazard Detection and Forwarding** | **Completed & Verified**: 5-stage core (`IF`, `ID`, `EX`, `MEM`, `WB`), Hazard Detection & Forwarding Unit, C test suite, cycle-by-cycle timing analyses |
| **2** | [`feature_2/`](feature_2/) | **Hardware Multiplier** | **Completed & Verified**: Radix-4 Booth / DSP multiplier supporting `MUL`, `MULH`, `MULHSU`, `MULHU` integrated in the EX stage |
| **3** | [`feature_3/`](feature_3/) | **Hardware Divider (RV32M)** | **Completed & Verified**: 32-cycle Radix-2 Restoring hardware divider for `DIV`, `DIVU`, `REM`, `REMU`, multi-cycle hazard stall interlock, Vivado project, and test suite |
| **4** | [`feature_4/`](feature_4/) | **IEEE754 FPU (FADD.S, FSUB.S, FMUL.S, FDIV.S)** | Single-precision 32-bit Floating Point Unit with dedicated 32-entry FP register file and stall control |
| **5** | [`feature_5/`](feature_5/) | **L1 D-Cache: Direct-Mapped** | Direct-mapped 2 KB L1 Data Cache with single-cycle hit, write-through/write-back policy, and byte alignment support (`SB`, `SH`, `SW`) |
| **6** | [`feature_6/`](feature_6/) | **L1 I-Cache: Direct-Mapped** | Direct-mapped 2 KB L1 Instruction Cache with single-cycle hit latency and burst memory refill FSM |
| **7** | [`feature_7/`](feature_7/) | **Branch Prediction: Static 32-Entry BTB** | Static 32-entry Branch Target Buffer (BTB) to eliminate control hazard penalty on predicted branches |
| **8** | [`feature_8/`](feature_8/) | **Performance Counters: Passive CSRs** | Hardware performance monitoring CSRs (`cycle`, `instret`, stall counter, branch mispredict, cache misses) |
| **9** | [`feature_9/`](feature_9/) | **Bit-Manipulation (Zbb)** | Standard RISC-V Zbb instructions: `CLZ`, `CTZ`, `CPOP`, `MIN`/`MAX`, `ROL`/`ROR`, `ANDN`, `ORN`, `XNOR` |

---

## Verification & Simulation Flow

All modules and integration testbenches are configured for **Vivado Simulator (`xvlog`, `xelab`, `xsim`)**:

```bash
# 1. Run all bare-metal C benchmark tests
python run_c_tests.py all

# 2. Run individual C test programs
python run_c_tests.py addition
python run_c_tests.py fibonacci
python run_c_tests.py sort

# 3. Simulate via Makefile
cd feature_1/simulation
make all
```
