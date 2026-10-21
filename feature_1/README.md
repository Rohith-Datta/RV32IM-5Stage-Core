# Feature 1: 5-Stage Pipeline Upgrade & Hazard Detection Unit

**Project:** Pipelined RV32IMF RISC-V Core with L1 Cache Hierarchy, Branch Prediction, and Hardware Math Accelerators  
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

---

## 7. FPGA Implementation & Board Mapping (Digilent Nexys A7-100T)

The 5-stage core has a dedicated FPGA top-level wrapper (`modules/fpga_top_feature1.v`) and XDC constraints file (`constraints/nexys_a7_100t.xdc`) targeted to the Xilinx Artix-7 XC7A100T FPGA.

### Board Peripherals & Visual Feedback

| Peripheral | Board Location | Core Signal Connected | Hardware Behavior & Visual Indication |
|---|---|---|---|
| **8-Digit 7-Segment Display** | Located directly **ABOVE the 16 LEDs** | `imem_addr` / `pc_if[31:0]` | **Displays the 32-bit Address Being Fetched** in real-time (8 hex characters, e.g. `00000028`), multiplexed across all 8 digits at ~763 Hz without flicker. |
| **LED[0]** | Discrete LED 0 (Pin `H17`) | `hazard_stall` | **DATA HAZARD LED:** Turns ON whenever a data hazard is detected (load-use stall freeze). Features ~50ms pulse-stretching for clear naked-eye visibility at 100 MHz. |
| **LED[1]** | Discrete LED 1 (Pin `K15`) | `(forward_a != 0) \|\| (forward_b != 0)` | **DATA FORWARDING LED:** Turns ON whenever data forwarding is active (operand bypass from EX/MEM or MEM/WB). Pulse-stretched. |
| **LED[2]** | Discrete LED 2 (Pin `J13`) | `hazard_flush_id` | **BRANCH FLUSH LED:** Turns ON when a branch misprediction or jump flush annuls instructions. |
| **LED[3]** | Discrete LED 3 (Pin `N14`) | `wb_reg_write` | **RETIREMENT LED:** Turns ON whenever an instruction commits to the Register File. |
| **LED[5:4]** | Discrete LEDs 5:4 | `forward_a[1:0]` | Raw Forwarding code for Operand A (`01`: EX/MEM, `10`: MEM/WB). |
| **LED[7:6]** | Discrete LEDs 7:6 | `forward_b[1:0]` | Raw Forwarding code for Operand B (`01`: EX/MEM, `10`: MEM/WB). |
| **LED[15:8]** | Discrete LEDs 15:8 | `wb_data[7:0]` | Displays low byte of retired register result (e.g. `102` = `0x66`). |
| **Switch sw[0]** | Slide Switch 0 (Pin `J15`) | Clock Mode | `0` = Continuous Execution, `1` = Manual Single-Step Clock Mode via `btnc`. |
| **Switch sw[1]** | Slide Switch 1 (Pin `L16`) | Speed Select | `0` = 50 MHz core speed, `1` = 1 Hz slow clock for live visual tracking (1 instruction/cycle per second). |
| **Switch sw[2]** | Slide Switch 2 (Pin `M13`) | Display Select | `0` = 7-Segment shows **Fetch PC Address** (e.g. `00000028`), `1` = Shows **32-bit Machine Instruction Code** (e.g. `00F707B3` for `add`). |
| **Switch sw[3]** | Slide Switch 3 (Pin `R15`) | UART Mode | `0` = Standard CPU MMIO `printf` mode, `1` = **Auto-Telemetry Step Streamer** (dumps PC and committed register over serial on every step). |
| **UART TX Pin**  | USB-UART Bridge (Pin `D4`) | `uart_tx` | **115,200 Baud Serial Stream** (8-N-1): Connect micro-USB cable to PC; open PuTTY/Tera Term at 115200 baud to see live diagnostics and program text. |
| **UART RX Pin**  | USB-UART Bridge (Pin `C4`) | `uart_rx` | Serial Receive from Host PC terminal. |
| **Button btnc** | Center Pushbutton (Pin `N17`)| Step Clock | In step mode (`sw[0]=1`), advances pipeline by exactly 1 clock cycle per press. |
| **Button reset**| CPU Reset (Pin `C12`) | `cpu_resetn` | Active-low master synchronous reset. Restarts execution from `PC=0x00` and emits UART boot banner. |

---

## 8. Interactive Terminal Pipeline Simulation & Trace Visualizer

A full-system cycle-by-cycle pipeline trace tool is available via `run_pipeline_trace.py`:

```bash
# Run standard compiled C benchmarks with cycle-by-cycle trace:
python run_pipeline_trace.py addition
python run_pipeline_trace.py fibonacci
python run_pipeline_trace.py sort
python run_pipeline_trace.py negative
python run_pipeline_trace.py xor

# Run custom inline assembly instructions:
python run_pipeline_trace.py --asm "addi x1, x0, 15; addi x2, x0, 25; add x3, x1, x2; addi x10, x3, 0; ret"

# Run custom C, Assembly, or Hex file:
python run_pipeline_trace.py custom_prog.c
python run_pipeline_trace.py custom_prog.s
python run_pipeline_trace.py custom_prog.hex
```

