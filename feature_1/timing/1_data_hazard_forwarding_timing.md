# Pipeline Timing Diagram - Case 1: Data Hazards with Operand Forwarding

This document analyzes the execution of a 14-instruction benchmark sequence demonstrating **data hazards (Read-After-Write, RAW)** and how the 5-stage RV32I pipeline core resolves them **without stalling** using hardware operand forwarding.

---

## 1. Instruction Sequence (I1 – I14)

| Label | Assembly Instruction | Format | Read Regs (rs1, rs2) | Write Reg (rd) | Data Dependency | Forwarding Mechanism |
|---|---|---|---|---|---|---|
| **I1** | `addi x1, x0, 10` | I-Type | rs1=x0 | rd=x1 | None (base initializer) | None (`forward_a=00, forward_b=00`) |
| **I2** | `addi x2, x1, 5`  | I-Type | rs1=x1 | rd=x2 | RAW on `x1` from **I1** (dist 1) | **EX/MEM → EX** (`forward_a=01`) |
| **I3** | `add  x3, x1, x2` | R-Type | rs1=x1, rs2=x2 | rd=x3 | RAW on `x1` from **I1** (dist 2)<br>RAW on `x2` from **I2** (dist 1) | **MEM/WB → EX** (`forward_a=10`)<br>**EX/MEM → EX** (`forward_b=01`) |
| **I4** | `sub  x4, x3, x1` | R-Type | rs1=x3, rs2=x1 | rd=x4 | RAW on `x3` from **I3** (dist 1)<br>RAW on `x1` from **I1** (dist 3) | **EX/MEM → EX** (`forward_a=01`)<br>**WB/ID Bypass** (`forward_b=00`) |
| **I5** | `sll  x5, x4, 2`  | I-Type | rs1=x4 | rd=x5 | RAW on `x4` from **I4** (dist 1) | **EX/MEM → EX** (`forward_a=01`) |
| **I6** | `srl  x6, x5, 1`  | I-Type | rs1=x5 | rd=x6 | RAW on `x5` from **I5** (dist 1) | **EX/MEM → EX** (`forward_a=01`) |
| **I7** | `or   x7, x6, x5` | R-Type | rs1=x6, rs2=x5 | rd=x7 | RAW on `x6` from **I6** (dist 1)<br>RAW on `x5` from **I5** (dist 2) | **EX/MEM → EX** (`forward_a=01`)<br>**MEM/WB → EX** (`forward_b=10`) |
| **I8** | `and  x8, x7, x6` | R-Type | rs1=x7, rs2=x6 | rd=x8 | RAW on `x7` from **I7** (dist 1)<br>RAW on `x6` from **I6** (dist 2) | **EX/MEM → EX** (`forward_a=01`)<br>**MEM/WB → EX** (`forward_b=10`) |
| **I9** | `add  x0, x8, x7` | R-Type | rs1=x8, rs2=x7 | rd=x0 | Writes to zero reg `x0` | **x0 protection**: Never forward `x0`! |
| **I10**| `addi x9, x0, 20` | I-Type | rs1=x0 | rd=x9 | Reads `x0` | Must read zero (`forward_a=00`) |
| **I11**| `xor  x10, x9, x8`| R-Type | rs1=x9, rs2=x8 | rd=x10| RAW on `x9` from **I10** (dist 1)<br>RAW on `x8` from **I8** (dist 3) | **EX/MEM → EX** (`forward_a=01`)<br>**WB/ID Bypass** (`forward_b=00`) |
| **I12**| `slt  x11, x10, x4`| R-Type| rs1=x10, rs2=x4| rd=x11| RAW on `x10` from **I11** (dist 1) | **EX/MEM → EX** (`forward_a=01`) |
| **I13**| `sltu x12, x11, x9`| R-Type| rs1=x11, rs2=x9| rd=x12| RAW on `x11` from **I12** (dist 1)<br>RAW on `x9` from **I10** (dist 3) | **EX/MEM → EX** (`forward_a=01`)<br>**WB/ID Bypass** (`forward_b=00`) |
| **I14**| `addi x13, x12, 1` | I-Type | rs1=x12 | rd=x13| RAW on `x12` from **I13** (dist 1) | **EX/MEM → EX** (`forward_a=01`) |

