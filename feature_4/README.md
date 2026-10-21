# Feature 4: RV32F Single-Precision Floating-Point Unit (FPU)

## Overview
**Feature 4** integrates a fully synthesizable **IEEE 754-2008 Single-Precision (32-bit) Floating-Point Unit (FPU)** into the 5-stage pipelined processor core (`IF`, `ID`, `EX`, `MEM`, `WB`).

The core implements the standard RISC-V RV32F floating-point arithmetic instructions:
- **`FADD.S`**: Floating-point addition
- **`FSUB.S`**: Floating-point subtraction
- **`FMUL.S`**: Floating-point multiplication
- **`FDIV.S`**: Floating-point division

The architecture unifies the RV32I base integer ISA, RV32M hardware multiplier and divider (Feature 2 & Feature 3), and RV32F floating-point capabilities into a single integrated **RV32IMF Processor Core** on the Digilent Nexys A7-100T FPGA clocked at **50 MHz**.

---

## Latency & Timing Specifications

The FPU strictly adheres to the requested cycle counts per arithmetic operation:

| Instruction | Funct7 | Cycle Latency in EX Stage | Execution Engine & Methodology |
|:---|:---:|:---:|:---|
| **`FADD.S`** | `7'b0000000` | **5 Clock Cycles** | Exponent align &gt; 27-bit Mantissa add/sub &gt; Leading-zero normalize &gt; RNE round |
| **`FSUB.S`** | `7'b0000100` | **5 Clock Cycles** | Sign inversion on operand B &gt; 5-cycle aligned mantissa computation &gt; RNE round |
| **`FMUL.S`** | `7'b0010000` | **4 Clock Cycles** | Exponent addition &gt; $24 \times 24$-bit mantissa product &gt; 1-bit normalize &gt; RNE round |
| **`FDIV.S`** | `7'b0001100` | **15 Clock Cycles** | Exponent subtraction &gt; 26-bit restoring division (2 bits/calc-cycle) &gt; RNE round |

*Note: All latencies are exact and verified cycle-by-cycle against the hardware clock.*

---

## IEEE 754-2008 Microarchitecture

### 1. Representation & Precision
Single-precision 32-bit floating-point numbers are decomposed as:
- **Sign ($S$)**: 1 bit (`[31]`)
- **Exponent ($E$)**: 8 bits (`[30:23]`), with standard bias $127$
- **Fraction ($F$)**: 23 bits (`[22:0]`), with hidden implicit leading bit ($1.F$) for normal numbers ($E \neq 0$)

Value:
$$V = (-1)^S \times 2^{E - 127} \times \left(1 + \sum_{i=1}^{23} b_{23-i} 2^{-i}\right)$$

### 2. Rounding Mode
- **Round to Nearest, Ties to Even (RNE)** (`frm = 3'b000`):
  - Uses Guard ($G$), Round ($R$), and Sticky ($S$) bits.
  - If $G=1$ and ($R=1 \lor S=1 \lor LSB=1$), mantissa is rounded up with potential renormalization.

### 3. Special Values Handled
- **Zero ($\pm 0$)**: Handled without underflow exceptions.
- **Infinity ($\pm\infty$)**: Proper propagation under overflow, divide-by-zero, or infinite inputs.
- **Divide by Zero**: Returns signed infinity ($\pm\infty$) and asserts divide-by-zero condition.
- **NaN (Not a Number)**: Default quiet NaN `32'h7FC00000` on invalid operations ($0/0$, $\infty - \infty$, $0 \times \infty$, etc.).

---

## Pipeline Integration & Hazard Interlock

### Multi-Cycle Stall Mechanism
When an RV32F instruction enters the Execution stage:
1. `is_fpu` is decoded from `OP_FP` (`7'b1010011`).
2. `fpu_single_core.v` latches input operands and asserts `fpu_busy_o = 1`.
3. The centralized hazard unit (`hazard_unit.v`) triggers a multi-cycle stall (`math_busy = div_busy || fpu_busy`):
   - **`stall_if = 1`**: Freezes Program Counter (`pc_reg`).
   - **`stall_if_id = 1`**: Freezes IF/ID pipeline register.
   - **`stall_id_ex = 1`**: Freezes ID/EX pipeline register holding current FPU instruction in EX.
   - **`flush_ex_mem = 1`**: Injects synchronous NOP bubbles into EX/MEM to avoid speculative hazard propagation.
