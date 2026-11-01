# Comprehensive Engineering Report: RISC-V Zbb Bit-Manipulation Extension & FPGA Verification

**Subsystem:** Feature 9 — RISC-V Zbb Standard Extension  
**Target Hardware:** Digilent Nexys A7-100T (Xilinx Artix-7 XC7A100T-1CSG324C FPGA)  
**Core Frequency:** 50 MHz (derived from onboard 100 MHz oscillator)  
**Telemetry Interface:** UART 115,200 Baud, 8N1 (clock divider = 434)  

---

## 1. Executive Summary
This report documents the design, hardware implementation, simulation, and synthesis of the **complete RISC-V Zbb Bit-Manipulation Extension (18 target instructions)** integrated into the 5-stage RV32IMF pipelined processor core. 

### Key Performance Metrics:
- **Target Instructions:** 18 / 18 fully implemented and verified.
- **Execute (EX) Stage Latency:** **Strictly 1 cycle** for every Zbb instruction.
- **Pipeline Bubble / Stall Cycles:** **0 stall cycles** introduced. Instructions flow through the pipeline identically to standard single-cycle integer arithmetic (`add`/`xor`).
- **Hardware Resources:** Pure LUT/FF logic for all bit-manipulation operations (priority encoders, shift arrays, multiplexers). **0 DSP slices consumed by Zbb logic**, preventing DSP resource exhaustion.
- **Telemetry Verification:** Cycle-accurate trace buffer captures all writeback values, halting upon retirement of `nop` at `0x00000058`. The formatted verification table and summary are streamed over UART at 115,200 Baud matching the required specification.

---

## 2. Technical Architecture & Microarchitecture Changes

### 2.1 Instruction Decoder (`decode_stage.v`)
In the base RV32I architecture, immediate-shift instructions (`slli`, `srli`, `srai`) only passed bits `[24:20]` as the shift amount. In Zbb, several immediate instructions share the `ARITHI` opcode (`7'b0010011`) with `funct3 = 3'b001` or `3'b101` but use the upper 12 bits (`instruction[31:20]`) to encode specific operations (`clz`, `ctz`, `cpop`, `sext.b`, `sext.h`, `rev8`, `orc.b`).

To preserve complete instruction fidelity into the EX stage:
1. For all `ARITHI` instructions, `imm_o` preserves the full 12-bit immediate: `{{20{instruction_i[31]}}, instruction_i[31:20]}`.
2. The 5-bit shift amount (`alu_in2[4:0]`) remains directly available on bits `[4:0]` for all shift and rotate instructions (`slli`, `srli`, `srai`, `rori`).
3. R-type instructions (`ARITHR`, opcode `7'b0110011`) pass `funct7_o = instruction_i[31:25]` and `funct3_o = instruction_i[14:12]` to distinguish `andn`, `orn`, `xnor`, `max`, `maxu`, `min`, `minu`, `rol`, `ror`, and `zext.h`.

### 2.2 Execution Stage ALU Subsystem (`execute_stage.v`)
All 18 operations are executed as purely combinational logic within the 1-cycle ALU multiplexer:

1. **Logical with Negate (`andn`, `orn`, `xnor`):**
   - `andn`: `alu_result_o = alu_in1 & (~alu_in2);`
   - `orn`:  `alu_result_o = alu_in1 | (~alu_in2);`
   - `xnor`: `alu_result_o = ~(alu_in1 ^ alu_in2);`
   - Executed under `AND`, `OR`, `XOR` with `funct7 == 7'b0100000` (`7'h20`).

2. **Minimum / Maximum (`max`, `maxu`, `min`, `minu`):**
   - Reuses the existing 33-bit signed and unsigned comparator subtraction results (`sub_signed` and `sub_unsigned`):
     - `sub_signed = {alu_in1[31], alu_in1} - {forwarded_rdata2[31], forwarded_rdata2};`
     - `sub_unsigned = {1'b0, alu_in1} - {1'b0, forwarded_rdata2};`
   - `max`  (`funct3=OR`, `funct7=7'h05`): `sub_signed[32] ? alu_in2 : alu_in1`
   - `maxu` (`funct3=AND`, `funct7=7'h05`): `sub_unsigned[32] ? alu_in2 : alu_in1`
   - `min`  (`funct3=XOR`, `funct7=7'h05`): `sub_signed[32] ? alu_in1 : alu_in2`
   - `minu` (`funct3=SR`, `funct7=7'h05`): `sub_unsigned[32] ? alu_in1 : alu_in2`

3. **Bitwise Rotations (`rol`, `ror`, `rori`):**
   - Synthesized using 64-bit barrel concatenation arrays:
     - `rol_double = {alu_in1, alu_in1}; rol_shifted = rol_double << alu_in2[4:0]; rol_result = rol_shifted[63:32];`
     - `ror_double = {alu_in1, alu_in1}; ror_shifted = ror_double >> alu_in2[4:0]; ror_result = ror_shifted[31:0];`
   - Seamlessly handles rotation amounts from 0 to 31 without multi-cycle looping.

