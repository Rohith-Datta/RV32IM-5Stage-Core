# Pipeline Timing Diagram - Case 2: Load-Use Hazards with Hardware Stalls & Forwarding

This document analyzes the execution of a 14-instruction benchmark sequence demonstrating **Load-Use Data Hazards**, hardware stall generation (pipeline freezing), bubble (NOP) insertion, and subsequent operand forwarding.

---

## 1. The Load-Use Hazard Problem in a 5-Stage Core

In the RV32I 5-stage pipeline, memory read data is only available at the output of the **Memory (MEM) stage** (end of cycle 4). An instruction that immediately follows a load and consumes the loaded register requires the value at the beginning of the **Execute (EX) stage** (beginning of cycle 4).

Because time cannot flow backward, **operand forwarding alone cannot resolve a distance-1 load-use dependency**. The hardware Hazard Detection Unit must interlock the pipeline by:
1. **Freezing the Program Counter (PC)**: Suppressing PC increment so the instruction in IF is re-fetched.
2. **Freezing the IF/ID Pipeline Register**: Holding the dependent instruction in Decode.
3. **Flushing the ID/EX Pipeline Register**: Injecting a zeroed control bubble (NOP) into the EX stage for exactly 1 cycle.
4. **Resuming with Forwarding**: In the following cycle, the loaded data is in the MEM/WB stage and is forwarded to EX via `forward = 2'b10`.

---

## 2. Instruction Sequence (I1 – I14)

| Label | Assembly Instruction | Format | Read Regs | Write Reg | Dependency Type | Hardware Action |
|---|---|---|---|---|---|---|
| **I1** | `lw   x2, 0(x1)`      | I-Type | rs1=x1    | rd=x2     | Memory Load | Produces `x2` at end of MEM stage |
| **I2** | `add  x3, x2, x4`     | R-Type | rs1=x2, rs2=x4 | rd=x3 | **Load-Use RAW on `x2`** from **I1** | **1-Cycle Stall (Bubble into EX)**; then **MEM/WB → EX** (`fwd_a=10`) |
| **I3** | `sub  x4, x3, x2`     | R-Type | rs1=x3, rs2=x2 | rd=x4 | RAW on `x3` (from I2) & `x2` (from I1) | **EX/MEM → EX** (`fwd_a=01`); **WB/ID Bypass** (`fwd_b=00`) |
| **I4** | `lw   x5, 4(x1)`      | I-Type | rs1=x1    | rd=x5     | Memory Load (Pointer fetch) | Produces `x5` at end of MEM stage |
| **I5** | `lw   x6, 0(x5)`      | I-Type | rs1=x5    | rd=x6     | **Load-Use RAW on `x5`** from **I4** | **1-Cycle Stall (Bubble into EX)**; then **MEM/WB → EX** (`fwd_a=10`) |
| **I6** | `or   x7, x6, x3`     | R-Type | rs1=x6, rs2=x3 | rd=x7 | **Load-Use RAW on `x6`** from **I5** | **1-Cycle Stall (Bubble into EX)**; then **MEM/WB → EX** (`fwd_a=10`) |
| **I7** | `lw   x8, 8(x1)`      | I-Type | rs1=x1    | rd=x8     | Memory Load | Produces `x8` at end of MEM stage |
| **I8** | `add  x9, x8, x2`     | R-Type | rs1=x8, rs2=x2 | rd=x9 | **Load-Use RAW on `x8`** from **I7** | **1-Cycle Stall (Bubble into EX)**; then **MEM/WB → EX** (`fwd_a=10`) |
| **I9** | `xor  x10, x9, x8`    | R-Type | rs1=x9, rs2=x8 | rd=x10| Dual Consumer of `x9` and `x8` | **EX/MEM → EX** (`fwd_a=01`); **WB/ID Bypass** (`fwd_b=00`) |
| **I10**| `lw   x11, 12(x1)`    | I-Type | rs1=x1    | rd=x11    | Memory Load | Produces `x11` at end of MEM stage |
| **I11**| `sw   x11, 16(x1)`    | S-Type | rs1=x1, rs2=x11| None      | **Load-Use Store Data RAW on `x11`** | **1-Cycle Stall**; then **MEM/WB → EX** Store Data Forward |
| **I12**| `lw   x12, 20(x1)`    | I-Type | rs1=x1    | rd=x12    | Memory Load | Produces `x12` at end of MEM stage |
| **I13**| `addi x13, x0, 50`    | I-Type | rs1=x0    | rd=x13    | **Independent Instruction (Slot Fill)**| **NO STALL**: Fills load-delay slot naturally |
| **I14**| `add  x14, x12, x13`   | R-Type | rs1=x12, rs2=x13| rd=x14| Consumer of `x12` from **I12** | **NO STALL NEEDED**: Forwarded from **MEM/WB → EX** (`fwd_a=10`) |

