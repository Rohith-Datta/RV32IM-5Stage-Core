# Pipelined FADD / FSUB Architecture

## Pipeline Stages
- **Stage 1**: Exponent alignment, mantissa shift, significand addition/subtraction.
- **Stage 2**: Normalization, leading zero count, Round-to-Nearest-Even (RNE) rounding.
- **Latency**: 2 clock cycles
