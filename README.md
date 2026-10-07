# Pipelined RV32IM RISC-V Core with L1 Cache Hierarchy and Neural Network MAC Coprocessor

**Group Number:** 13  
**Repository:** https://github.com/praneethsaibharath/RISCV

## Project Overview
This repository contains the design, implementation, and verification of an advanced 5-stage pipelined RV32IM RISC-V processor core targeted for FPGA synthesis on Xilinx Nexys boards. It features integrated hazard detection, operand forwarding, direct-mapped L1 instruction and data caches, hardware multiplication/division, and a dedicated 64-bit Neural Network MAC coprocessor.

---

## Directory & Feature Structure

| Folder | Feature / Module | Status | Deliverables |
|---|---|---|---|
| [`feature_1/`](feature_1/) | **5-Stage Pipeline Upgrade & Hazard Unit** | **Completed & Verified** | IF-WB pipeline registers, Hazard/Forwarding Unit, `tb_hazard.v`, `tb_pipeline_base.v` |
| [`feature_2/`](feature_2/) | Hardware Multiplier (Booth / RV32M) | Planned (Milestone 2) | Booth multiplier RTL, `tb_math.v` |
| [`feature_3/`](feature_3/) | Multi-Cycle Hardware Divider | Planned (Milestone 2) | Radix-2 divider RTL, stall controller |
| [`feature_4/`](feature_4/) | L1 Instruction Cache (I-Cache) | Planned (Milestone 2) | Direct-mapped I-cache RTL, `tb_icache.v` |
| [`feature_5/`](feature_5/) | L1 Data Cache (D-Cache) | Planned (Milestone 3) | Direct-mapped D-cache RTL |
| [`feature_6/`](feature_6/) | 64-bit Neural Network MAC Coprocessor | Planned (Milestone 3) | MAC RTL, custom opcode decoder |
| [`feature_7/`](feature_7/) | Branch Prediction (BTB) & Integration | Planned (Milestone 4) | 32-entry BTB RTL, FPGA top demo |

---

## Getting Started & Simulation

Simulations are configured for **Vivado Simulator (`xvlog`, `xelab`, `xsim`)**:

```powershell
# Navigate to Feature 1 simulation directory
cd feature_1/simulation

# Run unit hazard testbench
make sim_hazard

# Run full-system program testbench
make sim_pipeline

# Run all testbenches
make all
```
