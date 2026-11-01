# Hardware Division Profiling & Benchmarking Results

## Results Summary
- **Restoring Division (Iterative Shift-and-Subtract)**: 32 clock cycles for 32-bit quotient calculation.
- **Hardware Restoring Division Method**: Deterministic 32 cycles with zero pipeline timing violations and 1-cycle early out for divide-by-zero or signed overflow.
