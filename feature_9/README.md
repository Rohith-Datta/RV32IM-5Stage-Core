# Feature 9: Bit-Manipulation Extension (Zbb)

## Objectives & Scope
Integration of the official RISC-V **Zbb (Basic Bit-Manipulation)** instruction subset into the Execute (EX) stage ALU to accelerate bitwise manipulation, arithmetic, data extraction, and cryptography.

## Supported Instructions

### 1. Count Operations
- `CLZ`: Count Leading Zeros
- `CTZ`: Count Trailing Zeros
- `CPOP`: Count Set Bits (Population Count)

### 2. Min / Max Operations
- `MIN` / `MAX`: Signed minimum and maximum
- `MINU` / `MAXU`: Unsigned minimum and maximum

### 3. Bitwise Inversion Logic
- `ANDN`: Bitwise AND with negated operand ($rs1 \ \& \ \sim rs2$)
- `ORN`: Bitwise OR with negated operand ($rs1 \ \| \ \sim rs2$)
- `XNOR`: Bitwise Exclusive NOR ($rs1 \ \oplus \ \sim rs2$)

### 4. Bitwise Rotations
- `ROR` / `RORI`: Rotate Right (register / immediate)
- `ROL`: Rotate Left

### 5. Byte Sign & Zero Extension
- `SEXT.B`, `SEXT.H`: Sign-extend byte and halfword
- `ZEXT.H`: Zero-extend halfword
- `ORC.B`: Bitwise OR-combine bytes
- `REV8`: Byte-reverse word (Endianness swap)
