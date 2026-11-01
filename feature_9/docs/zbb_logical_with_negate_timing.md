# RISC-V Zbb Logical with Negate (ANDN, ORN, XNOR) Architecture

## Instruction Implementations
- **`andn rd, rs1, rs2`**: `rd = rs1 & ~rs2`.
- **`orn  rd, rs1, rs2`**: `rd = rs1 | ~rs2`.
- **`xnor rd, rs1, rs2`**: `rd = ~(rs1 ^ rs2)`.

### Execution Timing
Integrated directly into the EX stage ALU multiplexer, completing in exactly **1 clock cycle** with zero stall overhead.
