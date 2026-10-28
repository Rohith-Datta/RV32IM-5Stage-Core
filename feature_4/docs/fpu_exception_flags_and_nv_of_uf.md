# IEEE 754 Floating-Point Exception Detection Specifications

## Supported Exception Flags
1. **Invalid Operation (`NV`)**: Triggered by $\text{Inf} - \text{Inf}$, $0 \times \text{Inf}$, or signaling NaN inputs.
2. **Division by Zero (`DZ`)**: Triggered by $X / 0$ where $X \neq 0$.
3. **Overflow (`OF`)**: Result exponent exceeds 254 after rounding.
4. **Underflow (`UF`)**: Non-zero result exponent falls below 1 after rounding.
5. **Inexact (`NX`)**: Rounding modified the exact infinite-precision result.
