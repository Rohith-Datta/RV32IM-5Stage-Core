# IEEE 754 Single-Precision Floating-Point Multiplier (FMUL) Architecture

## Mantissa Multiplication Datapath
Single-precision floating-point multiplication requires multiplying two 24-bit significands ($1.M_A \times 1.M_B$), producing a 48-bit intermediate product.

### Hardware Mapping to DSP48E1 Slices
On the Nexys Artix-7 100T CSG324 FPGA:
- A single Xilinx DSP48E1 slice natively supports $25 \times 18$ signed multiplication.
- To execute $24 \times 24$ unsigned mantissa multiplication, 2 cascaded DSP48E1 slices are configured.
- Operating frequency: **50 MHz** core clock, achieving single-cycle execution within the FPU EX stage.

### Exponent Calculation and Bias Adjustment
$$E_{\text{raw}} = E_A + E_B - 127$$
- If product bit $P[47] == 1$: Normalization shift right by 1, $E_{\text{res}} = E_{\text{raw}} + 1$.
- If product bit $P[47] == 0$: Mantissa remains at $P[46:23]$, $E_{\text{res}} = E_{\text{raw}}$.

### Underflow and Overflow Detection
- Exponent $< 1$: Signals floating-point underflow (`UF`).
- Exponent $\ge 255$: Signals floating-point overflow (`OF`) and clamps to $\pm \text{Infinity}$.
