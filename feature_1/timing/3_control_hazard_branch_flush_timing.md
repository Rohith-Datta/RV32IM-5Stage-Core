# Pipeline Timing Diagram - Case 3: Control Hazards with Pipeline Flushes

This document analyzes the execution of a 14-instruction benchmark sequence demonstrating **Control Hazards (Branch Taken, Branch Not-Taken, and Jumps)**, showing cycle-by-cycle speculative fetching, the 2-cycle branch penalty, pipeline register flushing, and bubble conversion.

---

## 1. The Control Hazard Architecture in a 5-Stage Core

In our RV32I 5-stage core (`feature_1`), branch conditions (e.g. `beq`, `bne`, `blt`, `bge`) and target PC addresses are evaluated in the **Execute (EX) Stage**:
1. When a branch is **NOT TAKEN**: The sequentially fetched instructions in IF and ID are correct. **Zero penalty cycles (0 flushes)** occur.
2. When a branch or jump is **TAKEN**: Two sequentially fetched instructions have entered the pipeline:
   - One instruction is in the **Decode (ID)** stage.
   - One instruction is currently in the **Fetch (IF)** stage.
   
Because these instructions belong to the wrong execution path, the Hazard Unit asserts:
- `hazard_flush_id = 1`: Clears the IF/ID register, converting the instruction in IF into a **BUBBLE (NOP)**.
- `hazard_flush_ex = 1`: Clears the ID/EX register, converting the instruction in ID into a **BUBBLE (NOP)**.
- **PC Redirection**: The program counter updates to the computed target address `pc_branch` on the next rising clock edge.

**Branch Penalty = 2 Clock Cycles.**

---

## 2. Instruction Sequence (I1 – I14)

| Label | Assembly Instruction | Format | Purpose | Control Event | Hazard Unit Action |
|---|---|---|---|---|---|
| **I1** | `addi x1, x0, 5`       | I-Type | Set `x1 = 5` | Sequential ALU | Normal flow |
| **I2** | `addi x2, x0, 5`       | I-Type | Set `x2 = 5` | Sequential ALU | Normal flow |
| **I3** | `beq  x1, x2, target_I6`| B-Type | Branch if `x1 == x2` | **BRANCH TAKEN (Evaluated in EX)** | **2-Cycle Flush Triggered!** |
| **I4** | `addi x3, x0, 1`       | I-Type | Fall-through 1 (Wrong path) | **SPECULATIVE FETCH (in ID)** | **FLUSHED → BUBBLE** |
| **I5** | `addi x4, x0, 2`       | I-Type | Fall-through 2 (Wrong path) | **SPECULATIVE FETCH (in IF)** | **FLUSHED → BUBBLE** |
| **I6** | `target_I6: addi x5, x0, 20` | I-Type | **Branch Target Target** | Fetched after redirect | Valid execution |
| **I7** | `bne  x1, x2, target_I11`| B-Type| Branch if `x1 != x2` | **BRANCH NOT TAKEN (Condition FALSE)** | **NO FLUSH (0 penalty cycles)** |
| **I8** | `addi x6, x5, 1`       | I-Type | Correct fall-through 1 | Sequential execution | Seamless flow |
| **I9** | `addi x7, x6, 2`       | I-Type | Correct fall-through 2 | Sequential execution | Seamless flow |
| **I10**| `jal  x1, target_I13`  | J-Type | Unconditional Jump + Link | **JUMP TAKEN (Evaluated in EX)** | **2-Cycle Flush Triggered!** Saves `PC+4` to `x1` |
| **I11**| `sub  x8, x7, x6`      | R-Type | Fall-through (Wrong path) | **SPECULATIVE FETCH (in ID)** | **FLUSHED → BUBBLE** |
| **I12**| `and  x9, x8, x5`      | R-Type | Fall-through (Wrong path) | **SPECULATIVE FETCH (in IF)** | **FLUSHED → BUBBLE** |
| **I13**| `target_I13: addi x10, x1, 0`| I-Type | **Jump Target Target** | Fetched after jump | Consumes link reg `x1` |
| **I14**| `jalr x0, 0(x1)`       | I-Type | Return instruction (`ret`) | **Indirect Return Jump** | Evaluated in EX; completes routine |

