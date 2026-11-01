# FDIV Special Case Handling and Early-Out Bypass

## Special Case Prioritization
1. **Division by Zero ($D == 0, N \neq 0$)**:
   - Asserts `DZ` flag.
   - Result forced to $\text{Sign}(N) \oplus \text{Sign}(D) \times \text{Infinity}$.
   - Completes in 1 cycle without initiating restoring division iterations.
2. **Zero divided by Zero ($0 / 0$)**:
   - Asserts `NV` flag.
   - Returns Canonical Quiet NaN.