---

## 2. Cycle-by-Cycle Pipeline Stage Occupancy Table

In this sequence, **no pipeline stalls or flushes occur** (`hazard_stall = 0`, `flush = 0`). The pipeline achieves an optimal throughput of **1 instruction per cycle (IPC = 1.0)** after fill.

| Clock Cycle | IF Stage | ID Stage | EX Stage | ForwardA (`fwd_a`) | ForwardB (`fwd_b`) | MEM Stage | WB Stage | Cycle Remarks |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|---|
| **CC1** | **I1** | — | — | `00` (Reg) | `00` (Reg) | — | — | Fetch I1 (`addi x1, x0, 10`) |
| **CC2** | **I2** | **I1** | — | `00` (Reg) | `00` (Reg) | — | — | Decode I1; Fetch I2 |
| **CC3** | **I3** | **I2** | **I1** | `00` (Reg) | `00` (Imm) | — | — | Execute I1: compute `x1 = 10` |
| **CC4** | **I4** | **I3** | **I2** | **`01` (EX/MEM)** | `00` (Imm) | **I1** | — | **EX/MEM Forward**: `x1=10` forwarded from MEM to EX for I2 |
| **CC5** | **I5** | **I4** | **I3** | **`10` (MEM/WB)** | **`01` (EX/MEM)** | **I2** | **I1** | **Dual Forward**: `x1` from WB (`10`), `x2` from MEM (`01`) for I3 |
| **CC6** | **I6** | **I5** | **I4** | **`01` (EX/MEM)** | `00` (RF) | **I3** | **I2** | **EX/MEM Forward**: `x3` forwarded from MEM to EX for I4; `x1` from RF |
| **CC7** | **I7** | **I6** | **I5** | **`01` (EX/MEM)** | `00` (Imm) | **I4** | **I3** | **EX/MEM Forward**: `x4` forwarded to EX for I5 |
| **CC8** | **I8** | **I7** | **I6** | **`01` (EX/MEM)** | `00` (Imm) | **I5** | **I4** | **EX/MEM Forward**: `x5` forwarded to EX for I6 |
| **CC9** | **I9** | **I8** | **I7** | **`01` (EX/MEM)** | **`10` (MEM/WB)** | **I6** | **I5** | **Dual Forward**: `x6` from MEM (`01`), `x5` from WB (`10`) for I7 |
| **CC10**| **I10**| **I9** | **I8** | **`01` (EX/MEM)** | **`10` (MEM/WB)** | **I7** | **I6** | **Dual Forward**: `x7` from MEM (`01`), `x6` from WB (`10`) for I8 |
| **CC11**| **I11**| **I10**| **I9** | **`01` (EX/MEM)** | **`10` (MEM/WB)** | **I8** | **I7** | Execute I9: writes to `x0` (ignored by forwarding logic) |
| **CC12**| **I12**| **I11**| **I10**| `00` (x0=0) | `00` (Imm) | **I9** | **I8** | **Zero-Reg Check**: `I9` wrote `x0`, but `fwd_a=00`, `x0` forced to 0 |
| **CC13**| **I13**| **I12**| **I11**| **`01` (EX/MEM)** | `00` (RF) | **I10**| **I9** | **EX/MEM Forward**: `x9` from MEM (`01`) for I11 |
| **CC14**| **I14**| **I13**| **I12**| **`01` (EX/MEM)** | `00` (RF) | **I11**| **I10**| **EX/MEM Forward**: `x10` from MEM (`01`) for I12 |
| **CC15**| — | **I14**| **I13**| **`01` (EX/MEM)** | `00` (RF) | **I12**| **I11**| **EX/MEM Forward**: `x11` from MEM (`01`) for I13 |
| **CC16**| — | — | **I14**| **`01` (EX/MEM)** | `00` (Imm) | **I13**| **I12**| **EX/MEM Forward**: `x12` from MEM (`01`) for I14 |
| **CC17**| — | — | — | — | — | **I14**| **I13**| Memory stage for I14 |
| **CC18**| — | — | — | — | — | — | **I14**| Writeback for I14 (Execution Complete) |

