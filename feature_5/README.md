# Feature 5: 5-Stage RV32IMF Core with Direct-Mapped L1 Data Cache (D-Cache)

## Overview
**Feature 5** introduces a synthesizable **2 KB Direct-Mapped L1 Data Cache (D-Cache)** into the Memory (MEM) stage of the 5-stage pipelined processor core (`IF`, `ID`, `EX`, `MEM`, `WB`).

The D-Cache dramatically reduces the average memory access time (AMAT) for load instructions (`LB`, `LBU`, `LH`, `LHU`, `LW`) and store instructions (`SB`, `SH`, `SW`). The processor architecture unifies the RV32I integer base, RV32M hardware multiplier and divider (Feature 2 & Feature 3), RV32F single-precision FPU (Feature 4), and the L1 D-Cache into an integrated **RV32IMF Processor Core** on the Digilent Nexys A7-100T FPGA clocked at **50 MHz**.

---

## Architectural Specifications

### 1. Cache Geometry & Organization
| Parameter | Specification | Details |
|---|:---:|---|
| **Cache Type** | **Direct-Mapped L1 Data Cache** | Low latency, single-cycle combinational read on hit |
| **Capacity** | **2 KB** (2,048 Bytes / 512 Words) | Sized for Artix-7 BRAM efficiency |
| **Line / Block Size** | **16 Bytes** (4 Words / 128 bits) | Enables 4-word spatial locality burst refills |
| **Number of Cache Lines** | **128 Lines (Sets)** | $2048\text{ B} / 16\text{ B} = 128$ lines |
| **Tag Width** | **21 bits** (`[31:11]`) | Distributed LUT RAM storage |
| **Index Width** | **7 bits** (`[10:4]`) | $2^7 = 128$ index sets |
| **Word Offset** | **2 bits** (`[3:2]`) | Selects 1 of 4 words in the 16-byte block |
| **Byte Offset** | **2 bits** (`[1:0]`) | Sub-word alignment for byte/halfword operations |
| **Read Hit Latency** | **1 Clock Cycle** | Combinational SRAM read (`dcache_stall = 0`) |
| **Write Hit Latency** | **1 Clock Cycle** | Simultaneous cache line update + Write-Through |
| **Read Miss Penalty** | **10 Clock Cycles** | 4-word burst refill FSM from backing memory |
| **Write Miss Policy** | **No-Write-Allocate (Write-Around)** | Bypasses cache directly to memory (1-cycle, 0 stall) |
| **Write Policy** | **Write-Through with Write Buffer** | Direct memory consistency without dirty bits or eviction writebacks |
| **Sub-word Strobes** | **Byte Write Enables** | Full hardware support for `SB` (1B), `SH` (2B), and `SW` (4B) |
| **Target FPGA** | **Xilinx Artix-7 XC7A100T** | Digilent Nexys A7-100T board |
| **Core Clock** | **50 MHz** ($T_{clk} = 20\text{ ns}$) | Standard system frequency |

---

## 32-Bit Address Decomposition

```text
31                            11 10            4 3           2 1           0
+-------------------------------+---------------+-------------+-------------+
|          TAG (21 bits)        | INDEX (7 bits)|  WO (2 bits)| BO (2 bits) |
+-------------------------------+---------------+-------------+-------------+
```
- **Byte Offset (`[1:0]`)**: Sub-word byte selection for `SB`, `SH`, `LB`, `LBU`, `LH`, `LHU`.
- **Word Offset (`[3:2]`)**: Selects 1 of 4 32-bit words inside the 16-byte block.
- **Index (`[10:4]`)**: Selects 1 of 128 cache lines.
- **Tag (`[31:11]`)**: Compared combinationally against stored tag for hit determination.

---

## Pipeline Integration & Hazard Interlock

The D-Cache controller coordinates directly with the centralized hazard unit (`hazard_unit.v`) to handle stalls with strict priority:

