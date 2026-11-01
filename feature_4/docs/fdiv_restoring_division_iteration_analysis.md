# Restoring Division Method Floating-Point Division (FDIV.S) Analysis

## Architectural Formulation
The single-precision Floating-Point Unit implements a high-throughput **Radix-4 Restoring Division Algorithm** for `FDIV.S`.

### Algorithm Execution & Pipeline Timing
- **Total Latency**: Exactly 15 clock cycles.
  - Cycle 1: Operand unpack, sign calculation ($S_A \oplus S_B$), and exponent subtraction ($E_A - E_B + 127$).
  - Cycles 2 to 14 (13 Calculation Cycles): Computes 2 quotient bits per cycle using Radix-4 shift-and-subtract restoring division ($13 \times 2 = 26$ quotient bits).
  - Cycle 15: Rounding (Round to Nearest Even - RNE), exception flag generation (`NV`, `DZ`, `OF`, `UF`, `NX`), and result packing.

### Restoring Step Recurrence
For each quotient bit pair $(q_1, q_0)$ in cycle $k$:
1. Left shift current remainder: $R' = R \ll 1$.
2. Trial subtraction: If $R' \ge D$, then $q_1 = 1$ and $R = R' - D$; else $q_1 = 0$ and $R = R'$.
3. Repeat for $q_0$ to produce 2 quotient bits per clock cycle.
