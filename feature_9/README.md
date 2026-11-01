# Feature 9: Comprehensive RISC-V Zbb Bit-Manipulation Extension

## 1. Overview
This subsystem integrates the complete **RISC-V Zbb Bit-Manipulation Extension (18 target instructions)** into the 5-Stage RV32IMF Pipelined Processor Core. All 18 instructions execute with **strictly 1-cycle latency in the Execute (EX) stage** and introduce **0 pipeline stall cycles**, flowing through the pipeline identically to base arithmetic instructions (`add`/`xor`).

The implementation is verified via both simulation and hardware UART telemetry at 115,200 Baud on the **Digilent Nexys A7-100T FPGA** (Artix-7 XC7A100T-1CSG324C).

---

## 2. Supported Zbb Instructions (All 18 Implemented)

| Category | Instruction | Opcode | Funct3 | Funct7 / Imm12 | Operation | EX Latency | Pipeline Stalls |
| :--- | :--- | :--- | :--- | :--- | :--- | :---: | :---: |
| **Logical with Negate** | `andn` | `0110011` | `111` | `0100000` | `rd = rs1 & ~rs2` | 1 Cycle | 0 |
| | `orn` | `0110011` | `110` | `0100000` | `rd = rs1 \| ~rs2` | 1 Cycle | 0 |
| | `xnor` | `0110011` | `100` | `0100000` | `rd = ~(rs1 ^ rs2)` | 1 Cycle | 0 |
| **Min / Max** | `max` | `0110011` | `110` | `0000101` | `rd = ($signed(rs1) > $signed(rs2)) ? rs1 : rs2` | 1 Cycle | 0 |
| | `maxu` | `0110011` | `111` | `0000101` | `rd = (rs1 > rs2) ? rs1 : rs2` | 1 Cycle | 0 |
| | `min` | `0110011` | `100` | `0000101` | `rd = ($signed(rs1) < $signed(rs2)) ? rs1 : rs2` | 1 Cycle | 0 |
| | `minu` | `0110011` | `101` | `0000101` | `rd = (rs1 < rs2) ? rs1 : rs2` | 1 Cycle | 0 |
| **Extensions** | `zext.h` | `0110011` | `100` | `0000100` | `rd = {16'h0000, rs1[15:0]}` | 1 Cycle | 0 |
| | `sext.h` | `0010011` | `001` | `12'h605` | `rd = {{16{rs1[15]}}, rs1[15:0]}` | 1 Cycle | 0 |
| | `sext.b` | `0010011` | `001` | `12'h604` | `rd = {{24{rs1[7]}}, rs1[7:0]}` | 1 Cycle | 0 |
| **Counting** | `clz` | `0010011` | `001` | `12'h600` | Count leading zeros in `rs1` (0..32) | 1 Cycle | 0 |
| | `ctz` | `0010011` | `001` | `12'h601` | Count trailing zeros in `rs1` (0..32) | 1 Cycle | 0 |
| | `cpop` | `0010011` | `001` | `12'h602` | Count 1-bits (population count) in `rs1` | 1 Cycle | 0 |
| **Rotations** | `rol` | `0110011` | `001` | `0110000` | Circular left rotate `rs1` by `rs2[4:0]` | 1 Cycle | 0 |
| | `ror` | `0110011` | `101` | `0110000` | Circular right rotate `rs1` by `rs2[4:0]` | 1 Cycle | 0 |
| | `rori` | `0010011` | `101` | `0110000` | Circular right rotate `rs1` by `shamt[4:0]` | 1 Cycle | 0 |
| **Byte Ops** | `rev8` | `0010011` | `101` | `12'h698` | Endianness byte swap: `{b0, b1, b2, b3}` | 1 Cycle | 0 |
| | `orc.b` | `0010011` | `101` | `12'h287` | Byte-wise OR-combine: `(byte != 0) ? 0xFF : 0x00` | 1 Cycle | 0 |

---

## 3. FPGA Implementation Details
- **Target Device:** Digilent Nexys A7-100T (Xilinx Artix-7 XC7A100T-1CSG324C).
- **Primary Oscillator:** 100 MHz (Pin E3).
- **Core Clock:** 50 MHz (generated via divide-by-2 toggle register `clk_50mhz_reg`).
- **UART Baud Rate:** 115,200 Baud, 8N1 (Baud divider from 50 MHz = $50{,}000{,}000 / 115{,}200 = 434$).
- **FPGA Resource Strategy:** All 18 Zbb operations are synthesized into standard LUT logic, priority encoders, and multiplexers with **zero DSP slice consumption**, eliminating DSP resource pressure.

