# Feature 8: Static 32-Entry Branch Target Buffer (BTB) Dual Verification System

## 1. Overview & Architectural Scope
Feature 8 integrates and validates the **Static 32-Entry Branch Target Buffer (BTB)** within the 5-stage pipelined RV32IMF processor core.
- **Microarchitecture Target**: 5-Stage RV32IMF Core running at 50 MHz.
- **Target FPGA**: Digilent Nexys A7-100T (Xilinx Artix-7 XC7A100T-1CSG324C).
- **Core Benefit**: Eliminates the 2-cycle control hazard penalty on repeated loops and taken branches by predicting branch direction and target address in the Fetch (IF) stage with **0 penalty cycles**.
- **Dual Telemetry Support**:
  1. **Phase 1: 16-Cycle Synthetic BTB Verification Benchmark**: Strict cycle-by-cycle EX stage trace table and hardware counters (1 hit, 2 misses, 33% accuracy, 4 penalty cycles).
  2. **Phase 2: Bare-Metal C Program (`btb.c`)**: Simple C program verifying loop-branch prediction in compiled C, completing in **76 cycles** ($\le 80$ cycles max) with return value `a0 = 6`, 5 branches, 3 hits, 2 misses, 60% accuracy.

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
- **Target PC**: 32-bit pre-computed branch destination.
- **Valid Bit**: 1 bit per entry (cold start initialized to `0`).
- **Hit Detection (IF Stage)**: Query in parallel with instruction fetch. On a BTB Hit, `pc_next` redirects to `pred_target` immediately (0 bubble penalty).
- **Resolution (EX Stage)**: Actual branch condition evaluated.
  - If prediction matches actual: Branch commits with 0 stall penalty.
  - If prediction fails (mispredict): IF/ID and ID/EX are flushed (2 bubbles), BTB is updated/invalidated, and fetch redirects to correct PC.

---

## 3. Dual Execution Programs

### 3.1 Phase 1: Synthetic 16-Cycle Benchmark
Executes from memory address `0x00000000`:
```assembly
0x00000000     addi x1, x0, 2      // Set loop counter (evaluated across 3 branch passes)
0x00000004     addi x2, x0, 0      // Initialize accumulator
0x00000008     addi x2, x2, 1      // LOOP START: Increment accumulator
0x0000000C     addi x1, x1, -1     // Decrement counter
0x00000010     bne  x1, x0, -8     // Branch back to 0x00000008 if x1 != 0
0x00000014     nop                 // Loop exit target
```
- **Branch 1 (Cycle 5):** Taken, Cold BTB Miss -> 2 penalty flush cycles (Cycles 6, 7).
- **Branch 2 (Cycle 10):** Taken, BTB HIT -> 0 penalty cycles!
- **Branch 3 (Cycle 13):** Not Taken, BTB Predicted Taken -> 2 penalty flush cycles (Cycles 14, 15).
- **Cycle 16:** PC `0x14` completes EX stage. Total branches: 3, hits: 1, misses: 2, accuracy: 33%.

### 3.2 Phase 2: Bare-Metal C Program (`c_tests/btb.c` & `feature_8/mem/btb.c`)
```c
int main(void) {
    int sum = 0;
    for (int i = 0; i < 4; i++) {
        sum += i;
    }
    return sum; // Expected return: 6 (0x06)
}
```
- Total Execution Cycles: **76 clock cycles** ($\le 80$ cycles).
- Final Return Value in `a0`: **6** (`0x00000006`).
- Total Branches Executed: **5** (`bge` evaluated 5 times).
- Correct Predictions (Hits): **3** (Cycles 28, 40, 52).
- Mispredictions (Misses): **2** (Cycle 14 cold miss, Cycle 64 loop exit).
- Prediction Accuracy: **60%** ($3 \times 100 / 5$).

---

## 4. Hardware Peripheral Mapping & Verification Controls

### Slide Switches (`sw[15:0]`):
- **`sw[4]` / `sw[5]`**:
  - `sw[4] = 0` (Default): Automatic Sequential Mode (Executes Benchmark, then executes C Program).
  - `sw[4] = 1, sw[5] = 0`: Runs Bare-Metal C Program only.
  - `sw[4] = 1, sw[5] = 1`: Runs Synthetic Benchmark only.
- **`sw[3]`**:
  - `sw[3] = 0`: 7-segment display shows Bare-Metal C Program statistics.
  - `sw[3] = 1`: 7-segment display shows Benchmark statistics.
- **`sw[2:0]`**:
  - `3'b000`: Total Branches Executed
  - `3'b001`: Correct Predictions (Hits)
  - `3'b010`: Mispredictions (Misses)
  - `3'b011`: Prediction Accuracy Percentage
  - `3'b100`: Flush Penalties / Instructions Retired
  - `3'b101`: Return Value `a0` (Displays `0x00000006`)
  - `3'b110`: Total Execution Cycles (Displays `76` for C program)
  - `3'b111`: Test Pattern `0x0000C0DE`

### 16 Status LEDs (`led[15:0]`):
- **LED[0]**: BTB Query Hit (`btb_pred_hit`)
- **LED[1]**: BTB Misprediction Active (`btb_mispredict`)
- **LED[2]**: BTB Taken Prediction (`btb_pred_taken`)
- **LED[3]**: Pipeline Flush Active
- **LED[4]**: Benchmark Run Active
- **LED[5]**: Benchmark Run Done
- **LED[6]**: C Program Run Active
- **LED[7]**: C Program Run Done
- **LED[8]**: All UART Transmission Complete
- **LED[9]**: Pass Verification Flag (`a0 == 6`)
- **LED[10]**: UART Serial Transmitter Busy
- **LED[11]**: Active Phase Indicator
- **LED[15:12]**: Final Return Value low nibble (`a0[3:0] = 4'b0110` = 6)

---

## 5. Verification Commands

### Run PowerShell UART Monitor:
```powershell
powershell -ExecutionPolicy Bypass -File feature_8\read_uart.ps1
```

### Compile Custom C Test to Feature 8:
```powershell
python c_tests/build_hex.py btb --feature 8
```

### Run Vivado Simulation:
```powershell
Set-Location feature_8\simulation
xvlog -i ../modules -i ../modules/stages -i ../modules/pipeline -i ../modules/registers -i ../modules/fpga -f filelist.txt ../testbench/tb_fpga_top_feature8.v
xelab -top tb_fpga_top_feature8 -snapshot snap_tb_fpga_top -debug typical
xsim snap_tb_fpga_top -R
```
