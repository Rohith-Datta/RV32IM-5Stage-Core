# IEEE 754 Single-Precision Floating-Point Format Specification

## Architecture Overview
The custom RV32MF Floating-Point Unit implements IEEE 754-2008 single-precision (binary32) arithmetic.

### Bit Layout (32 bits)
- **Sign bit (`S`)**: 1 bit (`[31]`). 0 for positive, 1 for negative.
- **Biased Exponent (`E`)**: 8 bits (`[30:23]`), bias = 127 (`0x7F`).
- **Normalized Mantissa / Fraction (`M`)**: 23 bits (`[22:0]`), implicit leading 1 for normalized numbers ($1.M$).

### Numerical Interpretation
$$V = (-1)^S \times 2^{E - 127} \times (1 + \sum_{i=1}^{23} b_{23-i} 2^{-i})$$

### Special Representation Encodings
| Representation | Sign ($S$) | Exponent ($E$) | Fraction ($M$) | Hardware Value |
| :--- | :---: | :---: | :---: | :--- |
| **Zero (+0.0 / -0.0)** | $0 / 1$ | `0x00` | `0x000000` | Handled with sign preservation |
| **Subnormal Numbers** | $0 / 1$ | `0x00` | $\neq 0$ | Flushed to zero (FTZ mode supported) |
| **Normalized Numbers**| $0 / 1$ | `0x01` .. `0xFE`| Any | Full 24-bit mantissa processing |
| **Infinity (+Inf / -Inf)**| $0 / 1$ | `0xFF` | `0x000000` | Generates arithmetic overflow flag |
| **Quiet NaN (qNaN)** | $0 / 1$ | `0xFF` | MSB = 1 | Propagated across FPU pipeline stages |
| **Signaling NaN (sNaN)**| $0 / 1$ | `0xFF` | MSB = 0, $\neq 0$ | Raises Invalid Operation (`NV`) flag |

### Rounding Modes
Hardware natively supports **Round to Nearest, ties to Even (RNE)** per IEEE 754 specification.
