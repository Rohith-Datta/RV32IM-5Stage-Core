# IEEE 754 FDIV Newton Raphson Method Implementation

## Algorithmic Foundation
Iterative reciprocal approximation:
`X_{k+1} = X_k * (2 - D * X_k)`
Converges to 24-bit single-precision mantissa accuracy in 15 clock cycles.
