# ==============================================================================
# File: asm_tests/04_fpu_special_cases.s
# Description: IEEE-754 FPU Arithmetic and Corner/Special Cases Verification
# Target: Feature 4 Pipelined RV32IMF Core with Hardware Newton-Raphson Divider
# ==============================================================================

.globl main
.text

main:
    # --------------------------------------------------------------------------
    # 1. Load Floating-Point Constants into Integer Registers
    # --------------------------------------------------------------------------
    lui     x1, 0x3FC00         # x1  = 1.5f (0x3FC00000)
    lui     x2, 0x40200         # x2  = 2.5f (0x40200000)
    lui     x3, 0x40000         # x3  = 2.0f (0x40000000)
    lui     x4, 0x40E00         # x4  = 7.0f (0x40E00000)
    li      x5, 0               # x5  = 0.0f (0x00000000)
    lui     x6, 0xC0000         # x6  = -2.0f (0xC0000000)
    lui     x7, 0x7F800         # x7  = +Infinity (0x7F800000)
    lui     x8, 0xC0C00         # x8  = -6.0f (0xC0C00000)
    li      x9, 10              # x9  = 10
    lui     x10, 0x80000        # x10 = INT_MIN (0x80000000)
    li      x11, -1             # x11 = -1

    # --------------------------------------------------------------------------
    # 2. Standard Floating-Point Operations
    # --------------------------------------------------------------------------
    # FADD.S (5 Cycles): 1.5 + 2.5 = 4.0f (0x40800000)
    fadd.s  x12, x1, x2

    # FSUB.S (5 Cycles): 4.0 - 1.5 = 2.5f (0x40200000)
    fsub.s  x13, x12, x1

    # FMUL.S (4 Cycles): 2.0 * 2.5 = 5.0f (0x40A00000)
    fmul.s  x14, x2, x3

    # FDIV.S (15 Cycles via Hardware Divider): 7.0 / 2.0 = 3.5f (0x40600000)
    fdiv.s  x15, x4, x3

    # --------------------------------------------------------------------------
    # 3. Special Cases (Division by Zero, NaN, Infinity)
    # --------------------------------------------------------------------------
    # Special Case 1: Division by Zero: 2.0 / 0.0 -> +Infinity (0x7F800000)
    fdiv.s  x16, x3, x5

    # Special Case 2: Negative Division by Zero: -2.0 / 0.0 -> -Infinity (0xFF800000)
    fdiv.s  x17, x6, x5

    # Special Case 3: Zero divided by Zero: 0.0 / 0.0 -> qNaN (0x7FC00000)
    fdiv.s  x18, x5, x5

    # Special Case 4: Infinity divided by Infinity: +Inf / +Inf -> qNaN (0x7FC00000)
    fdiv.s  x19, x7, x7

    # Special Case 5: Negative Division with Sign Preservation: -6.0 / 2.0 = -3.0f (0xC0400000)
    fdiv.s  x20, x8, x3

    # Special Case 6: Integer Division by Zero: 10 / 0 -> 0xFFFFFFFF (-1)
    div     x21, x9, x5

    # Special Case 7: Integer Signed Overflow: INT_MIN / -1 -> INT_MIN (0x80000000)
    div     x22, x10, x11

    # --------------------------------------------------------------------------
    # 4. Store Results to Data RAM at Address 0x00000200
    # --------------------------------------------------------------------------
    li      x23, 0x00000200
    sw      x12, 0(x23)         # RAM[0x200] = 4.0f (0x40800000)
    sw      x13, 4(x23)         # RAM[0x204] = 2.5f (0x40200000)
    sw      x14, 8(x23)         # RAM[0x208] = 5.0f (0x40A00000)
    sw      x15, 12(x23)        # RAM[0x20C] = 3.5f (0x40600000)
    sw      x16, 16(x23)        # RAM[0x210] = +Inf (0x7F800000)
    sw      x17, 20(x23)        # RAM[0x214] = -Inf (0xFF800000)
    sw      x18, 24(x23)        # RAM[0x218] = qNaN (0x7FC00000)
    sw      x19, 28(x23)        # RAM[0x21C] = qNaN (0x7FC00000)
    sw      x20, 32(x23)        # RAM[0x220] = -3.0f (0xC0400000)
    sw      x21, 36(x23)        # RAM[0x224] = -1 (0xFFFFFFFF)
    sw      x22, 40(x23)        # RAM[0x228] = INT_MIN (0x80000000)

    # Completion signature: 0xCAFEFEED written to RAM[0x22C]
    li      x24, 0xCAFEFEED
    sw      x24, 44(x23)        # RAM[0x22C] = 0xCAFEFEED

    ret
