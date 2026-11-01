# RISC-V Zbb Min/Max (MAX, MAXU, MIN, MINU) Architecture

## Instruction Set Support
- `max rd, rs1, rs2`: Signed maximum.
- `maxu rd, rs1, rs2`: Unsigned maximum.
- `min rd, rs1, rs2`: Signed minimum.
- `minu rd, rs1, rs2`: Unsigned minimum.

### Datapath Integration
Reuses the 32-bit subtractor from the standard ALU comparator (`slt` / `sltu`), selecting operand $A$ or $B$ via conditional multiplexer based on difference sign bit.
