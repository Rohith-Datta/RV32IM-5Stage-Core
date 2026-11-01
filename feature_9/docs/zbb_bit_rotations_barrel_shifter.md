# RISC-V Zbb Bitwise Rotation (ROL, ROR, RORI) Barrel Shifter

## Architectural Formulation
- **`ror rd, rs1, rs2`**: `rd = (rs1 >> rs2[4:0]) | (rs1 << (32 - rs2[4:0]))`.
- **`rori rd, rs1, shamt`**: Right rotation by immediate constant.
- **`rol rd, rs1, rs2`**: Left rotation via inverted right shift: `ror(rs1, (32 - rs2[4:0]))`.

### Timing & Resource Efficiency
Implemented as a 64-bit replicated operand right shifter, eliminating DSP usage and maintaining 1-cycle latency at 50 MHz.