---

## 3. Cycle-by-Cycle Pipeline Stage Occupancy Table

| Clock Cycle | IF Stage | ID Stage | EX Stage | MEM Stage | WB Stage | Hazard Stall (`stall`) | Bubble Injected? | Forwarding Status | Cycle Remarks |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|---|
| **CC1** | **I1** | — | — | — | — | `0` | No | None | Fetch I1 (`lw x2, 0(x1)`) |
| **CC2** | **I2** | **I1** | — | — | — | `0` | No | None | Decode I1; Fetch I2 (`add x3, x2, x4`) |
| **CC3** | **I3** | **I2** | **I1** | — | — | **`1`** (Stall) | **Yes** (to ID/EX) | None | **Hazard Detected!** `I1` is load in EX, `I2` reads `x2` in ID |
| **CC4** | **I3** (Held) | **I2** (Held) | **BUBBLE** | **I1** | — | `0` | No | None | **STALL CYCLE 1**: IF/ID frozen; BUBBLE in EX; I1 in MEM |
| **CC5** | **I4** | **I3** | **I2** | **BUBBLE** | **I1** | `0` | No | **MEM/WB → EX** (`fwd_a=10`) | `x2` forwarded from WB to EX for I2; I1 retires |
| **CC6** | **I5** | **I4** | **I3** | **I2** | **BUBBLE** | `0` | No | **EX/MEM → EX** (`fwd_a=01`) | `x3` forwarded from MEM to EX for I3 |
| **CC7** | **I6** | **I5** | **I4** | **I3** | **I2** | **`1`** (Stall) | **Yes** (to ID/EX) | None | **Hazard Detected!** `I4` is load in EX, `I5` reads `x5` in ID |
| **CC8** | **I6** (Held) | **I5** (Held) | **BUBBLE** | **I4** | **I3** | `0` | No | None | **STALL CYCLE 2**: IF/ID frozen; BUBBLE in EX; I4 in MEM |
| **CC9** | **I7** | **I6** | **I5** | **BUBBLE** | **I4** | **`1`** (Stall) | **Yes** (to ID/EX) | **MEM/WB → EX** (`fwd_a=10`) | `x5` forwarded to I5; **Chained Hazard Detected** (`I5` is load!) |
| **CC10**| **I7** (Held) | **I6** (Held) | **BUBBLE** | **I5** | **BUBBLE** | `0` | No | None | **STALL CYCLE 3**: IF/ID frozen; BUBBLE in EX; I5 in MEM |
| **CC11**| **I8** | **I7** | **I6** | **BUBBLE** | **I5** | `0` | No | **MEM/WB → EX** (`fwd_a=10`) | `x6` forwarded from WB to EX for I6; I5 retires |
| **CC12**| **I9** | **I8** | **I7** | **I6** | **BUBBLE** | **`1`** (Stall) | **Yes** (to ID/EX) | None | **Hazard Detected!** `I7` is load in EX, `I8` reads `x8` in ID |
| **CC13**| **I9** (Held) | **I8** (Held) | **BUBBLE** | **I7** | **I6** | `0` | No | None | **STALL CYCLE 4**: IF/ID frozen; BUBBLE in EX; I7 in MEM |
| **CC14**| **I10**| **I9** | **I8** | **BUBBLE** | **I7** | `0` | No | **MEM/WB → EX** (`fwd_a=10`) | `x8` forwarded from WB to EX for I8; I7 retires |
| **CC15**| **I11**| **I10**| **I9** | **I8** | **BUBBLE** | `0` | No | **EX/MEM → EX** (`fwd_a=01`) | `x9` forwarded from MEM to EX for I9; `x8` from RF |
| **CC16**| **I12**| **I11**| **I10**| **I9** | **I8** | **`1`** (Stall) | **Yes** (to ID/EX) | None | **Hazard Detected!** `I10` is load in EX, `I11` (`sw`) needs `x11` |
| **CC17**| **I12** (Held)| **I11** (Held)| **BUBBLE** | **I10**| **I9** | `0` | No | None | **STALL CYCLE 5**: IF/ID frozen; BUBBLE in EX; I10 in MEM |
| **CC18**| **I13**| **I12**| **I11**| **BUBBLE** | **I10**| `0` | No | **MEM/WB → EX** (`fwd_b=10`) | `x11` forwarded to Store Data for I11; I10 retires |
| **CC19**| **I14**| **I13**| **I12**| **I11**| **BUBBLE** | `0` | No | None | `I12` is load in EX, BUT `I13` is independent! **NO STALL!** |
| **CC20**| — | **I14**| **I13**| **I12**| **I11**| `0` | No | None | `I13` executes in EX; `I12` reads memory in MEM |
| **CC21**| — | — | **I14**| **I13**| **I12**| `0` | No | **MEM/WB → EX** (`fwd_a=10`) | `x12` forwarded from WB to EX for I14! **ZERO STALLS!** |
| **CC22**| — | — | — | **I14**| **I13**| `0` | No | None | MEM stage for I14 |
| **CC23**| — | — | — | — | **I14**| `0` | No | None | Writeback for I14 (Sequence Complete) |