### What `run_pipeline_trace.py` Displays on the Terminal Screen:

1. **Static Instruction Memory Listing**: Address, 32-bit machine word, and decoded instruction mnemonic for every instruction in memory.
2. **Cycle-by-Cycle Pipeline Trace Table**: Shows the exact instruction present in each stage at each clock cycle:
   - `CC`: Clock cycle number
   - `FETCH (IF)`: PC address and instruction being fetched (displayed on the 8 seven-segment lights).
   - `DECODE (ID)`: PC address and instruction being decoded.
   - `EXECUTE (EX)`: PC address and instruction executing in the ALU.
   - `MEMORY (MEM)`: PC address and memory access operation.
   - `WRITEBACK (WB)`: PC address and register retirement value (`rd <= value`).
   - `HAZARDS & FORWARDING NOTES`: Live annotations showing:
     - `>>> [DATA HAZARD STALL] (LED[0] ON! Freeze IF/ID, bubble to EX)`
     - `[*] [DATA FORWARDING] (LED[1] ON! A:EX/MEM, B:MEM/WB)`
     - `[!] [BRANCH/CONTROL FLUSH] (LED[2] ON! Annulling IF/ID)`
     - `[+] [RETIRE] rd = val (LED[3] ON)`
3. **Dynamic Instruction Execution Order**: Chronological list of retired instructions in the exact order they executed.
4. **FPGA Hardware Verification Summary**: Total cycles, retired instructions, IPC throughput, hazard stall counts, forwarding event counts, and final return value in `a0` (`x10`).

---

## 9. Opening in AMD Vivado GUI

The project files and scripts are housed directly within `feature_1`:

1. **One-Click Launch:**
   - Double-click or run `open_vivado.bat` inside `feature_1/` (or run `open_vivado.bat` at the repository root, which forwards here).
2. **Batch Generation:**
   - If regenerating from scratch:
     ```bash
     cd feature_1
     vivado -mode batch -source create_vivado_project.tcl
     ```
3. **Direct Project File:**
   - Double-click `feature_1/vivado_project/rv32i_5stage_core.xpr`.

---

## 10. UART Diagnostic & Telemetry Subsystem (115,200 Baud)

Feature 1 includes a full-duplex capable **Universal Asynchronous Receiver-Transmitter (UART)** subsystem connected to the onboard FTDI FT2232HQ USB-to-UART bridge on the Nexys A7:

* **Hardware Transmitter (`uart_tx.v`):** Standard 8-N-1 framing (1 start bit, 8 data bits, 1 stop bit) clocked by the stable 100 MHz oscillator.
* **Buffer Architecture:** 64-byte circular FIFO buffer preventing character loss during rapid CPU burst writes.
* **FPGA Pins:** 
  * `uart_tx`: Pin `D4` (FPGA transmit $\rightarrow$ FTDI chip $\rightarrow$ PC Terminal).
  * `uart_rx`: Pin `C4` (FPGA receive $\leftarrow$ FTDI chip $\leftarrow$ PC Terminal).

### Memory-Mapped I/O (MMIO) Register Map

| Register Name | Byte Address | Access | Bit Field Description |
|---|:---:|:---:|---|
| **`UART_TX_DATA`** | `0x8000_0000` | Write-Only | `[7:0]`: ASCII character byte written into UART TX FIFO. |
| **`UART_STATUS`**  | `0x8000_0004` | Read-Only  | `[0]`: `uart_busy` (1 = Transmitting or FIFO not empty)<br>`[1]`: `fifo_full` (1 = FIFO full, wait before write)<br>`[2]`: `fifo_empty` (1 = All characters transmitted) |

### Bare-Metal C Usage (`c_tests/uart.h`)

```c
#include "uart.h"

int main(void) {
    uart_puts("RV32I Core Initialized on Nexys A7!\n");
    uart_puts("Committed Result: ");
    uart_puthex(102);
    uart_putc('\n');
    return 102;
}
```

### Live Terminal Verification on Host PC
1. Connect the Nexys A7 micro-USB cable to your laptop.
2. Open any serial terminal (e.g., **PuTTY**, **Tera Term**, or `minicom`).
3. Set the port to the board's virtual COM port (e.g. `COM3` on Windows) at **115200 Baud, 8 Data Bits, 1 Stop Bit, No Parity**.
4. Press the red **CPU Reset Button (`C12`)**: The terminal immediately displays:
   ```text
   ===================================================
    RV32I Core (Group 13) Active @ 115200 Baud
   ===================================================
   ```
5. In Single-Step Mode (`sw[0]=1, sw[3]=1`), every press of the center button `btnc` dumps the execution state:
   ```text
   [PC:0x00000028 | WB:x14=0x00000066 | OK]
   ```