---

## 4. Test Program & Expected UART Output
The deterministic 23-instruction sequence is executed from `0x00000000` to `0x00000058`. The processor captures each writeback value into a telemetry trace buffer, halts when `nop` at `0x00000058` completes the Writeback stage, and streams the formatted trace table over UART:

```
===== ZBB EXHAUSTIVE VERIFICATION =====
PC          INSTR                WB REGISTER   CALCULATED VALUE
0x00000000  addi x1, x0, -2      x1            0xFFFFFFFE
0x00000004  addi x2, x0, 5       x2            0x00000005
0x00000008  andn x3, x2, x1      x3            0x00000001
0x0000000C  orn  x4, x2, x1      x4            0x00000005
0x00000010  xnor x5, x2, x1      x5            0x00000004
0x00000014  max  x6, x1, x2      x6            0x00000005
0x00000018  maxu x7, x1, x2      x7            0xFFFFFFFE
0x0000001C  min  x8, x1, x2      x8            0xFFFFFFFE
0x00000020  minu x9, x1, x2      x9            0x00000005
0x00000024  addi x10, x0, -1     x10           0xFFFFFFFF
0x00000028  zext.h x11, x10      x11           0x0000FFFF
0x0000002C  sext.h x12, x10      x12           0xFFFFFFFF
0x00000030  sext.b x13, x10      x13           0xFFFFFFFF
0x00000034  addi x14, x0, 0x0F0  x14           0x000000F0
0x00000038  clz  x15, x14        x15           0x00000018
0x0000003C  ctz  x16, x14        x16           0x00000004
0x00000040  cpop x17, x14        x17           0x00000004
0x00000044  rol  x18, x14, x2    x18           0x00001E00
0x00000048  ror  x19, x14, x2    x19           0x80000007
0x0000004C  rori x20, x14, 4     x20           0x0000000F
0x00000050  rev8 x21, x14        x21           0xF0000000
0x00000054  orc.b x22, x14       x22           0x000000FF

===== VERIFICATION SUMMARY =====
Total Zbb instructions executed: 18
Timing Violation Detected      : NO (All executed in 1 cycle)
```

---

## 5. Verification Commands

### Run Simulations (Vivado Simulator)
```powershell
# 1. Direct Execution Unit Tests (All 18 operations)
xvlog -i feature_9/modules -i feature_9/modules/stages -i feature_9/modules/registers -i feature_9/modules/pipeline -i feature_9/modules/fpga -i feature_9/modules/uart feature_9/modules/stages/multiplier_unit.v feature_9/modules/stages/multiplier_dsp.v feature_9/modules/stages/booth_radix4_multiplier.v feature_9/modules/stages/divider_unit.v feature_9/modules/stages/fpu_single_core.v feature_9/modules/stages/execute_stage.v feature_9/testbench/tb_zbb_unit.v
xelab -top tb_zbb_unit -snapshot tb_zbb_unit_snap -R

# 2. 5-Stage Pipeline Cycle-Accurate Verification
xvlog -i feature_9/modules -i feature_9/modules/stages -i feature_9/modules/registers -i feature_9/modules/pipeline -i feature_9/modules/fpga -i feature_9/modules/uart feature_9/testbench/tb_feature9_pipeline.v
xelab -top tb_feature9_pipeline -snapshot tb_feature9_pipeline_snap -R

# 3. Board-Level UART Stream Verification
xvlog -i feature_9/modules -i feature_9/modules/stages -i feature_9/modules/registers -i feature_9/modules/pipeline -i feature_9/modules/fpga -i feature_9/modules/uart feature_9/modules/fpga/fpga_top_feature9.v
xelab -top tb_fpga_top_feature9 -snapshot tb_fpga_top_feature9_snap -R
```

### Build FPGA Bitstream
```powershell
vivado -mode batch -source feature_9/build_bitstream.tcl
```

### Program FPGA
```powershell
vivado -mode batch -source feature_9/program_fpga.tcl
```

### Monitor UART Output
```powershell
powershell -ExecutionPolicy Bypass -File feature_9/read_uart.ps1 -Port COM5 -Baud 115200
```