---

## 3. Cycle-by-Cycle Pipeline Stage Occupancy Table

| Clock Cycle | IF Stage | ID Stage | EX Stage | MEM Stage | WB Stage | `branch_taken` | `flush_id` / `flush_ex` | PC Action | Cycle Remarks |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|---|
| **CC1** | **I1** | — | — | — | — | `0` | `0` / `0` | PC += 4 | Fetch I1 (`addi x1, x0, 5`) |
| **CC2** | **I2** | **I1** | — | — | — | `0` | `0` / `0` | PC += 4 | Fetch I2 (`addi x2, x0, 5`); Decode I1 |
| **CC3** | **I3** | **I2** | **I1** | — | — | `0` | `0` / `0` | PC += 4 | Fetch I3 (`beq`); Execute I1 |
| **CC4** | **I4** | **I3** | **I2** | **I1** | — | `0` | `0` / `0` | PC += 4 | Fetch speculative I4; Decode I3 |
| **CC5** | **I5** | **I4** | **I3** | **I2** | **I1** | **`1` (TAKEN!)** | **`1` / `1`** | **PC = target_I6** | **Branch Taken in EX!** I4 & I5 marked for flush |
| **CC6** | **I6** | **BUBBLE** | **BUBBLE** | **I3** | **I2** | `0` | `0` / `0` | PC += 4 | **FLUSH 1**: I4 & I5 annulled; Target I6 fetched |
| **CC7** | **I7** | **I6** | **BUBBLE** | **BUBBLE** | **I3** | `0` | `0` / `0` | PC += 4 | Decode I6; Fetch I7 (`bne`) |
| **CC8** | **I8** | **I7** | **I6** | **BUBBLE** | **BUBBLE** | `0` | `0` / `0` | PC += 4 | Execute I6; Decode I7 |
| **CC9** | **I9** | **I8** | **I7** | **I6** | **BUBBLE** | **`0` (NOT TAKEN)**| `0` / `0` | PC += 4 | **Branch Not-Taken!** Zero flush; I8 & I9 valid |
| **CC10**| **I10**| **I9** | **I8** | **I7** | **I6** | `0` | `0` / `0` | PC += 4 | Execute I8; Fetch I10 (`jal`) |
| **CC11**| **I11**| **I10**| **I9** | **I8** | **I7** | `0` | `0` / `0` | PC += 4 | Decode I10 (`jal`); Execute I9 |
| **CC12**| **I12**| **I11**| **I10**| **I9** | **I8** | **`1` (JAL!)** | **`1` / `1`** | **PC = target_I13**| **JAL Taken in EX!** I11 & I12 marked for flush |
| **CC13**| **I13**| **BUBBLE** | **BUBBLE** | **I10**| **I9** | `0` | `0` / `0` | PC += 4 | **FLUSH 2**: I11 & I12 annulled; Target I13 fetched |
| **CC14**| **I14**| **I13**| **BUBBLE** | **BUBBLE** | **I10**| `0` | `0` / `0` | PC += 4 | Decode I13; I10 writes `x1 = PC+4` (Link) |
| **CC15**| — | **I14**| **I13**| **BUBBLE** | **BUBBLE** | `0` | `0` / `0` | PC += 4 | Execute I13 (`fwd_a=10` from I10 link in WB) |
| **CC16**| — | — | **I14**| **I13**| **BUBBLE** | **`1` (JALR)** | **`1` / `1`** | **PC = (x1)** | Execute I14 (`ret`); Indirect jump taken |
| **CC17**| — | — | — | **I14**| **I13**| `0` | `0` / `0` | — | Memory stage for I14 |
| **CC18**| — | — | — | — | **I14**| `0` | `0` / `0` | — | Writeback for I14 (Execution Complete) |

---

## 4. Instruction vs Clock Cycle Pipeline Matrix (Reservation Chart)

