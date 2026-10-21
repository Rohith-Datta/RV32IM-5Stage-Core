# Feature 3: RV32M Hardware Divider & Remainder Unit

## Overview
**Feature 3** introduces full hardware support for the 4 division and remainder instructions of the official **RISC-V RV32M Standard Extension** (`DIV`, `DIVU`, `REM`, `REMU`) into the 5-stage pipelined processor core.

The processor core preserves all RV32I base integer instructions and RV32M hardware multiplication engines (DSP48E1 slices and Radix-4 Booth multiplier from Feature 2), creating a comprehensive **RV32IM 5-Stage Processor Core** with real-time USB-UART telemetry and Digilent Nexys A7 FPGA peripheral integration.

---

## Architecture Specifications

### 1. Instruction Decoding
- **Opcode**: `7'b0110011` (`ARITHR`)
- **funct7**: `7'b0000001` (`FUNCT7_M_EXT`)
- **funct3 Operations**:
  | Mnemonic | funct3 | Operation | Description |
  |---|:---:|:---:|---|
  | `DIV`  | `3'b100` | $Q = \lfloor A / B \rfloor$ | Signed 32-bit quotient |
  | `DIVU` | `3'b101` | $Q = A / B$ | Unsigned 32-bit quotient |
  | `REM`  | `3'b110` | $R = A - B \times \lfloor A / B \rfloor$ | Signed 32-bit remainder ($\text{sign}(R) == \text{sign}(A)$) |
  | `REMU` | `3'b111` | $R = A \pmod B$ | Unsigned 32-bit remainder |

### 2. RISC-V Specification Architectural Corner Cases
Strictly compliant with Chapter 7 of the *RISC-V Instruction Set Manual, Volume I: User-Level ISA*:
- **Divide by Zero ($B = 0$):**
  - `DIV(x, 0)` $\rightarrow -1$ (`32'hFFFF_FFFF`)
  - `DIVU(x, 0)` $\rightarrow 2^{32}-1$ (`32'hFFFF_FFFF`)
  - `REM(x, 0)` $\rightarrow x$ (dividend)
  - `REMU(x, 0)` $\rightarrow x$ (dividend)
  - *Hardware Optimization*: 1-cycle early-out bypass directly to WB without stalling for 32 cycles.
- **Signed Overflow ($\text{INT\_MIN} / -1$ where $\text{INT\_MIN} = \text{0x8000_0000}$):**
  - `DIV(0x80000000, 0xFFFFFFFF)` $\rightarrow \text{0x8000_0000}$ ($\text{INT\_MIN}$)
  - `REM(0x80000000, 0xFFFFFFFF)` $\rightarrow 0$
  - *Hardware Optimization*: 1-cycle early-out bypass directly to WB.

### 3. Multi-Cycle Pipeline Interlock & Stall Mechanism
- **Hardware Engine**: 32-cycle Radix-2 Restoring Divider FSM (`divider_unit.v`).
- **Interlock Coordination (`hazard_unit.v`)**:
  - When a `DIV`/`REM` instruction enters the EX stage, `divider_unit` latches operands and asserts `div_busy = 1`.
  - While `div_busy == 1`:
    - `stall_if = 1`: Freezes Program Counter (`pc_reg`).
    - `stall_if_id = 1`: Holds IF/ID pipeline register.
    - `stall_id_ex = 1`: Holds ID/EX pipeline register so the division instruction remains active in the EX stage.
    - `flush_ex_mem = 1`: Inserts NOP bubbles into EX/MEM so unready division data does not corrupt MEM/WB stages.
  - When calculation completes (`div_done == 1`):
    - `div_busy` drops to `0`.
    - Pipeline resumes, `ex_alu_result` multiplexes `div_result`, and commits cleanly into `ex_mem_reg`.

---

