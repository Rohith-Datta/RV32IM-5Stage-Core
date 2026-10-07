# Feature 1: 5-Stage Pipeline Upgrade & Hazard Detection Unit

**Project:** Pipelined RV32IM RISC-V Core with L1 Cache Hierarchy and Dedicated Neural Network MAC Coprocessor  
**Course:** CS2202L (Group 13)  
**Deliverable Milestone (Week 5–11 Oct):** Base 5-Stage Pipeline Integration & Hazard Unit  
**Deliverables:** IF-WB pipeline registers, Forwarding multiplexer RTL + `tb_pipeline_base.v` and `tb_hazard.v`

---

## 1. Architectural Overview

Feature 1 upgrades the baseline 3-stage RISC-V processor to a classic **5-Stage Pipeline (IF -> ID -> EX -> MEM -> WB)** with full hazard detection, data forwarding, and branch resolution in the EX stage.

```
       +----+        +----+        +----+        +-----+        +----+
-----> | IF | -----> | ID | -----> | EX | -----> | MEM | -----> | WB | -----> (RegFile)
       +----+        +----+        +----+        +-----+        +----+
         ^             ^             ^              |              |
         |             |             |   Forward    |   Forward    |
         |             +-------------+--------------+--------------+
         |                 Hazard Detection & Forwarding Unit
         +---------------------------------------------------------+
                          Branch Redirect / Stall / Flush
```

### 5 Pipeline Stages:
1. **IF (Instruction Fetch):**
   - Program Counter register (`pc`) with branch/jump redirection support.
   - Sequential next PC (`pc + 4`).
   - Instruction Memory (IMEM) interface.
   - Stall support: Freezes `pc` on load-use hazards.

2. **ID (Instruction Decode & Register File Read):**
   - Extracts `opcode`, `rd`, `rs1`, `rs2`, `funct3`, `funct7/subtype`.
   - Generates control signals (`alu_op`, `immediate_sel`, `mem_read`, `mem_write`, `mem_to_reg`, `reg_write`, `branch`, `jal`, `jalr`, `lui`, `auipc`).
   - Immediate Generator (I, S, B, U, J types with standard sign extension).
   - 32-entry Register File (x0 hardwired to 0) with **internal writeback-to-decode forwarding** (WB -> ID).

3. **EX (Execution & Address Calculation):**
   - Dual Forwarding Multiplexers (`forward_a`, `forward_b`) selecting between ID/EX register data, EX/MEM forwarding, or MEM/WB forwarding.
   - 32-bit ALU supporting ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND, LUI, AUIPC, and return address generation (`pc + 4`).
   - Branch condition evaluation (BEQ, BNE, BLT, BGE, BLTU, BGEU) using signed/unsigned subtractors with borrow bits.
   - Target PC computation for branches (`pc + imm`), JAL (`pc + imm`), and JALR (`(rs1 + imm) & ~1`).

