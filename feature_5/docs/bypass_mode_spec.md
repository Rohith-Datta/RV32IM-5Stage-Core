# L1 Data Cache Bypass Mode Specification

## Diagnostic Mode Control
Controlled via slide switch SW[1].

- **SW[1] = 0 (Normal Mode)**: Cache lines are allocated and burst refilled on misses.
- **SW[1] = 1 (Bypass Mode)**: Every data access bypasses cache SRAM and directly targets backing memory.
