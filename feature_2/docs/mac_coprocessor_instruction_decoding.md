# 64-Bit Neural Network MAC Coprocessor Instruction Decoding

## Custom RV32 Coprocessor Interface
To accelerate deep learning matrix operations and digital filtering, the core integrates a dedicated Multiply-Accumulate (MAC) coprocessor attached to the EX stage.

### Instruction Opcodes (Custom-0: `0x0B`)
| Instruction | Opcode | func3 | func7 | Operands | Operation |
| :--- | :---: | :---: | :---: | :--- | :--- |
| `MAC` | `0x0B` | `0x0` | `0x00` | `rs1, rs2` | $\text{ACC} \leftarrow \text{ACC} + (\text{rs1} \times \text{rs2})$ |
| `MACC`| `0x0B` | `0x1` | `0x00` | `rs1, rs2` | $\text{ACC} \leftarrow (\text{rs1} \times \text{rs2})$ (Clear & MAC) |
| `MREADL`| `0x0B`| `0x2` | `0x00` | `rd` | $\text{rd} \leftarrow \text{ACC}[31:0]$ |
| `MREADH`| `0x0B`| `0x3` | `0x00` | `rd` | $\text{rd} \leftarrow \text{ACC}[63:32]$ |
| `MCLEAR`| `0x0B`| `0x4` | `0x00` | None | $\text{ACC} \leftarrow 0$ |

### Pipeline Control and Forwarding
- Decoder asserts `coproc_en` and selects MAC arithmetic subtype.
- Register forwarding paths feed `rs1` and `rs2` from EX/MEM or MEM/WB stages without introducing pipeline bubbles.
