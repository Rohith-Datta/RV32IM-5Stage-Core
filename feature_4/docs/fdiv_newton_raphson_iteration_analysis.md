# Newton Raphson Method Floating-Point Reciprocal Iteration Analysis

## Mathematical Formulation
To compute $Q = N / D$:
1. Normalize divisor $D \in [0.5, 1.0)$.
2. Initial guess $X_0$ from 256-entry lookup table: $|X_0 - 1/D| \le 2^{-8}$.
3. First Newton-Raphson iteration:
   $$X_1 = X_0 (2 - D \cdot X_0)$$
   Accuracy increases to 16 bits.
4. Second iteration:
   $$X_2 = X_1 (2 - D \cdot X_1)$$
   Accuracy reaches 27 bits (exceeding IEEE 754 24-bit single-precision mantissa).