---

## 4. Instruction vs Clock Cycle Pipeline Matrix (Reservation Chart)

```text
Inst | CC01| CC02| CC03| CC04| CC05| CC06| CC07| CC08| CC09| CC10| CC11| CC12| CC13| CC14| CC15| CC16| CC17| CC18| CC19| CC20| CC21| CC22| CC23|
-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
 I1  | IF  | ID  | EX  | MEM | WB  |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |
 I2  |     | IF  | ID  | ID* | EX^ | MEM | WB  |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |
 I3  |     |     | IF  | IF* | ID  | EX  | MEM | WB  |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |
 I4  |     |     |     |     | IF  | ID  | EX  | MEM | WB  |     |     |     |     |     |     |     |     |     |     |     |     |     |     |
 I5  |     |     |     |     |     | IF  | ID  | ID* | EX^ | MEM | WB  |     |     |     |     |     |     |     |     |     |     |     |     |
 I6  |     |     |     |     |     |     | IF  | IF* | ID  | ID* | EX^ | MEM | WB  |     |     |     |     |     |     |     |     |     |     |
 I7  |     |     |     |     |     |     |     |     | IF  | IF* | ID  | EX  | MEM | WB  |     |     |     |     |     |     |     |     |     |
 I8  |     |     |     |     |     |     |     |     |     |     | IF  | ID  | ID* | EX^ | MEM | WB  |     |     |     |     |     |     |     |
 I9  |     |     |     |     |     |     |     |     |     |     |     | IF  | IF* | ID  | EX  | MEM | WB  |     |     |     |     |     |     |
 I10 |     |     |     |     |     |     |     |     |     |     |     |     |     | IF  | ID  | EX  | MEM | WB  |     |     |     |     |     |
 I11 |     |     |     |     |     |     |     |     |     |     |     |     |     |     | IF  | ID  | ID* | EX^ | MEM | WB  |     |     |     |
 I12 |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     | IF  | IF* | ID  | EX  | MEM | WB  |     |     |
 I13 |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     | IF  | ID  | EX  | MEM | WB  |     |
 I14 |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     | IF  | ID  | EX^ | MEM | WB  |
-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
Legend:
 *  : Pipeline Stage FROZEN due to Load-Use Hazard Stall (1 cycle freeze).
 ^  : Execution Stage using Forwarded Data from MEM/WB stage.
Note: Between frozen ID and EX stages, a BUBBLE (NOP) flows through EX -> MEM -> WB.
```

---

## 5. Hardware Stall Logic Implementation

In `feature_1/modules/hazard_unit.v`, the stall logic detects whenever the instruction currently in the **Execute stage (`id_ex`) is a Load**, and its destination register `rd_ex` matches either operand source (`rs1_id` or `rs2_id`) of the instruction in the **Decode stage**:

```verilog
// Load-Use Hazard Condition
wire load_use_hazard = id_ex_mem_read && 
                       (id_ex_rd != 5'd0) && 
                       ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2));

// Control Action:
assign hazard_stall    = load_use_hazard; // Freezes PC and IF/ID register
assign hazard_flush_ex = load_use_hazard; // Injects BUBBLE into ID/EX register
```

### Key Software Optimization Demonstrated (I12 – I14):
Notice how inserting **`I13: addi`** between **`I12: lw`** and **`I14: add`** completely eliminated the load-use stall! The independent instruction filled the 1-cycle latency slot, allowing the compiler/programmer to achieve **100% pipeline efficiency (0 stalls)** through instruction scheduling.