4. **MEM (Memory Access & Store Data Formatting):**
   - Data Memory (DMEM) interface.
   - Store formatting unit with alignment-aware byte enables:
     * `SB`: 8-bit replicate + 1-hot byte strobe `wstrb` (4'b0001, 4'b0010, 4'b0100, 4'b1000).
     * `SH`: 16-bit replicate + halfword strobe `wstrb` (4'b0011, 4'b1100).
     * `SW`: 32-bit word with full word strobe `wstrb` (4'b1111).

5. **WB (Writeback & Load Formatting):**
   - Formats raw data loaded from DMEM with byte alignment and sign/zero extension:
     * `LB`: 8-bit sign extended.
     * `LBU`: 8-bit zero extended.
     * `LH`: 16-bit sign extended.
     * `LHU`: 16-bit zero extended.
     * `LW`: 32-bit word.
   - Result multiplexer selecting between load data and ALU/jump return result.
   - Drives write port of Register File (`wb_reg_write`, `wb_dest_reg`, `wb_data`).

---

## 2. Pipeline Registers

Four dedicated pipeline registers isolate the stages:
1. `if_id_reg.v`: Latches `pc`, `pc_plus4`, and fetched `instruction`. Supports `stall` (freeze) and `flush` (clear to NOP).
2. `id_ex_reg.v`: Latches control signals, decoded operands (`rdata1`, `rdata2`, `imm`), and register indices (`rs1`, `rs2`, `rd`). Supports `stall` and `flush` (bubble insertion).
3. `ex_mem_reg.v`: Latches ALU result, forwarded store data, destination register `rd`, and memory control signals.
4. `mem_wb_reg.v`: Latches memory read data, ALU result, `rd`, and writeback control signals.

---

## 3. Hazard Detection & Forwarding Unit (`hazard_unit.v`)

### Data Forwarding:
Resolves Read-After-Write (RAW) data hazards without stalling the pipeline:
- **EX Hazard (EX/MEM -> EX):** Forwarded when `ex_mem_reg_write && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rs1/rs2)`. Select code: `2'b10`.
- **MEM Hazard (MEM/WB -> EX):** Forwarded when `mem_wb_reg_write && (mem_wb_rd != 0) && (mem_wb_rd == id_ex_rs1/rs2)`. Select code: `2'b01`.
- **Back-to-Back Priority:** EX/MEM is prioritized over MEM/WB to guarantee the most recently computed value is always selected.

### Load-Use Hazard Detection:
When an instruction in EX is a LOAD (`id_ex_mem_read`) and its `rd` matches `id_rs1` or `id_rs2` of the instruction in ID:
- Assert `stall_if = 1` (Freezes Program Counter).
- Assert `stall_if_id = 1` (Holds instruction in ID).
- Assert `flush_id_ex = 1` (Inserts exactly **1 bubble cycle** into ID/EX).
- **Latency penalty:** Exactly 1 clock cycle (matching Section 5 design commitment).

### Control Hazards (Branches & Jumps):
Resolved in the EX stage:
- When a branch condition is satisfied or an unconditional jump (JAL/JALR) executes:
  * Redirects PC to computed target address.
  * Flushes speculative instructions in IF/ID and ID/EX (`flush_if_id = 1`, `flush_id_ex = 1`).
  * **Flush penalty:** Exactly 2 clock cycles (matching Section 5 design commitment).
- When a branch is not taken, execution continues sequentially with **0 stall cycles**.

---

## 4. Directory Structure

```
feature_1/
├── modules/
│   ├── opcode.vh           # Opcode, funct3, control constants
│   ├── if_id_reg.v         # IF/ID pipeline register
│   ├── id_ex_reg.v         # ID/EX pipeline register
│   ├── ex_mem_reg.v        # EX/MEM pipeline register
│   ├── mem_wb_reg.v        # MEM/WB pipeline register
│   ├── hazard_unit.v       # Hazard detection and data forwarding unit
│   ├── decode_stage.v      # Decoder & 32-reg Register File
│   ├── execute_stage.v     # Forwarding muxes, 32-bit ALU, Branch logic
│   ├── memory_stage.v      # Memory store formatting & bus interface
│   ├── writeback_stage.v   # Memory load formatting & WB mux
│   ├── pipeline_5stage.v   # Top-level 5-stage RV32I Core
│   ├── pipe.v              # Backward-compatible wrapper
│   └── memory.v            # Instruction & Data memory simulation models
├── simulation/
│   ├── Makefile            # Simulation build automation
│   ├── filelist.txt        # Source file compilation manifest
│   ├── tb_hazard.v         # Dedicated unit testbench for hazards & forwarding
│   └── tb_pipeline_base.v  # Full-system integration testbench running Fibonacci
├── mem/
│   ├── imem.hex            # Compiled instruction memory image
│   ├── dmem.hex            # Initial data memory image
│   └── code.dis            # Disassembly of test benchmark
├── tb_hazard.v             # Root copy of tb_hazard
├── tb_pipeline_base.v      # Root copy of tb_pipeline_base
└── README.md               # Documentation & verification report
```

---

## 5. Verification & Simulation Results

Both testbenches were fully verified using **Vivado Simulator 2025.2 (`xvlog`, `xelab`, `xsim`)**:

### Testbench 1: `tb_hazard.v`
Validates 7 targeted hazard scenarios with automated self-checking assertions:
- `[PASS] Test 1: EX-to-EX Forwarding verified! (x2 = 15, expected 15)`
- `[PASS] Test 2: MEM-to-EX Forwarding verified! (x4 = 27, expected 27)`
- `[PASS] Test 3: Back-to-Back Hazard Priority verified! (x6 = 6, expected 6)`
- `[PASS] Test 4: Load-Use Hazard 1-cycle stall verified! (x8 = 20, stalls = 1)`
- `[PASS] Test 5: Store Data Forwarding verified! (x10 = 42, expected 42)`
- `[PASS] Test 6: Branch 2-cycle flush verified! (x11=0, x12=0, x13=100, flushes = 1)`
- `[PASS] Test 7: Register x0 hardwired zero verified! (x14 = 5, expected 5)`
- **Result:** `>>> ALL 7 HAZARD & FORWARDING TESTS PASSED (100% SUCCESS) <<<`

### Testbench 2: `tb_pipeline_base.v`
Executes the bare-metal compiled RISC-V Fibonacci benchmark (`fibonacci(5)`):
- Successfully executes 44 retired instructions.
- Correctly detects and resolves 18 load-use hazards and 6 branch flushes.
- Computes final Fibonacci value `a5 (x15) = 8`.
- Achieves continuous execution throughput with flawless pipeline advance.

---

## 6. How to Run Simulations

From the `feature_1/simulation/` directory:

```powershell
# Run Hazard Unit Testbench
make sim_hazard

# Run Full System Base Pipeline Testbench
make sim_pipeline

# Run Both Testbenches
make all

# Clean Simulation Artifacts
make clean
```
