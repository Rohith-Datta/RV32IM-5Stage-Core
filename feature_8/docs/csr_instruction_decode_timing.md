# CSR Instruction Atomic Read-Modify-Write Timing

## Instruction Set Support
The CSR execution unit implements standard RISC-V privileged instruction encodings:
- **`CSRRW` / `CSRRWI`**: Atomic Swap / Write.
- **`CSRRS` / `CSRRSI`**: Atomic Read and Set Bits.
- **`CSRRC` / `CSRRCI`**: Atomic Read and Clear Bits.

### Single-Cycle EX Stage Execution
- Reading previous CSR value routes to `rd` via standard WB forwarding.
- Modification to shadow register occurs on positive clock edge.
