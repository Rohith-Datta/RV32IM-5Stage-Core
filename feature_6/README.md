# Feature 6: Pipelined RV32IMF Processor Core with L1 Instruction Cache

## 1. Overview & Architectural Scope
Feature 6 integrates a high-performance **2 KB Direct-Mapped L1 Instruction Cache (L1 I-Cache)** into the 5-stage pipelined RV32IMF processor core. Data memory (DMEM) uses direct memory access without a D-Cache (per modular development flow; unified caching integration is reserved for the final system integration phase). All operations run synchronously at the standard **50 MHz system clock**.

---

## 2. Microarchitecture Specifications

```
                              +-----------------------------------------------+
                              |            Fetch Stage PC Address [31:0]      |
                              +-----------------------------------------------+
                                     |                |               |
                                [31:11] (21b)    [10:4] (7b)     [3:0] (4b)
                                     |                |               |
                                     v                v               v
                               +-----------+    +-----------+   +-----------+
                               |    TAG    |    |   INDEX   |   |BYTE OFFSET|
                               +-----------+    +-----------+   +-----------+
                                     |                |
                       +-------------+                +---------------+
                       |                                              |
                       v                                              v
           +-----------------------+                      +-----------------------+
           | TAG SRAM (128 x 21b)  |                      | DATA SRAM (4 banks)   |
           | Valid bit (128 x 1b)  |                      | (128 lines x 4 words) |
           +-----------------------+                      +-----------------------+
                       |                                              |
                       v                                              v
           +-----------------------+                      +-----------------------+
           | Tag Comparator & Hit  |                      | Word Select Mux [3:2] |
           +-----------------------+                      +-----------------------+
                       |                                              |
                       +---------------> HIT / MISS <-----------------+
```

### L1 I-Cache Geometry & Parameterization:
- **Organization**: Direct-Mapped Instruction Cache (Read-Only)
- **Total Capacity**: **2 KB** (2,048 Bytes)
- **Cache Line / Block Size**: **16 Bytes** (4 words / 128 bits)
- **Number of Cache Lines**: **128 lines** ($2048 / 16 = 128 = 2^7$)
- **Hit Latency**: **1 cycle** (combinational read from SRAM banks, zero pipeline stall)
- **Miss Penalty**: **10 cycles** (4-word hardware burst refill from backing memory)
- **Address Breakdown (32-bit byte address)**:
  - **Byte Offset (`addr[1:0]`)**: 2 bits (ignored for 32-bit aligned instruction fetches)
  - **Word Offset (`addr[3:2]`)**: 2 bits (selects word 0, 1, 2, or 3 from the 16-byte line)
  - **Index (`addr[10:4]`)**: 7 bits (selects one of 128 cache lines)
  - **Tag (`addr[31:11]`)**: 21 bits (stored in tag array and compared against current PC)
- **Storage Implementation**:
  - 4 parallel RAM banks for line data (`data_mem0`, `data_mem1`, `data_mem2`, `data_mem3`), mapped to Block RAM / LUT RAM.
  - Tag storage array: 128 lines $\times$ 21 bits.
  - Valid storage array: 128 lines $\times$ 1 bit.
- **Hardware Flush Support**: Active-high `flush_i` resets the refill FSM immediately to `STATE_IDLE` upon branch/jump redirection in the EX stage, canceling orphaned fetches.
- **Cache Bypass Mode**: Active-high `cache_bypass_i` (`SW[1]`) bypasses cache line allocation for diagnostic latency analysis.

---

## 3. Centralized Multi-Level Hazard Prioritization

The hazard unit (`hazard_unit.v`) coordinates all stalls, flushes, and bypasses with strict priority:

1. **Multi-Cycle Math Busy (`div_busy || fpu_busy`)**:
   - 32-cycle hardware divider or multi-cycle floating-point unit active in EX stage.
   - Freezes PC, IF/ID, and ID/EX; injects bubble into EX/MEM.
2. **I-Cache Miss (`icache_stall`)**:
   - Occurs in IF stage during cold instruction fetch or conflict miss.
   - Freezes PC: `stall_if = 1`.
   - Outputs NOP (`0x0000_0013`) to `IF/ID`, allowing downstream stages to drain naturally.
   - If a branch/jump redirects in EX (`branch_or_jump_taken`), PC update takes precedence, and `flush_i` aborts the in-flight I-Cache refill.
