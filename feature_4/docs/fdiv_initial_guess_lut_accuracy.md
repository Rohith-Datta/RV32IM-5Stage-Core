# 8-Bit Reciprocal Initial Approximation Lookup Table

## ROM Table Architecture
- **Input**: Divisor mantissa bits `D[22:15]` (8 bits).
- **Output**: 8-bit initial guess `X0[7:0]`.
- **Maximum Absolute Error**: $< 2^{-8} = 0.0039$.
- **BRAM / Distributed ROM Cost**: 1 single LUT6 per 2 output bits, totaling 4 LUTs.