4. When calculation reaches completion state `S_DONE`:
   - `fpu_busy_o` drops to `0`.
   - Result is multiplexed into `ex_alu_result` and clocked into `ex_mem_reg`.
   - Normal pipeline flow resumes.

### Data Forwarding Support
- Forwarding unit supports full forwarding from `EX/MEM` and `MEM/WB` stages into FPU operands $A$ and $B$.
- Dependent instructions execute back-to-back with zero stall penalty once previous result commits.

---

## Directory Organization

```
feature_4/
├── modules/
│   ├── opcode.vh                       # Central RISC-V definitions & RV32F opcodes/funct7
│   ├── hazard_unit.v                   # Stall & forwarding unit with FPU interlock
│   ├── fpga/
│   │   ├── fpga_top_feature4.v         # Synthesizable top-level wrapper for Nexys A7
│   │   └── seven_seg_controller.v     # 8-digit multiplexed 7-segment display
│   ├── pipeline/
│   │   ├── pipe.v                      # Pipeline register abstraction
│   │   └── pipeline_5stage.v           # Complete 5-stage RV32IMF processor core
│   ├── registers/
│   │   ├── if_id_reg.v                 # IF/ID pipeline register
│   │   ├── id_ex_reg.v                 # ID/EX pipeline register with is_fpu
│   │   ├── ex_mem_reg.v                # EX/MEM pipeline register with bubble flush
│   │   └── mem_wb_reg.v                # MEM/WB pipeline register
│   ├── stages/
│   │   ├── decode_stage.v              # Decoder supporting RV32I, RV32M, and RV32F
│   │   ├── execute_stage.v             # EX stage with ALU, Multiplier, Divider & FPU
│   │   ├── fpu_single_core.v           # IEEE 754-2008 single-precision FPU core
│   │   ├── divider_unit.v              # RV32M Radix-2 hardware divider
│   │   ├── multiplier_unit.v           # RV32M unified hardware multiplier
│   │   ├── multiplier_dsp.v            # DSP48E1 single-cycle multiplier
│   │   ├── booth_radix4_multiplier.v   # Modified Booth Radix-4 multiplier
│   │   ├── memory_stage.v              # Store formatting and alignment
│   │   ├── memory.v                    # Dual BRAM models (IMEM & DMEM)
│   │   └── writeback_stage.v           # Load data extension & writeback mux
│   └── uart/
│       ├── uart_tx.v                   # 115200 baud UART transmitter
│       └── uart_unit.v                 # MMIO + real-time hardware telemetry
├── testbench/
│   ├── tb_fpu.v                        # Unit testbench for FPU (cycle counts & precision)
│   ├── tb_feature4_pipeline.v          # 5-stage pipeline integration testbench
│   ├── tb_pipeline_base.v              # Base integer testbench
│   └── tb_uart.v                       # MMIO UART testbench
├── simulation/
│   ├── filelist.txt                    # Simulation source list
│   ├── Makefile                        # Vivado xsim automated compile & test flow
│   └── run_simulation.bat              # Batch simulation runner
├── constraints/
│   └── nexys_a7_100t.xdc               # Physical constraints for Nexys A7-100T (50 MHz)
├── mem/
│   ├── imem.hex                        # Instruction memory hex
│   └── dmem.hex                        # Data memory hex
├── create_vivado_project.tcl           # Automated Vivado project creation script
├── build_bitstream.tcl                 # Headless bitstream build script
├── open_vivado.bat                     # Vivado project launcher
└── README.md
```

---

## Nexys A7 FPGA Peripheral Mapping

