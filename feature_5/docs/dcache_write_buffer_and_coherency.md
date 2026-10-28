# L1 Data Cache Write Buffer and Memory Bus Serialization

## Architectural Specifications
The 2KB L1 Data Cache employs a strict **Write-Through, No-Write-Allocate** policy to ensure continuous cache-to-main-memory consistency.

### Write Buffer FIFO Datapath
- **Depth**: 4-entry circular FIFO buffer.
- **Entry Width**: 64 bits (32-bit address + 32-bit store data + 4-bit byte enables).
- **Core Decoupling**: The processor pipeline experiences 0 stall cycles on store instructions when the write buffer is not full.
- **Stall Condition**: If back-to-back stores saturate the 4-entry FIFO, the hazard unit asserts `dcache_stall` until the memory controller drains the oldest entry to main memory.
