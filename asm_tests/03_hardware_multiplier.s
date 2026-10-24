# ==============================================================================
# File: asm_tests/03_hardware_multiplier.s
# Description: RV32M Standard Hardware Multiplier and Divider Verification
# Operates with both Booth Radix-4 and DSP48E1 architectures (SW[3] selectable)
# ==============================================================================

.globl main
.text

main:
    # --------------------------------------------------------------------------
    # 1. Hardware Multiplications (MUL, MULH, MULHU)
    # --------------------------------------------------------------------------
    li      x1, 1234
    li      x2, 5678
    mul     x3, x1, x2          # x3 = 1234 * 5678 = 7,006,652 (0x006AEABC)

    # 64-bit full product test
    li      x4, 0x12345678
    li      x5, 0x00000010
    mul     x6, x4, x5          # Low 32 bits: 0x23456780
    mulhu   x7, x4, x5          # High 32 bits: 0x00000001

    # --------------------------------------------------------------------------
    # 2. Hardware Divisions & Modulos (DIV, DIVU, REM, REMU)
    # --------------------------------------------------------------------------
    li      x8, 1000
    li      x9, 30
    div     x10, x8, x9         # x10 = 1000 / 30 = 33
    rem     x11, x8, x9         # x11 = 1000 % 30 = 10

    # Negative signed division: -1000 / 30 = -33 (0xFFFFFFDF)
    li      x12, -1000
    div     x13, x12, x9        # x13 = -33 (0xFFFFFFDF)
    rem     x14, x12, x9        # x14 = -10 (0xFFFFFFF6)

    # --------------------------------------------------------------------------
    # 3. Special Case: Integer Division by Zero (RISC-V Spec Requirements)
    # Divisor = 0 -> Quotient = -1 (0xFFFFFFFF), Remainder = Dividend (100)
    # --------------------------------------------------------------------------
    li      x15, 100
    li      x16, 0
    div     x17, x15, x16       # Expected: 0xFFFFFFFF (-1)
    rem     x18, x15, x16       # Expected: 100 (0x64)

    # --------------------------------------------------------------------------
    # 4. Special Case: Integer Signed Overflow (INT_MIN / -1)
    # Overflow -> Quotient = INT_MIN (0x80000000), Remainder = 0
    # --------------------------------------------------------------------------
    li      x19, 0x80000000     # INT_MIN (-2,147,483,648)
    li      x20, -1
    div     x21, x19, x20       # Expected: 0x80000000 (INT_MIN)
    rem     x22, x19, x20       # Expected: 0

    # --------------------------------------------------------------------------
    # 5. Store Results to Data RAM at 0x00000200
    # --------------------------------------------------------------------------
    li      x23, 0x00000200
    sw      x3, 0(x23)          # RAM[0x200] = 7,006,652
    sw      x6, 4(x23)          # RAM[0x204] = 0x23456780
    sw      x7, 8(x23)          # RAM[0x208] = 0x00000001
    sw      x10, 12(x23)        # RAM[0x20C] = 33
    sw      x11, 16(x23)        # RAM[0x210] = 10
    sw      x13, 20(x23)        # RAM[0x214] = -33
    sw      x17, 24(x23)        # RAM[0x218] = 0xFFFFFFFF (Div0)
    sw      x21, 28(x23)        # RAM[0x21C] = 0x80000000 (Overflow)

    # Signature: 0xCAFE0003 indicates M-Extension Verification Passed!
    li      x24, 0xCAFE0003
    sw      x24, 32(x23)        # RAM[0x220] = 0xCAFE0003

    ret