| Peripheral | Pin | Description |
|:---|:---:|:---|
| **LED[0]** | `H17` | Hazard Stall (active during load-use, DIV, or FPU calculation) |
| **LED[1]** | `K15` | Forwarding Active into EX operands |
| **LED[2]** | `J13` | Branch / Jump Flush Active |
| **LED[3]** | `N14` | Writeback Commit Active (`wb_reg_write`) |
| **LED[4]** | `R18` | Multiplier Active Indicator (`mul_active`) |
| **LED[5]** | `V17` | Divider Active Indicator (`div_active`) |
| **LED[6]** | `U17` | **FPU Active Indicator (`fpu_active`)** |
| **LED[7]** | `U16` | Program Execution Complete |
| **LED[15:8]** | `V11..H6` | Low 8 bits of committed writeback result (`wb_data[7:0]`) |
| **7-Segment Display** | `J17..L18` | Displays PC (`sw[2]=0`) or Instruction Word (`sw[2]=1`) |
| **sw[0]** | `J15` | Single-Step Clock Mode (`1` = manual step via `btnc`) |
| **sw[1]** | `L16` | Slow Clock Mode (1 Hz) |
| **sw[2]** | `M13` | 7-Segment Display Mode (`0` = PC, `1` = Instruction) |
| **sw[3]** | `R15` | Multiplier Engine Select (`0` = DSP48E1, `1` = Booth Radix-4) |
| **btnc** | `N17` | Manual Clock Step Pulse |
| **cpu_resetn** | `C12` | Active-Low Asynchronous Reset |
| **uart_tx** | `D4` | 115200 Baud Serial Telemetry output |

---

## Verification & Test Results

### 1. FPU Unit Verification (`tb_fpu.v`)
- Total Test Vectors: **14**
- **Results: 14 / 14 Passed (100% Pass Rate)**
- Exact Latencies Verified:
  - `FADD.S`: Exactly **5 cycles**
  - `FSUB.S`: Exactly **5 cycles**
  - `FMUL.S`: Exactly **4 cycles**
  - `FDIV.S`: Exactly **15 cycles**
- Edge cases tested:
  - Exact powers of two, fractional quotients ($1.0 / 3.0 \rightarrow \text{0x3EAAAAAB}$), divide-by-zero ($10.0 / 0.0 \rightarrow +\infty$), negative dividends, and subtractions yielding zero.

### 2. 5-Stage Pipeline Verification (`tb_feature4_pipeline.v`)
- Total Integration Checks: **17**
- **Results: 17 / 17 Passed (100% Pass Rate)**
- Tests verified:
  - `FADD.S` multi-cycle stall (5 cycles) and writeback commit to register file.
  - RAW Data Forwarding: `FADD.S x3, x1, x2` followed immediately by `FMUL.S x5, x3, x4` (forwarding $4.0$ directly into multiplier operand without stale data).
  - Multi-cycle interlock: `FDIV.S` stalling the pipeline for 15 cycles, preventing subsequent instructions from committing until quotient is valid.
  - Interleaved base integer (`ADDI`) and floating-point computations.

### 3. Base Integer Core (`tb_pipeline_base.v`)
- **Results: 5 / 5 Passed (100% Pass Rate)**

### 4. UART Telemetry (`tb_uart.v`)
- **Results: 100% Pass Rate**

---

## How to Build & Simulate

### 1. Run Simulation in Terminal
```cmd
cd feature_4\simulation
run_simulation.bat
```
Or with Vivado xsim:
```cmd
xvlog -i ../modules -i ../modules/pipeline -i ../modules/stages -i ../modules/registers -i ../modules/fpga -i ../modules/uart -f filelist.txt ../testbench/tb_feature4_pipeline.v
xelab tb_feature4_pipeline -s snap_tb_fpu_pipe -timescale 1ns/1ps
xsim snap_tb_fpu_pipe -R
```

### 2. Open Standalone Vivado Project
Double click or run:
```cmd
feature_4\open_vivado.bat
```
Project is located at `feature_4/vivado_project/rv32mf_fpu_fpga.xpr`.

### 3. Headless Bitstream Generation
```cmd
vivado -mode batch -source feature_4/build_bitstream.tcl -nojournal -nolog
```