---

## 3. Instruction vs Clock Cycle Pipeline Matrix (Reservation Chart)

```text
Inst | CC01 | CC02 | CC03 | CC04 | CC05 | CC06 | CC07 | CC08 | CC09 | CC10 | CC11 | CC12 | CC13 | CC14 | CC15 | CC16 | CC17 | CC18 |
-----+------+------+------+------+------+------+------+------+------+------+------+------+------+------+------+------+------+------+
 I1  |  IF  |  ID  |  EX  | MEM  |  WB  |      |      |      |      |      |      |      |      |      |      |      |      |      |
 I2  |      |  IF  |  ID  |  EX* | MEM  |  WB  |      |      |      |      |      |      |      |      |      |      |      |      |
 I3  |      |      |  IF  |  ID  |  EX* | MEM  |  WB  |      |      |      |      |      |      |      |      |      |      |      |
 I4  |      |      |      |  IF  |  ID  |  EX* | MEM  |  WB  |      |      |      |      |      |      |      |      |      |      |
 I5  |      |      |      |      |  IF  |  ID  |  EX* | MEM  |  WB  |      |      |      |      |      |      |      |      |      |
 I6  |      |      |      |      |      |  IF  |  ID  |  EX* | MEM  |  WB  |      |      |      |      |      |      |      |      |
 I7  |      |      |      |      |      |      |  IF  |  ID  |  EX* | MEM  |  WB  |      |      |      |      |      |      |      |
 I8  |      |      |      |      |      |      |      |  IF  |  ID  |  EX* | MEM  |  WB  |      |      |      |      |      |      |
 I9  |      |      |      |      |      |      |      |      |  IF  |  ID  |  EX  | MEM  |  WB  |      |      |      |      |      |
 I10 |      |      |      |      |      |      |      |      |      |  IF  |  ID  |  EX  | MEM  |  WB  |      |      |      |      |
 I11 |      |      |      |      |      |      |      |      |      |      |  IF  |  ID  |  EX* | MEM  |  WB  |      |      |      |
 I12 |      |      |      |      |      |      |      |      |      |      |      |  IF  |  ID  |  EX* | MEM  |  WB  |      |      |
 I13 |      |      |      |      |      |      |      |      |      |      |      |      |  IF  |  ID  |  EX* | MEM  |  WB  |      |
 I14 |      |      |      |      |      |      |      |      |      |      |      |      |      |  IF  |  ID  |  EX* | MEM  |  WB  |
-----+------+------+------+------+------+------+------+------+------+------+------+------+------+------+------+------+------+------+
* Indicates operand forwarding active during execution stage.
```

---

## 4. Hardware Forwarding Unit Logic

The forwarding unit implements the standard RISC-V 5-stage forwarding rules:

### Forward A (rs1) Multiplexer Logic:
```verilog
if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1)) begin
    forward_a = 2'b01; // Forward from EX/MEM stage ALU result (Distance = 1)
end else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs1)) begin
    forward_a = 2'b10; // Forward from MEM/WB stage writeback data (Distance = 2)
end else begin
    forward_a = 2'b00; // No hazard: Read directly from Register File port 1
end
```

### Forward B (rs2) Multiplexer Logic:
```verilog
if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2)) begin
    forward_b = 2'b01; // Forward from EX/MEM stage ALU result (Distance = 1)
end else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs2)) begin
    forward_b = 2'b10; // Forward from MEM/WB stage writeback data (Distance = 2)
end else begin
    forward_b = 2'b00; // No hazard: Read directly from Register File port 2 (or Imm)
end
```

### Key Safety Highlights:
1. **Priority Rule**: EX/MEM hazard check is evaluated first (`forward = 01`). If both EX/MEM and MEM/WB write to the same register, EX/MEM takes precedence because it contains the most recent value.
2. **`x0` Register Protection**: `(rd != 5'd0)` prevents forwarding writes directed to `x0` (as verified in cycle CC12 with `I9` and `I10`).
