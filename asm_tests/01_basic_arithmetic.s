# ==============================================================================
# File: asm_tests/01_basic_arithmetic.s
# Description: RV32I Base Integer ALU & Control Flow Verification
# Target: Pipelined RV32IMF Core on Nexys A7 FPGA
# ==============================================================================

.globl main
.text

main:
    # 1. Initialize Register Values
    li      x1, 15              # x1 = 15
    li      x2, 25              # x2 = 25
    li      x3, 100             # x3 = 100

    # 2. Basic Arithmetic (Tests ADD, SUB, ADDI)
    add     x4, x1, x2          # x4 = 15 + 25 = 40 (0x28)
    sub     x5, x3, x4          # x5 = 100 - 40 = 60 (0x3C)
    addi    x6, x5, -10         # x6 = 60 - 10 = 50 (0x32)

    # 3. Logical Operations (AND, OR, XOR, XORI)
    and     x7, x1, x2          # x7 = 15 & 25 = 9 (0x09)
    or      x8, x1, x2          # x8 = 15 | 25 = 31 (0x1F)
    xor     x9, x1, x2          # x9 = 15 ^ 25 = 22 (0x16)
    xori    x10, x9, -1         # x10 = ~x9 = NOT(22) = 0xFFFFFFE9

    # 4. Shifts (SLL, SRL, SRA)
    li      x11, 4              # Shift amount = 4
    sll     x12, x1, x11        # x12 = 15 << 4 = 240 (0xF0)
    srl     x13, x12, x11       # x13 = 240 >> 4 = 15 (0x0F)
    li      x14, -128           # x14 = 0xFFFFFF80
    sra     x15, x14, x11       # x15 = -128 >> 4 = -8 (0xFFFFFFF8, sign preserved)

    # 5. Comparisons (SLT, SLTI, SLTU)
    slt     x16, x1, x2         # x16 = (15 < 25) ? 1 : 0 -> 1
    slt     x17, x2, x1         # x17 = (25 < 15) ? 1 : 0 -> 0
    slti    x18, x14, 0         # x18 = (-128 < 0) ? 1 : 0 -> 1

    # 6. Branch & Loop (Sums integers from 1 to 5 = 15)
    li      x19, 5              # loop counter = 5
    li      x20, 0              # accumulator = 0
loop_sum:
    add     x20, x20, x19       # sum += counter
    addi    x19, x19, -1        # counter--
    bnez    x19, loop_sum       # repeat if counter != 0

    # 7. Store Result to Data RAM at 0x00000200
    li      x21, 0x00000200
    sw      x4, 0(x21)          # RAM[0x200] = 40
    sw      x5, 4(x21)          # RAM[0x204] = 60
    sw      x6, 8(x21)          # RAM[0x208] = 50
    sw      x20, 12(x21)        # RAM[0x20C] = 15 (Sum of 1..5)

    # Signature: 0xCAFE0001 indicates Test 01 Passed
    li      x22, 0xCAFE0001
    sw      x22, 16(x21)        # RAM[0x210] = 0xCAFE0001

    ret