3. **Load-Use Hazard (`load_use_hazard`)**:
   - 1-cycle interlock when ID stage needs data from a load currently in EX stage.
   - Freezes PC and IF/ID; injects bubble into ID/EX.
4. **Control Hazard (Branch / Jump Taken)**:
   - Flushes `IF/ID` and `ID/EX` (2-cycle branch penalty).

---

## 4. FPGA Nexys A7-100T Top-Level Configuration

### Board Clock & Reset:
- **`CLK100MHZ`**: Onboard 100 MHz crystal oscillator.
- **Core Clock**: Clock divider generates strict **50 MHz** ($T_{clk} = 20\text{ ns}$).
- **`CPU_RESETN`**: Active-low CPU reset push button (synchronized to 50 MHz).
- **`BTNC`**: Diagnostic performance counter reset button.

### Slide Switches (`SW[15:0]`):
- **`SW[0]`**: Pipeline Run Enable (`1` = normal execution, `0` = pipeline pause).
- **`SW[1]`**: I-Cache Bypass Mode (`0` = L1 I-Cache enabled, `1` = bypass cache).
- **`SW[2]`**: Multiplier Selection (`1` = DSP48E1 slices, `0` = Radix-4 Booth).
- **`SW[5:3]`**: 7-Segment Display Diagnostic Mode:
  - `3'b000`: Program Counter in Writeback stage (`pc_wb[15:0]`)
  - `3'b001`: Writeback Data (`wb_data[15:0]`)
  - `3'b010`: I-Cache Diagnostic Hit Counter (`icache_hit_count[15:0]`)
  - `3'b011`: I-Cache Diagnostic Miss Counter (`icache_miss_count[15:0]`)
  - `3'b100`: Fetched Instruction (`imem_rdata[15:0]`)
  - `3'b101`: Destination Register (`wb_dest_reg`)
  - `3'b110`: Math Busy Flags (`div_busy`, `fpu_busy`)
  - `3'b111`: Feature 6 Tag (`0x0006`)

### Diagnostic LEDs (`LED[15:0]`):
- **`LED[7:0]`**: Writeback PC word index.
- **`LED[8]`**: I-Cache Hit (pulse stretched for human visibility).
- **`LED[9]`**: I-Cache Miss (pulse stretched).
- **`LED[11:10]`**: Reserved for multi-cache integration.
- **`LED[12]`**: Multi-Cycle Math Busy (`div_busy || fpu_busy`).
- **`LED[13]`**: Pipeline Stall Active (`hazard_stall`).
- **`LED[14]`**: UART Transmitter Active.
- **`LED[15]`**: Heartbeat Blink Indicator (~1.5 Hz).

### Dedicated UART Telemetry Subsystem:
- **Baud Rate**: 115,200 baud (50 MHz clock / 434 clock divider).
- **Pin**: `UART_TXD_IN` (Nexys A7 USB-UART bridge pin `D4`).
- **Features**: Boot banner, real-time instruction telemetry, and non-cached MMIO writes (`0x8000_0000`).

---

## 5. Simulation & Verification Suite

All testbenches run at **50 MHz** ($T_{clk} = 20\text{ ns}$):

1. **`tb_icache.v` (Unit Verification)**:
   - 9 comprehensive tests: cold start compulsory miss, immediate re-hit, spatial locality same-line hits, adjacent line miss, conflict eviction, re-access evicted line, bypass mode, branch flush, and hardware reset.
2. **`tb_feature6_pipeline.v` (Full Pipeline Integration)**:
   - Verifies 2 KB L1 I-Cache with direct DMEM access: cold start miss stalls, spatial hit acceleration, multi-iteration loop temporal locality (0 fetch stalls), direct data load/store, UART MMIO, and program termination.
3. **`tb_pipeline_base.v` (Integer ALU Program)**:
   - Verifies RV32I base instructions, ALU forwarding paths, and pipeline interlocks with I-Cache enabled.
4. **`tb_uart.v` (UART Telemetry)**:
   - Verifies 50 MHz baud timing, FIFO queue management, boot banner serialization, and framing.

### Running Simulations:
```bash
cd feature_6/simulation
./run_simulation.bat
```
or via Make:
```bash
make all
```