```text
+---------------------------------------------------------------------------------+
|                               PIPELINE PRIORITY                                 |
| 1. D-Cache Miss (MEM stage): Freezes PC, IF/ID, ID/EX, EX/MEM; Flushes MEM/WB.  |
| 2. Math Busy (EX stage DIV / FPU): Freezes PC, IF/ID, ID/EX; Flushes EX/MEM.    |
| 3. Load-Use Hazard (ID stage): Freezes PC, IF/ID; Flushes ID/EX.                |
| 4. Branch / Jump Flush (EX stage): Flushes IF/ID, ID/EX.                        |
+---------------------------------------------------------------------------------+
```

### Non-Cached MMIO Bypass:
- Memory accesses to `0x8000_0000` (UART TX and Status) bypass the L1 D-Cache entirely (`dcache_cpu_we = dmem_we && !is_mmio`).
- This guarantees that diagnostic UART writes and peripheral status reads never pollute cache lines or distort hit/miss metrics.

---

## Directory Organization

```
feature_5/
├── modules/
│   ├── opcode.vh                       # RISC-V RV32I/M/F opcodes and control constants
│   ├── hazard_unit.v                   # Stall & forwarding unit with D-Cache & math interlocks
│   ├── fpga/
│   │   ├── fpga_top_feature5.v         # Dedicated synthesizable FPGA wrapper for Nexys A7
│   │   └── seven_seg_controller.v     # 8-digit multiplexed 7-segment display driver
│   ├── pipeline/
│   │   ├── pipe.v                      # Backward-compatible register abstraction
│   │   └── pipeline_5stage.v           # 5-Stage RV32IMF processor core with L1 D-Cache
│   ├── registers/
│   │   ├── if_id_reg.v                 # IF/ID pipeline register
│   │   ├── id_ex_reg.v                 # ID/EX pipeline register
│   │   ├── ex_mem_reg.v                # EX/MEM pipeline register
│   │   └── mem_wb_reg.v                # MEM/WB pipeline register with flush bubble support
│   ├── stages/
│   │   ├── decode_stage.v              # Decoder for RV32I, RV32M, RV32F & register file
│   │   ├── execute_stage.v             # EX stage with ALU, Multiplier, Divider & FPU
│   │   ├── dcache_controller.v         # 2 KB Direct-Mapped L1 D-Cache Controller FSM
│   │   ├── divider_unit.v              # RV32M Radix-2 hardware divider (32 cycles)
│   │   ├── multiplier_unit.v           # RV32M unified hardware multiplier
│   │   ├── multiplier_dsp.v            # DSP48E1 single-cycle multiplier
│   │   ├── booth_radix4_multiplier.v   # Modified Booth Radix-4 multiplier
│   │   ├── fpu_single_core.v           # IEEE 754-2008 single-precision FPU core
│   │   ├── memory_stage.v              # Store formatting and byte write strobes
│   │   ├── memory.v                    # Backing dual BRAM models (IMEM & DMEM)
│   │   └── writeback_stage.v           # Load data extension & writeback mux
│   └── uart/
│       ├── uart_tx.v                   # 115200 baud UART transmitter
│       └── uart_unit.v                 # MMIO UART subsystem + boot banner + telemetry
├── testbench/
│   ├── tb_dcache.v                     # Standalone D-Cache unit testbench (18 assertions)
│   ├── tb_feature5_pipeline.v          # 5-stage pipeline integration testbench
│   ├── tb_pipeline_base.v              # Base integer testbench
│   └── tb_uart.v                       # MMIO UART testbench
├── simulation/
│   ├── filelist.txt                    # Simulation source list
│   ├── Makefile                        # Vivado xsim compile & test flow
│   └── run_simulation.bat              # Batch simulation runner
├── constraints/
│   └── nexys_a7_100t.xdc               # Physical constraints for Nexys A7-100T (50 MHz)
├── mem/
│   ├── imem.hex                        # Instruction memory hex
│   └── dmem.hex                        # Data memory hex
├── create_vivado_project.tcl           # Automated Vivado project creation script
├── build_bitstream.tcl                 # Headless bitstream build script
├── open_vivado.bat                     # Vivado project launcher
├── run_pipeline_trace.py               # Cycle-by-cycle terminal visualizer
└── README.md
```

---

## Nexys A7 FPGA Peripheral Mapping