```text
Inst | CC01| CC02| CC03| CC04| CC05| CC06| CC07| CC08| CC09| CC10| CC11| CC12| CC13| CC14| CC15| CC16| CC17| CC18|
-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
 I1  | IF  | ID  | EX  | MEM | WB  |     |     |     |     |     |     |     |     |     |     |     |     |     |
 I2  |     | IF  | ID  | EX  | MEM | WB  |     |     |     |     |     |     |     |     |     |     |     |     |
 I3  |     |     | IF  | ID  | EX* | MEM | WB  |     |     |     |     |     |     |     |     |     |     |     |
 I4  |     |     |     | IF  | ID~ |  X  |  X  |  X  |     |     |     |     |     |     |     |     |     |     | (FLUSHED)
 I5  |     |     |     |     | IF~ |  X  |  X  |  X  |     |     |     |     |     |     |     |     |     |     | (FLUSHED)
 I6  |     |     |     |     |     | IF  | ID  | EX  | MEM | WB  |     |     |     |     |     |     |     |     |
 I7  |     |     |     |     |     |     | IF  | ID  | EX! | MEM | WB  |     |     |     |     |     |     |     |
 I8  |     |     |     |     |     |     |     | IF  | ID  | EX  | MEM | WB  |     |     |     |     |     |     |
 I9  |     |     |     |     |     |     |     |     | IF  | ID  | EX  | MEM | WB  |     |     |     |     |     |
 I10 |     |     |     |     |     |     |     |     |     | IF  | ID  | EX* | MEM | WB^ |     |     |     |     |
 I11 |     |     |     |     |     |     |     |     |     |     | IF  | ID~ |  X  |  X  |  X  |     |     |     | (FLUSHED)
 I12 |     |     |     |     |     |     |     |     |     |     |     | IF~ |  X  |  X  |  X  |     |     |     | (FLUSHED)
 I13 |     |     |     |     |     |     |     |     |     |     |     |     | IF  | ID  | EX  | MEM | WB  |     |
 I14 |     |     |     |     |     |     |     |     |     |     |     |     |     | IF  | ID  | EX* | MEM | WB  |
-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
Legend:
 *  : Branch / Jump condition evaluated in EX stage; Redirect asserted.
 ~  : Speculatively fetched instruction annulled by Hazard Unit.
 X  : Annulled instruction converted to BUBBLE (NOP); does not alter register/memory state.
 !  : Branch Not-Taken: Evaluated as FALSE in EX; zero flushes or stalls incurred.
 ^  : JAL instruction writes link return address (PC + 4) into destination register.
```

---

## 5. Control Hazard Unit Logic Implementation

In `feature_1/modules/hazard_unit.v`, control hazard flushes are asserted whenever `branch_taken_ex` is high:

```verilog
// Branch & Jump Flush Logic
assign hazard_flush_id = branch_taken_ex; // Clears IF/ID pipeline register
assign hazard_flush_ex = branch_taken_ex; // Clears ID/EX pipeline register
```

### In `feature_1/modules/execute_stage.v`:
```verilog
always @(*) begin
    case (branch_op_ex)
        BEQ:  branch_taken = (op1 == op2);
        BNE:  branch_taken = (op1 != op2);
        BLT:  branch_taken = ($signed(op1) < $signed(op2));
        BGE:  branch_taken = ($signed(op1) >= $signed(op2));
        BLTU: branch_taken = (op1 < op2);
        BGEU: branch_taken = (op1 >= op2);
        JAL:  branch_taken = 1'b1;
        JALR: branch_taken = 1'b1;
        default: branch_taken = 1'b0;
    endcase
end
```

### Key Quantitative Findings:
- **Branch Taken Penalty**: Exactly **2 clock cycles** (2 bubble stages inserted per taken branch/jump).
- **Branch Not-Taken Penalty**: Exactly **0 clock cycles** (100% throughput preserved).
- **Architectural Correctness**: Annulled instructions (`I4`, `I5`, `I11`, `I12`) are scrubbed before reaching the Memory or Writeback stages, preventing any side effects on the register file or memory hierarchy.