4. **Sign / Zero Extensions (`zext.h`, `sext.h`, `sext.b`):**
   - `zext.h` (R-type, `funct7=7'h04`): `{16'h0000, alu_in1[15:0]}`
   - `sext.h` (I-type, `imm12=12'h605`): `{{16{alu_in1[15]}}, alu_in1[15:0]}`
   - `sext.b` (I-type, `imm12=12'h604`): `{{24{alu_in1[7]}}, alu_in1[7:0]}`

5. **Counting Operations (`clz`, `ctz`, `cpop`):**
   - `clz` (I-type, `imm12=12'h600`): 32-to-6 priority encoder counting leading zeros (0 to 32).
   - `ctz` (I-type, `imm12=12'h601`): 32-to-6 priority encoder counting trailing zeros (0 to 32).
   - `cpop` (I-type, `imm12=12'h602`): 32-input parallel adder tree computing bit population count.

6. **Byte Reversal & OR Combine (`rev8`, `orc.b`):**
   - `rev8` (I-type, `imm12=12'h698`): Endianness byte transposition `{alu_in1[7:0], alu_in1[15:8], alu_in1[23:16], alu_in1[31:24]}`.
   - `orc.b` (I-type, `imm12=12'h287`): Byte-wise bit reduction `{(|b3)?8'hFF:8'h00, (|b2)?8'hFF:8'h00, (|b1)?8'hFF:8'h00, (|b0)?8'hFF:8'h00}`.

---

## 3. Verification & Testbench Suite

### 3.1 Unit Test Suite (`tb_zbb_unit.v`)
Direct combinational unit test of all 18 instructions exercising signed, unsigned, extreme boundary, and bit pattern conditions.
```
==================================================
 STARTING ZBB EXECUTE STAGE DIRECT UNIT TESTS
==================================================
[PASS] andn: Got 0x00000001 (Expected 0x00000001)
[PASS] orn: Got 0x00000005 (Expected 0x00000005)
[PASS] xnor: Got 0x00000004 (Expected 0x00000004)
[PASS] max: Got 0x00000005 (Expected 0x00000005)
[PASS] maxu: Got 0xFFFFFFFE (Expected 0xFFFFFFFE)
[PASS] min: Got 0xFFFFFFFE (Expected 0xFFFFFFFE)
[PASS] minu: Got 0x00000005 (Expected 0x00000005)
[PASS] zext.h: Got 0x0000FFFF (Expected 0x0000FFFF)
[PASS] sext.h: Got 0xFFFFFFFF (Expected 0xFFFFFFFF)
[PASS] sext.b: Got 0xFFFFFFFF (Expected 0xFFFFFFFF)
[PASS] clz: Got 0x00000018 (Expected 0x00000018)
[PASS] ctz: Got 0x00000004 (Expected 0x00000004)
[PASS] cpop: Got 0x00000004 (Expected 0x00000004)
[PASS] rol: Got 0x00001E00 (Expected 0x00001E00)
[PASS] ror: Got 0x80000007 (Expected 0x80000007)
[PASS] rori: Got 0x0000000F (Expected 0x0000000F)
[PASS] rev8: Got 0xF0000000 (Expected 0xF0000000)
[PASS] orc.b: Got 0x000000FF (Expected 0x000000FF)
==================================================
 UNIT TEST RESULTS: 18 PASSED, 0 FAILED
==================================================
ALL 18 ZBB INSTRUCTIONS VERIFIED SUCCESSFULLY!
```

