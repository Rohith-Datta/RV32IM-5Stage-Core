# Feature 6: L1 Instruction Cache (L1 I-Cache)

## 1. Objectives & Scope
Integration of a high-speed, direct-mapped **L1 Instruction Cache (2 KB)** placed between the Fetch (IF) stage and background instruction memory (IMEM). The primary objective is to supply 32-bit machine instruction words to the decode stage with single-cycle hit latency at 50 MHz, drastically reducing memory bus contention.

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
           | TAG SRAM (128 x 22b)  |                      | DATA SRAM (128 x 128b)|
           |  [Valid bit + Tag]    |                      | (16 Bytes / 4 Insts)  |
           +-----------------------+                      +-----------------------+
                       |                                              |
                       v                                              v
           +-----------------------+                      +-----------------------+
           | Tag Comparator & Hit  |                      | Inst Select Mux [3:2] |
           +-----------------------+                      +-----------------------+
                       |                                              |
                       +---------------> HIT / MISS <-----------------+
```

### Cache Geometry & Parameterization:
- **Cache Organization**: Direct-Mapped Instruction Cache (Read-Only)
- **Total Capacity**: **2 KB** (2,048 Bytes)
- **Line / Block Size**: **16 Bytes** (4 instructions $\times$ 32 bits per cache block)
- **Number of Cache Lines**: **128 lines** ($2048 / 16 = 128 = 2^7$)
- **Address Breakdown (32-bit byte address)**:
  - **Byte Offset (`addr[3:0]`)**: 4 bits (selects instruction word via `addr[3:2]`, with `addr[1:0] == 2'b00`)
  - **Index (`addr[10:4]`)**: 7 bits (indexes one of the 128 cache lines)
  - **Tag (`addr[31:11]`)**: 21 bits (compared against tag SRAM entry)
- **SRAM Storage Requirements**:
  - Instruction Data RAM: $128 \text{ lines} \times 128 \text{ bits} = 16,384 \text{ bits}$ (half a 36Kb Xilinx Block RAM block)
  - Tag & Valid RAM: $128 \text{ lines} \times (21\text{-bit Tag} + 1\text{-bit Valid}) = 2,816 \text{ bits}$

---

## 3. Cache Controller & Miss FSM

```
                  +----------------------------------------------+
                  |                     IDLE                     |
                  |  - Compare Tag & Valid bit on Fetch PC       |
                  +----------------------------------------------+
                            |                           ^
                 Fetch Miss |                           | Refill Complete
                            v                           |
                  +-------------------+       +-------------------+
                  |   REFILL_REQ      | ----> |   BURST_REFILL    |
                  | Assert imem_read  |       | Transfer 4 insts  |
                  | to background ROM |       | from BRAM/Flash   |
                  +-------------------+       +-------------------+
```

1. **Hit Operation (1-Cycle Latency)**:
   - On every clock cycle where IF is active (`!stall_if`):
     - Indexed line tag and valid bit read synchronously.
     - If `valid == 1` and `tag_match == 1`: **Cache Hit** (`icache_hit = 1`).
     - Requested instruction extracted from cache line and fed directly into `IF/ID` register.

2. **Miss Handling & Pipeline Stall (`icache_stall`)**:
   - On a fetch miss (`!icache_hit`):
     - Asserts `icache_stall = 1` directly to the `hazard_unit`.
     - Hazard unit freezes PC (`stall_if = 1`) and inserts a NOP bubble into `IF/ID` (`flush_if_id = 1`).
     - Controller initiates a 4-word burst refill from background instruction memory.
     - Upon refill completion, line is written to SRAM, `valid` bit set, and stalled instruction is latched.

---

## 4. Signal Interface

| Port Name | Direction | Width | Description |
|---|:---:|:---:|---|
| `clk` | Input | 1 bit | 50 MHz synchronous core clock |
| `reset_n` | Input | 1 bit | Active-low synchronous reset (invalidates all lines) |
| **CPU IF Interface** | | | |
| `fetch_pc` | Input | 32 bits | Program Counter from IF stage (`pc_if`) |
| `fetch_inst` | Output | 32 bits | Fetched machine instruction to IF/ID register |
| `icache_stall` | Output | 1 bit | Hold request asserted during miss burst refill |
| `icache_hit` | Output | 1 bit | High when current PC hits in cache |
| **Main Instruction Memory Interface** | | | |
| `imem_baddr` | Output | 32 bits | 16-byte block-aligned address for burst refill |
| `imem_brdata` | Input | 128 bits | 16-byte burst instruction line from background ROM/Flash |
| `imem_req` | Output | 1 bit | Instruction line read request strobe |
| `imem_ready` | Input | 1 bit | Main memory acknowledge signal |
