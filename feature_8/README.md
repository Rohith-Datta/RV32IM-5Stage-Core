# Feature 8: Performance Counters (Passive CSRs)

## Objectives & Scope
Integration of passive hardware performance monitoring Control and Status Registers (CSRs) to track clock cycles, instruction throughput, and architectural hazard events without disrupting pipeline flow.

## Implemented Passive Performance Registers
- `cycle` / `cycleh`: 64-bit counter tracking elapsed clock cycles
- `instret` / `instreth`: 64-bit counter tracking instructions successfully retired in the Writeback (WB) stage
- `hpmcounter3`: Total pipeline stall cycles (load-use stalls, divider stalls, cache misses)
- `hpmcounter4`: Total branch instructions executed
- `hpmcounter5`: Total branch mispredictions
- `hpmcounter6`: L1 Instruction Cache miss counter
- `hpmcounter7`: L1 Data Cache miss counter

## Access Interface
- Read-accessible via standard RISC-V instructions:
  - `csrr rd, cycle` (CSR address `0xC00`)
  - `csrr rd, time` (CSR address `0xC01`)
  - `csrr rd, instret` (CSR address `0xC02`)
- Passive read-only monitoring: counters update in hardware automatically on every relevant pipeline event.
