# L1 Data Cache Banked SRAM Organization

## Memory Organization
- **Capacity**: 2048 Bytes (2 KB).
- **Block / Line Size**: 16 Bytes (4 words per cache line).
- **Total Lines**: 128 cache lines ($2048 / 16 = 128$).
- **Index Bits**: `addr[10:4]` (7 bits $\rightarrow 2^7 = 128$ lines).
- **Block Offset**: `addr[3:0]` (4 bits $\rightarrow 16$ bytes).
- **Tag Bits**: `addr[31:11]` (21 bits).

### Byte-Enable Architecture
The data array consists of four byte-wide synchronous BRAM banks. Write operations assert specific `we[3:0]` strobes according to instruction type (`SB`, `SH`, `SW`) and byte offset, eliminating read-modify-write latency.
