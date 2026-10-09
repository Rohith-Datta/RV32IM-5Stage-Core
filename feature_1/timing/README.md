# RV32I 5-Stage Pipeline Timing Analysis

This directory contains comprehensive clock-cycle by clock-cycle pipeline timing reservation charts and stage occupancy tables for the **5-Stage Pipelined RV32I Processor Core** (`feature_1`).

---

## Document Index

| File | Scenario / Focus | Instruction Count | Hazards Covered | Key Hardware Mechanisms |
|---|---|---|---|---|
| [`1_data_hazard_forwarding_timing.md`](1_data_hazard_forwarding_timing.md) | **Case 1: Data Hazards with Operand Forwarding** | 14 Instructions (`I1`–`I14`) | RAW hazards, distance-1 and distance-2 dependencies | EX/MEM → EX (`fwd=01`), MEM/WB → EX (`fwd=10`), `x0` immunity, zero stalls |
| [`2_load_use_hazard_stalls_timing.md`](2_load_use_hazard_stalls_timing.md) | **Case 2: Load-Use Hazards with Stalls & Forwarding** | 14 Instructions (`I1`–`I14`) | Load-Use data hazards, pointer chasing | 1-cycle hardware stall, IF/ID freezing, bubble (NOP) injection into EX, load-delay slot fill |
| [`3_control_hazard_branch_flush_timing.md`](3_control_hazard_branch_flush_timing.md) | **Case 3: Control Hazards with Pipeline Flushes** | 14 Instructions (`I1`–`I14`) | Branch Taken, Branch Not-Taken, JAL, JALR | 2-cycle branch flush, speculative instruction annulment, PC redirection, link return address write |

---

## 5-Stage Pipeline Structure

```text
+-------------------+      +-------------------+      +-------------------+      +-------------------+      +-------------------+
|    Fetch (IF)     | ---> |    Decode (ID)    | ---> |   Execute (EX)    | ---> |   Memory (MEM)    | ---> |  Writeback (WB)   |
|  - PC Generation  |      |  - Reg Read (rs1) |      |  - ALU Arithmetic |      |  - Data Read (lw) |      |  - Reg File Write |
|  - IMEM Read      |      |  - Reg Read (rs2) |      |  - Branch Compare |      |  - Data Write (sw)|      |    (rd <= data)   |
|  - IF/ID Register |      |  - Imm Generation |      |  - Forwarding Mux |      |  - Byte Alignment |      |                   |
+-------------------+      +-------------------+      +-------------------+      +-------------------+      +-------------------+
                                     ^                          |                          |                          |
                                     |                          +--- EX/MEM Forward -------+                          |
                                     |                                                     |                          |
                                     +--------------------------- MEM/WB Forward ----------+--------------------------+
```

---

## Hazard Unit Summary Table

| Hazard Type | Detection Condition | Hardware Penalty | Signals Asserted |
|---|---|---|---|
| **ALU RAW Data Hazard** | `rd_ex == rs1_id` or `rs2_id` (ALU op) | **0 Cycles** | `forward_a = 2'b01` or `forward_b = 2'b01` |
| **MEM RAW Data Hazard** | `rd_mem == rs1_id` or `rs2_id` | **0 Cycles** | `forward_a = 2'b10` or `forward_b = 2'b10` |
| **Load-Use Data Hazard** | `is_load_ex && (rd_ex == rs1_id \|\| rs2_id)` | **1 Cycle Stall** | `hazard_stall = 1` (PC & IF/ID freeze), `hazard_flush_ex = 1` (Bubble in EX) |
| **Branch Taken** | `branch_taken_ex == 1` | **2 Cycle Flush** | `hazard_flush_id = 1`, `hazard_flush_ex = 1`, `pc = branch_target` |
| **Branch Not-Taken** | `branch_taken_ex == 0` | **0 Cycles** | None (sequential execution continues) |
| **Jump (JAL / JALR)** | `is_jump_ex == 1` | **2 Cycle Flush** | `hazard_flush_id = 1`, `hazard_flush_ex = 1`, `pc = jump_target` |