## Directory Organization
Follows strict modular repository hierarchy:
```
feature_3/
├── modules/
│   ├── opcode.vh                       # Central RISC-V definitions & RV32M funct3
│   ├── hazard_unit.v                   # Forwarding, load-use stall, & div_busy interlock
│   ├── fpga/
│   │   ├── fpga_top_feature3.v         # Dedicated top synthesizable FPGA module
│   │   └── seven_seg_controller.v     # 8-digit multiplexed 7-segment display
│   ├── pipeline/
│   │   ├── pipe.v                      # Pipeline register abstraction
│   │   └── pipeline_5stage.v           # 5-Stage RV32IM processor core
│   ├── registers/
│   │   ├── if_id_reg.v                 # IF/ID stage register
│   │   ├── id_ex_reg.v                 # ID/EX stage register with is_div
│   │   ├── ex_mem_reg.v                # EX/MEM stage register with flush bubble
│   │   └── mem_wb_reg.v                # MEM/WB stage register
│   ├── stages/
│   │   ├── decode_stage.v              # Decoder with RV32M MUL/DIV & register file
│   │   ├── execute_stage.v             # EX stage with ALU, Multiplier & Divider
│   │   ├── divider_unit.v              # Radix-2 Restoring Divider FSM
│   │   ├── multiplier_unit.v           # Unified multiplier interface
│   │   ├── multiplier_dsp.v            # DSP48E1 single-cycle multiplier
│   │   ├── booth_radix4_multiplier.v   # Modified Booth Radix-4 multiplier
│   │   ├── memory_stage.v              # Store formatting and alignment
│   │   ├── memory.v                    # Dual BRAM models (IMEM & DMEM)
│   │   └── writeback_stage.v           # Load data sign/zero-extension & commit
│   └── uart/
│       ├── uart_tx.v                   # 115200 baud UART transmitter
│       └── uart_unit.v                 # MMIO + real-time hardware telemetry
├── testbench/
│   ├── tb_divider.v                    # Exhaustive unit testbench (129 vectors)
│   ├── tb_feature3_pipeline.v          # 5-stage pipeline integration testbench
│   ├── tb_multiplier.v                 # Multiplier unit testbench
│   └── tb_pipeline_base.v              # Full system testbench for compiled C tests
├── simulation/
│   ├── filelist.txt                    # Simulation source list
│   └── Makefile                        # Automated Vivado simulator flow
├── mem/
│   ├── division.c                      # C test benchmark (100 / 7 + 100 % 7 = 16)
│   ├── imem.hex                        # Instruction memory hex
│   └── dmem.hex                        # Data memory hex
├── constraints/
│   └── nexys_a7_100t.xdc               # Physical pin mapping for Nexys A7-100T
├── create_vivado_project.tcl           # Tcl project generator script
├── build_bitstream.tcl                 # Automated bitstream generation
├── open_vivado.bat                     # Windows batch launcher for Vivado GUI
├── run_pipeline_trace.py               # Cycle-by-cycle terminal visualizer
└── README.md
```

---

## Nexys A7 FPGA Peripheral Mapping

| Peripheral | Port Pin | Function |
|---|:---:|---|
| **LED[0]** | `H17` | Hazard Stall (Load-use or Multi-Cycle Divider interlock active) |
| **LED[1]** | `K15` | Data Forwarding Active into ALU/Multiplier/Divider |
| **LED[2]** | `J13` | Branch / Jump / Speculative Flush |
| **LED[3]** | `N14` | Instruction Writeback Commit (`wb_reg_write`) |
| **LED[4]** | `R18` | Multiplier Unit Active Indicator (`mul_active`) |
| **LED[5]** | `V17` | Divider Unit Active Indicator (`div_active` / `div_busy`) |
| **LED[6]** | `U17` | DSP Multiplier Mode Indicator (`sw[3] == 0`) |
| **LED[7]** | `U16` | Program Execution Completed (`prog_done`) |
| **LED[15:8]** | `V11..H6` | Low 8 bits of committed writeback result (`wb_data[7:0]`) |
| **7-Seg Display** | `J17..L18` | `sw[2]=0`: Current Fetch PC (`pc_if`), `sw[2]=1`: Machine Code (`imem_rdata`) |
| **sw[0]** | `J15` | Single-Step Mode (`1` = Manual step via `btnc`, `0` = Continuous) |
| **sw[1]** | `L16` | Slow Clock Mode (`1` = 1 Hz auto-step for human observation) |
| **sw[2]** | `M13` | 7-Segment Display Select (`0` = PC, `1` = Instruction Code) |
| **sw[3]** | `R15` | Multiplier Engine (`0` = DSP48E1, `1` = Booth Radix-4) |
| **btnc** | `N17` | Manual Clock Step Pulse Pushbutton |
| **cpu_resetn** | `C12` | Active-Low CPU Reset Pushbutton |
| **uart_tx** | `D4` | USB-UART Serial Telemetry (115,200 Baud) |

---

## Verification & Test Results

### 1. Exhaustive Unit Verification (`tb_divider.v`)
- Total test vectors run: **129**
- Vectors Passed: **129 / 129 (100% Pass Rate)**
- Verified operations:
  - All 4 signed/unsigned combinations for `DIV`, `DIVU`, `REM`, `REMU`.
  - Divide-by-Zero across positive and negative operands.
  - Signed Overflow ($\text{INT\_MIN} / -1$).
  - 100 randomized vectors verified against golden software reference.

### 2. Pipeline Integration Verification (`tb_feature3_pipeline.v`)
- Back-to-back `div` and `rem` instructions.
- Operand forwarding from MEM and WB stages into divider.
- Forwarding of divider result to dependent ALU instructions (`div x3` &rarr; `addi x5, x3, 10`).
- Assertions Passed: **7 / 7 (100% Pass Rate)**.

### 3. C Test Execution (`division.c`)
- Program:
  ```c
  int a = 100;
  int b = 7;
  int q = a / b;  // 14
  int r = a % b;  // 2
  return q + r;   // 16 (0x10)
  ```
- Result: Returns **16 (`0x00000010`)** in register `a0` (`x10`).

### 4. UART Subsystem Verification (`tb_uart.v`)
- Verifies MMIO character writes (`0x8000_0000`), 64-byte FIFO queuing, 115,200 baud serialization, and boot banner transmission.
- Automatically monitors `uart_tx` serial framing with a behavioral receiver model.
- Result: **100% Pass Rate**.
