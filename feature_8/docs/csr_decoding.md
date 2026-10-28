# CSR Instruction Decoder Specification

## Supported Instructions
- `CSRRW` (Atomic Read/Write CSR)
- `CSRRS` (Atomic Read and Set Bits in CSR)
- `CSRRC` (Atomic Read and Clear Bits in CSR)
Decoded in Decode stage and dispatched to CSR unit.
