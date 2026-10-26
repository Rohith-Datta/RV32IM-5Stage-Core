# Hardware Multiplier Radix-4 Booth Recoding and Partial Product Generation

## Algorithmic Formulation
The RV32M multiplier utilizes modified Radix-4 Booth recoding to reduce the number of partial products from 32 down to 16.

### Bit-Pair Recoding Table
For multiplier triplet $(y_{2i+1}, y_{2i}, y_{2i-1})$:
| $y_{2i+1}$ | $y_{2i}$ | $y_{2i-1}$ | Operation on Multiplicand $X$ |
| :---: | :---: | :---: | :--- |
| 0 | 0 | 0 | $0 \times X$ |
| 0 | 0 | 1 | $+1 \times X$ |
| 0 | 1 | 0 | $+1 \times X$ |
| 0 | 1 | 1 | $+2 \times X$ (Shift left by 1) |
| 1 | 0 | 0 | $-2 \times X$ (Negate and shift left 1) |
| 1 | 0 | 1 | $-1 \times X$ (Two's complement negate) |
| 1 | 1 | 0 | $-1 \times X$ (Two's complement negate) |
| 1 | 1 | 1 | $0 \times X$ |

### Timing & Resource Utilization on Nexys Artix-7 100T CSG324
- Single-cycle execution latency in EX stage.
- Zero stall penalty for back-to-back `mul`, `mulh`, `mulhsu`, `mulhu` instructions.
- Fully verified at 50 MHz core clock with positive timing slack.
