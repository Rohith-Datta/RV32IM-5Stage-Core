# RISC-V Zbb Byte Reverse (REV8) and OR-Combine (ORC.B)

## Instructions
- **`rev8 rd, rs1`**: Endianness byte reversal:
  `{rs1[7:0], rs1[15:8], rs1[23:16], rs1[31:24]}` (Pure wiring, 0 logic delay).
- **`orc.b rd, rs1`**: Byte-wise reduction OR:
  Sets each byte to `0xFF` if any bit in that byte is 1, else `0x00`.
