# Feature 7: Pipelined RV32IMF Processor Core with Static 32-Entry Branch Target Buffer (BTB)

## 1. Overview & Architectural Scope
Feature 7 integrates a high-performance **Static 32-Entry Branch Target Buffer (BTB)** into the 5-stage pipelined RV32IMF processor core.
- **Microarchitecture Target**: 5-Stage RV32IMF Core running at 50 MHz.
- **Target FPGA**: Digilent Nexys A7-100T (Xilinx Artix-7 XC7A100T-1CSG324C).
- **Core Benefit**: Eliminates the 2-cycle control hazard penalty on repeated loops and taken branches by predicting branch direction and target address in the Fetch (IF) stage with **0 penalty cycles**.

---

## 2. BTB Microarchitecture Specifications

```
                              +-----------------------------------------------+
                              |            Fetch Stage PC Address [31:0]      |
                              +-----------------------------------------------+
                                            |                    |
                                       [31:7] (25b)          [6:2] (5b)
                                            |                    |
                                            v                    v
                                      +-----------+        +-----------+
                                      |    TAG    |        |   INDEX   |
                                      +-----------+        +-----------+
                                            |                    |
                                            v                    v
                                 +--------------------+--------------------+
                                 |  Tag Comparator    |  32-Entry BTB RAM  |
                                 +--------------------+--------------------+
                                            |
                         +------------------+------------------+
                         |                                     |
                         v                                     v
                 [ HIT / MISS ]                         [ TARGET PC ]
                         |                                     |
                         v                                     v
        +---------------------------------+   +---------------------------------+
        | Hit:  Predict TAKEN             |   | Next PC = Target PC (0 cycles)  |
        | Miss: Predict NOT TAKEN (PC+4)  |   | Next PC = PC + 4                |
        +---------------------------------+   +---------------------------------+
```

- **Table Size**: 32 entries (direct-mapped, indexed by `PC[6:2]`).
- **Tag Size**: 25 bits (`PC[31:7]`).
- **Target PC**: 32 bits pre-computed branch destination.
- **Valid Bit**: 1 bit per entry.
- **Lookup (IF Stage)**: Query in parallel with instruction fetch. On a BTB Hit, `next_pc` is redirected to `pred_target` immediately (0 bubble penalty).
- **Resolution (EX Stage)**: Actual branch condition is evaluated.
  - If prediction matches actual: Branch commits with 0 stall penalty.
  - If prediction fails (mispredict): IF/ID and ID/EX are flushed (2 bubbles), BTB is updated, and fetch redirects to correct PC.

---

## 3. Student Implementation & Guided `TODO` Sections
Per project specifications, key architectural sections contain guided `TODO` blocks with detailed theory for student self-learning:
1. `modules/stages/btb_branch_pred.v`:
   - **TODO 1**: 5-bit index and 25-bit tag extraction from PC.
   - **TODO 2**: Combinational hit detection and target multiplexing in IF stage.
   - **TODO 3**: Synchronous allocation, target update, and invalidation on clock edge in EX stage.
2. `modules/stages/execute_stage.v`:
   - **TODO**: Misprediction detection logic and redirect PC recovery calculation.
3. `modules/pipeline/pipe.v`:
   - Register forwarding multiplexers (`reg_rdata1`, `reg_rdata2`), reset zeroing, and WB stage port connections.

---

## 4. Hardware Verification & FPGA Peripheral Mapping

### 16 Discrete Status LEDs:
- **LED[0]**: Hazard Stall Active (Load-use, DIV, FPU)
- **LED[1]**: Data Forwarding Active (Operand bypass active)
- **LED[2]**: Branch / Misprediction Pipeline Flush
- **LED[3]**: Instruction Writeback Commit (`wb_reg_write`)
- **LED[4]**: Multiplier Unit Active (`mul_active`)
- **LED[5]**: Divider Unit Active (`div_active`)
- **LED[6]**: FPU Unit Active (`fpu_active`)
- **LED[7]**: Program Execution Completed (`prog_done`)
- **LED[8]**: **BTB Hit Indicator** (Stretched for visibility)
- **LED[9]**: **BTB Mispredict Indicator** (Stretched for visibility)
- **LED[10]**: **BTB Taken Prediction** (`btb_pred_taken`)
- **LED[15:11]**: Low bits of return value or committed data

### 8-Digit Seven-Segment Display (Multiplexed via `SW[2:0]`):
- `SW[2:0] = 3'b000`: Fetch PC Address (`pc_if`)
- `SW[2:0] = 3'b001`: Fetched Machine Instruction (`imem_rdata`)
- `SW[2:0] = 3'b010`: Total BTB Hits Counter
- `SW[2:0] = 3'b011`: Total BTB Mispredicts Counter
- `SW[2:0] = 3'b100`: Total Execution Cycles Counter
- `SW[2:0] = 3'b101`: Total Instructions Retired Counter
- `SW[2:0] = 3'b110`: Final Return Value in `x10` (`a0`)

---

## 5. Verification Commands

### Vivado Simulator:
```bash
cd simulation
make sim_btb       # Runs unit BTB testbench (8 assertions)
make sim_pipeline  # Runs full 5-stage pipeline branch loop testbench
```

### Icarus Verilog (`iverilog`):
```bash
# Unit BTB Testbench
iverilog -o sim_btb testbench/tb_btb.v modules/stages/btb_branch_pred.v && ./sim_btb

# Full Pipeline Integration Testbench
iverilog -I modules -I modules/stages -I modules/pipeline -I modules/registers \
  -o sim_pipe testbench/tb_feature7_pipeline.v modules/pipeline/pipeline_5stage.v \
  modules/hazard_unit.v modules/stages/*.v modules/registers/*.v && ./sim_pipe
```