| Peripheral | Pin | Description |
|:---|:---:|:---|
| **LED[0]** | `H17` | Hazard Stall (active during load-use, DIV, FPU, or D-Cache miss) |
| **LED[1]** | `K15` | Forwarding Active into EX operands |
| **LED[2]** | `J13` | Branch / Jump Flush Active |
| **LED[3]** | `N14` | Writeback Commit Active (`wb_reg_write`) |
| **LED[4]** | `R18` | Multiplier Active Indicator (`mul_active`) |
| **LED[5]** | `V17` | Divider Active Indicator (`div_active`) |
| **LED[6]** | `U17` | FPU Active Indicator (`fpu_active`) |
| **LED[7]** | `U16` | Program Execution Complete (`prog_done`) |
| **LED[8]** | `V16` | **L1 D-Cache Hit Indicator (pulse-stretched green LED)** |
| **LED[9]** | `T15` | **L1 D-Cache Miss Indicator (pulse-stretched red LED)** |
| **LED[15:10]** | `V11..U14`| Low bits of committed writeback result |
| **7-Segment Display** | `J17..L18`| Current Fetch PC (`sw[2]=0`) or Instruction Code (`sw[2]=1`) |
| **sw[0]** | `J15` | Single-Step Clock Mode (`1` = manual step via `btnc`) |
| **sw[1]** | `L16` | Slow Clock Mode (1 Hz) |
| **sw[2]** | `M13` | 7-Segment Display Mode (`0` = PC, `1` = Instruction) |
| **sw[3]** | `R15` | Multiplier Select (`0` = DSP48E1, `1` = Booth Radix-4) |
| **btnc** | `N17` | Manual Clock Step Pulse |
| **cpu_resetn** | `C12` | Active-Low Asynchronous Reset |
| **uart_tx** | `D4` | 115200 Baud Serial Telemetry output |

---

## Verification & Test Results

### 1. D-Cache Unit Verification (`tb_dcache.v`)
- Total Assertions: **18**
- **Results: 18 / 18 Passed (100% Pass Rate)**
- Verified Scenarios:
  - Cold compulsory load miss at `0x100` (exact 10-cycle burst refill stall)
  - Immediate re-hit on same address (1-cycle hit, zero stall)
  - Spatial locality hits across words 1, 2, 3 in the same 16-byte block
  - Store hit (`SW`) with write-through updating backing memory + 1 cycle latency
  - Read back updated store data from cache line
  - Store miss with No-Write-Allocate / write-around (1 cycle, zero stall)
  - Sub-word byte/halfword stores (`SB`, `SH`) with write strobes
  - Conflict miss and line eviction at `0x900`
  - Re-access of evicted line
  - Hardware reset clearing all valid bits

### 2. 5-Stage Pipeline Verification (`tb_feature5_pipeline.v`)
- Total Integration Checks: **11**
- **Results: 11 / 11 Passed (100% Pass Rate)**
- Verified Behaviors:
  - Cold load miss stalls the pipeline for 10 cycles, freezing PC and IF/ID
  - Sequential array reads hit in cache with zero stall cycles (75% spatial locality)
  - Store hit updates cache line and propagates to backing memory
  - Store miss writes directly to backing memory without stall
  - MMIO character writes (`0x8000_0000`) bypass D-Cache directly to UART

### 3. Base Integer Core (`tb_pipeline_base.v`)
- **Results: 5 / 5 Passed (100% Pass Rate)**

### 4. UART Telemetry (`tb_uart.v`)
- **Results: 100% Pass Rate**

---

## How to Build & Simulate

### 1. Run Simulation Suite in Terminal
```cmd
cd feature_5\simulation
run_simulation.bat
```
Or with Vivado xsim:
```cmd
xvlog -i ../modules -f filelist.txt ../testbench/tb_feature5_pipeline.v
xelab tb_feature5_pipeline -s snap_tb_feature5 -timescale 1ns/1ps
xsim snap_tb_feature5 -R
```

### 2. Open Standalone Vivado Project
```cmd
feature_5\open_vivado.bat
```
Project is located at `feature_5/vivado_project/rv32imf_dcache_fpga.xpr`.

### 3. Headless Bitstream Generation
```cmd
vivado -mode batch -source feature_5/build_bitstream.tcl -nojournal -nolog
```
