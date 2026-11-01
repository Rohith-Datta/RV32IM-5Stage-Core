# IEEE 754 FDIV Restoring Division Method Implementation

## Algorithmic Foundation
The hardware floating-point divider uses an iterative Radix-4 restoring division method:
- Computes 2 quotient bits per calculation clock cycle.
- Iterates over 13 clock cycles to generate 26 quotient bits (24-bit mantissa + guard and round bits).
- Total deterministic latency: 15 clock cycles (1 cycle unpack, 13 cycles restoring division iterations, 1 cycle RNE rounding and pack).
