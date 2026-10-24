# Multi-Cycle FPU Hazard Interlock

## Handshaking Protocol
- Asserts `fpu_busy` during multi-cycle division.
- Centralized hazard unit freezes IF/ID, ID/EX, and PC until completion.