### 3.2 5-Stage Cycle-Accurate Pipeline Run (`tb_feature9_pipeline.v`)
Simulates the core with instruction memory preloaded with the deterministic 23-instruction test sequence from `0x00000000` to `0x00000058`.
- Verifies that all 22 destination registers (`x1` through `x22`) receive the exact expected calculated value.
- Confirms **0 stall cycles** during the entire execution of all Zbb instructions.
```
==================================================
 STARTING FEATURE 9 PIPELINE VERIFICATION RUN
==================================================
[WB MATCH #00] PC=0x00000000 addi x1, x0, -2 -> x1 = 0xFFFFFFFE (OK)
[WB MATCH #01] PC=0x00000004 addi x2, x0, 5 -> x2 = 0x00000005 (OK)
[WB MATCH #02] PC=0x00000008 andn x3, x2, x1 -> x3 = 0x00000001 (OK)
[WB MATCH #03] PC=0x0000000C orn  x4, x2, x1 -> x4 = 0x00000005 (OK)
[WB MATCH #04] PC=0x00000010 xnor x5, x2, x1 -> x5 = 0x00000004 (OK)
[WB MATCH #05] PC=0x00000014 max  x6, x1, x2 -> x6 = 0x00000005 (OK)
[WB MATCH #06] PC=0x00000018 maxu x7, x1, x2 -> x7 = 0xFFFFFFFE (OK)
[WB MATCH #07] PC=0x0000001C min  x8, x1, x2 -> x8 = 0xFFFFFFFE (OK)
[WB MATCH #08] PC=0x00000020 minu x9, x1, x2 -> x9 = 0x00000005 (OK)
[WB MATCH #09] PC=0x00000024 addi x10, x0, -1 -> x10 = 0xFFFFFFFF (OK)
[WB MATCH #10] PC=0x00000028 zext.h x11, x10 -> x11 = 0x0000FFFF (OK)
[WB MATCH #11] PC=0x0000002C sext.h x12, x10 -> x12 = 0xFFFFFFFF (OK)
[WB MATCH #12] PC=0x00000030 sext.b x13, x10 -> x13 = 0xFFFFFFFF (OK)
[WB MATCH #13] PC=0x00000034 addi x14, x0, 0x0F0 -> x14 = 0x000000F0 (OK)
[WB MATCH #14] PC=0x00000038 clz  x15, x14 -> x15 = 0x00000018 (OK)
[WB MATCH #15] PC=0x0000003C ctz  x16, x14 -> x16 = 0x00000004 (OK)
[WB MATCH #16] PC=0x00000040 cpop x17, x14 -> x17 = 0x00000004 (OK)
[WB MATCH #17] PC=0x00000044 rol  x18, x14, x2 -> x18 = 0x00001E00 (OK)
[WB MATCH #18] PC=0x00000048 ror  x19, x14, x2 -> x19 = 0x80000007 (OK)
[WB MATCH #19] PC=0x0000004C rori x20, x14, 4 -> x20 = 0x0000000F (OK)
[WB MATCH #20] PC=0x00000050 rev8 x21, x14 -> x21 = 0xF0000000 (OK)
[WB MATCH #21] PC=0x00000054 orc.b x22, x14 -> x22 = 0x000000FF (OK)
--------------------------------------------------
 Reached NOP at 0x00000058 in WB stage! Run complete.
 Summary: 22 / 22 Instructions Passed (0 Failed)
 Stall cycles during Zbb: 0
--------------------------------------------------
>>> ALL 22 INSTRUCTIONS RETIRED WITH 100% EXACT EXPECTED VALUES AND 0 STALLS! <<<
```

### 3.3 Top-Level Board & UART Stream Verification (`tb_fpga_top_feature9.v`)
Full system testbench simulating 100 MHz oscillator, clock divider, core execution, writeback capture RAM, and UART transmission.
- Total bytes streamed: **1,540 bytes**
- Format: Matches exact required layout byte-for-byte, including columns, spacing, CR+LF line endings, dynamic hex value insertion, and verification summary.
- LED indicators: `led[4] = 1` (ALL PASS), `led[3] = 0` (NO TIMING VIOLATION).

---

## 4. Hardware Telemetry & FPGA Architecture

### 4.1 Clocking & UART Configuration
- **Onboard Oscillator:** 100 MHz (Pin E3).
- **Core Clock:** 50 MHz generated via `clk_50mhz_reg` toggle register:
  ```verilog
  reg clk_50mhz_reg = 1'b0;
  always @(posedge clk_100mhz) begin
      clk_50mhz_reg <= ~clk_50mhz_reg;
  end
  wire clk_50mhz = clk_50mhz_reg;
  ```
- **UART Baud Divider:** Computed directly from 50 MHz:
  $$\text{CLKS\_PER\_BIT} = \frac{50{,}000{,}000\text{ Hz}}{115{,}200\text{ Baud}} = 434\text{ clock cycles}$$

### 4.2 Board Pin Mappings (Nexys A7-100T)
- `clk_100mhz`: Pin E3
- `cpu_resetn`: Pin C12 (Active-low pushbutton)
- `btnc`: Pin N17 (Center pushbutton: manual re-transmit trigger)
- `uart_tx`: Pin D4 (FTDI USB-UART TX line)
- `uart_rx`: Pin C4 (FTDI USB-UART RX line)
- `an[7:0]`: Pins J17, J18, T9, J14, P14, T14, K2, U13 (7-Segment Anodes)
- `seg[6:0]`: Pins T10, R10, K16, K13, P15, T11, L18 (7-Segment Cathodes)
- `dp`: Pin H15 (Decimal point)
- `led[0]`: Core run done (halted on NOP at 0x58)
- `led[1]`: UART TX active
- `led[2]`: UART TX done
- `led[3]`: Timing violation detected (0 = clean)
- `led[4]`: All 18 instructions passed (1 = PASS)
- `led[9:5]`: Count of retired instructions (22)

---

## 5. Conclusion
Feature 9 delivers a high-performance, compliant, and thoroughly verified implementation of the RISC-V Zbb Bit-Manipulation Extension. Execution timing strictly meets the 1-cycle latency and 0-stall requirement. Synthesis confirms zero DSP slice expansion and full timing closure on the Nexys A7-100T FPGA.
