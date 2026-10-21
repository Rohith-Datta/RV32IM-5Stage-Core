# Feature 5: L1 Data Cache (L1 D-Cache)

## 1. Objectives & Scope
Integration of a high-speed, direct-mapped **L1 Data Cache (2 KB)** placed between the Memory (MEM) stage and background main memory (DMEM). The primary objective is to minimize average memory access time (AMAT) for data loads (`LB`, `LH`, `LW`, `LBU`, `LHU`) and stores (`SB`, `SH`, `SW`) by satisfying hits in a single clock cycle at 50 MHz.

---

## 2. Microarchitecture Specifications

```
                              +-----------------------------------------------+
                              |            MEM Stage Address [31:0]           |
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
           |  [Valid bit + Tag]    |                      | (16 Bytes / 4 Words)  |
           +-----------------------+                      +-----------------------+
                       |                                              |
                       v                                              v
           +-----------------------+                      +-----------------------+
           | Tag Comparator & Hit  |                      | Word Select Mux [3:2] |
           +-----------------------+                      +-----------------------+
                       |                                              |
                       +---------------> HIT / MISS <-----------------+
```

### Cache Geometry & Parameterization:
- **Cache Organization**: Direct-Mapped Data Cache
- **Total Capacity**: **2 KB** (2,048 Bytes)
- **Line / Block Size**: **16 Bytes** (4 words $\times$ 32 bits per cache block)
- **Number of Cache Lines**: **128 lines** ($2048 / 16 = 128 = 2^7$)
- **Address Breakdown (32-bit byte address)**:
  - **Byte Offset (`addr[3:0]`)**: 4 bits (selects byte within 16-byte cache line; `addr[3:2]` selects 32-bit word, `addr[1:0]` selects byte)
  - **Index (`addr[10:4]`)**: 7 bits (indexes one of the 128 cache lines)
  - **Tag (`addr[31:11]`)**: 21 bits (compared against tag SRAM entry)
- **SRAM Storage Requirements**:
  - Data RAM: $128 \text{ lines} \times 128 \text{ bits} = 16,384 \text{ bits}$ (half a 36Kb Xilinx Block RAM block)
  - Tag & Valid RAM: $128 \text{ lines} \times (21\text{-bit Tag} + 1\text{-bit Valid}) = 2,816 \text{ bits}$

---

## 3. Cache Controller & Miss FSM

```
                  +----------------------------------------------+
                  |                     IDLE                     |
                  |  - Compare Tag & Valid bit on memory access  |
                  +----------------------------------------------+
                            |                           ^
                 Read Miss  |                           | Refill Complete
                            v                           |
                  +-------------------+       +-------------------+
                  |   REFILL_REQ      | ----> |   BURST_REFILL    |
                  | Assert mem_read   |       | Transfer 4 words  |
                  | to main memory    |       | from BRAM/SDRAM   |
                  +-------------------+       +-------------------+
```

1. **Hit Operation (1-Cycle Latency)**:
   - On a load instruction (`MemRead` active in MEM):
     - Indexed line tag and valid bit read synchronously.
     - If `valid == 1` and `tag_match == 1`: **Cache Hit** (`dcache_hit = 1`).
     - Requested word extracted from cache line and forwarded to `WB` stage in **1 cycle**.
   - On a store instruction (`MemWrite` active in MEM):
     - If hit: Line updated with byte write-strobe masking (`dmem_wstrb[3:0]`).

2. **Write Policy**:
   - **Write-Through with No-Write-Allocate** (or Write-Back with Dirty bit):
     - Stores update the cache line on hit and propagate to background data memory.
     - On write miss: Writes pass directly to background memory without evicting a cache block.

3. **Miss Handling & Pipeline Stall (`dcache_stall`)**:
   - On a read miss (`MemRead && !dcache_hit`):
     - Asserts `dcache_stall = 1` directly to the `hazard_unit`.
     - Hazard unit freezes PC (`stall_if = 1`), freezes IF/ID, ID/EX, and EX/MEM registers.
     - Controller initiates a 4-word burst refill from main memory.
     - Upon refill completion, line is written to SRAM, `valid` bit set, and stalled load completes.

---

## 4. Signal Interface

| Port Name | Direction | Width | Description |
|---|:---:|:---:|---|
| `clk` | Input | 1 bit | 50 MHz synchronous core clock |
| `reset_n` | Input | 1 bit | Active-low synchronous reset (clears all valid bits) |
| **CPU MEM Interface** | | | |
| `mem_addr` | Input | 32 bits | Memory byte address from EX stage (`alu_result`) |
| `mem_wdata` | Input | 32 bits | Forwarded store data (`op_b_fwd`) |
| `mem_wstrb` | Input | 4 bits | Byte-write enable strobe (`SB`, `SH`, `SW`) |
| `mem_re` | Input | 1 bit | Data read strobe (`LB`, `LH`, `LW`, `LBU`, `LHU`) |
| `mem_we` | Input | 1 bit | Data write strobe (`SB`, `SH`, `SW`) |
| `raw_rdata` | Output | 32 bits | Raw data word returned to Memory stage formatter |
| `dcache_stall` | Output | 1 bit | Freeze pipeline during cache miss refill |
| `dcache_hit` | Output | 1 bit | High when current access hits in cache |
| **Main Memory Interface** | | | |
| `bmem_addr` | Output | 32 bits | Block-aligned memory address for burst read/write |
| `bmem_wdata` | Output | 128 bits | 16-byte cache line write data |
| `bmem_rdata` | Input | 128 bits | 16-byte cache line read data from background RAM |
| `bmem_req` | Output | 1 bit | Memory transaction request strobe |
| `bmem_ready` | Input | 1 bit | Memory transaction completion acknowledge |

---

## 5. Directory & Verification Roadmap
- Modular RTL structure (`modules/dcache_controller.v`, `modules/dcache_data_sram.v`, `modules/dcache_tag_sram.v`)
- Unit testbench verifying:
  1. Cold miss on initial access
  2. Sequential hits
  3. Capacity eviction & replacement
  4. Byte write masking (`SB`, `SH`, `SW`)
  5. Hazard interlock & pipeline stall verification
