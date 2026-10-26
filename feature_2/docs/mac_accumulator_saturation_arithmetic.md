# 64-Bit Neural Network MAC Accumulator and Saturation Arithmetic

## Accumulator Architecture
The Neural Network MAC coprocessor maintains a 64-bit internal accumulator register (`acc_reg`) designed to prevent loss of precision during extensive matrix dot-product operations.

### Saturation Arithmetic Logic
When performing high-throughput accumulation, integer overflow is prevented via configurable saturating logic:
- **Positive Saturation**: When sum exceeds $+2^{63} - 1$, the accumulator clamps to `0x7FFFFFFFFFFFFFFF`.
- **Negative Saturation**: When sum falls below $-2^{63}$, the accumulator clamps to `0x8000000000000000`.
- **Overflow Flag**: Latchable status bit readable via UART telemetry or status registers.

### Readout Latency
- Reading lower 32 bits (`MREADL`) completes in 1 cycle with zero core stall.
- Reading upper 32 bits (`MREADH`) completes in 1 cycle with zero core stall.
- Total MAC throughput: **1 operation per clock cycle (1.0 IPC)** in continuous accumulation loops.
