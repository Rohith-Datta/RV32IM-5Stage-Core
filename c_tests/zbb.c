// ============================================================================
// File: zbb.c
// Description: Simple Bare-Metal C Verification for RISC-V Zbb Extension
// Tests all 18 instructions and returns 18 (0x12) in register a0 on 100% PASS
// ============================================================================

int main(void) {
    int passes = 0;

    int a = 5;
    int b = -2; // 0xFFFFFFFE

    // 1. ANDN: rd = a & ~b -> 5 & 1 = 1
    int r1;
    __asm__ ("andn %0, %1, %2" : "=r"(r1) : "r"(a), "r"(b));
    if (r1 == 1) passes++;

    // 2. ORN: rd = a | ~b -> 5 | 1 = 5
    int r2;
    __asm__ ("orn %0, %1, %2" : "=r"(r2) : "r"(a), "r"(b));
    if (r2 == 5) passes++;

    // 3. XNOR: rd = ~(a ^ b) -> ~(5 ^ -2) = 4
    int r3;
    __asm__ ("xnor %0, %1, %2" : "=r"(r3) : "r"(a), "r"(b));
    if (r3 == 4) passes++;

    // 4. MAX: signed max(-2, 5) = 5
    int r4;
    __asm__ ("max %0, %1, %2" : "=r"(r4) : "r"(b), "r"(a));
    if (r4 == 5) passes++;

    // 5. MIN: signed min(-2, 5) = -2
    int r5;
    __asm__ ("min %0, %1, %2" : "=r"(r5) : "r"(b), "r"(a));
    if (r5 == -2) passes++;

    // 6. MAXU: unsigned max(0xFFFFFFFE, 5) = 0xFFFFFFFE
    unsigned int r6;
    __asm__ ("maxu %0, %1, %2" : "=r"(r6) : "r"(b), "r"(a));
    if (r6 == 0xFFFFFFFE) passes++;

    // 7. MINU: unsigned min(0xFFFFFFFE, 5) = 5
    unsigned int r7;
    __asm__ ("minu %0, %1, %2" : "=r"(r7) : "r"(b), "r"(a));
    if (r7 == 5) passes++;

    int neg1 = -1; // 0xFFFFFFFF

    // 8. ZEXT.H: zero-extend 16 bits -> 0x0000FFFF
    unsigned int r8;
    __asm__ ("zext.h %0, %1" : "=r"(r8) : "r"(neg1));
    if (r8 == 0x0000FFFF) passes++;

    // 9. SEXT.H: sign-extend 16 bits -> -1
    int r9;
    __asm__ ("sext.h %0, %1" : "=r"(r9) : "r"(neg1));
    if (r9 == -1) passes++;

    // 10. SEXT.B: sign-extend 8 bits -> -1
    int r10;
    __asm__ ("sext.b %0, %1" : "=r"(r10) : "r"(neg1));
    if (r10 == -1) passes++;

    unsigned int val = 0x000000F0;

    // 11. CLZ: count leading zeros in 0x000000F0 -> 24
    unsigned int r11;
    __asm__ ("clz %0, %1" : "=r"(r11) : "r"(val));
    if (r11 == 24) passes++;

    // 12. CTZ: count trailing zeros in 0x000000F0 -> 4
    unsigned int r12;
    __asm__ ("ctz %0, %1" : "=r"(r12) : "r"(val));
    if (r12 == 4) passes++;

    // 13. CPOP: count set bits (popcount) in 0x000000F0 -> 4
    unsigned int r13;
    __asm__ ("cpop %0, %1" : "=r"(r13) : "r"(val));
    if (r13 == 4) passes++;

    // 14. ROL: rotate left 0x000000F0 by 5 -> 0x00001E00
    unsigned int r14;
    __asm__ ("rol %0, %1, %2" : "=r"(r14) : "r"(val), "r"(a));
    if (r14 == 0x00001E00) passes++;

    // 15. ROR: rotate right 0x000000F0 by 5 -> 0x80000007
    unsigned int r15;
    __asm__ ("ror %0, %1, %2" : "=r"(r15) : "r"(val), "r"(a));
    if (r15 == 0x80000007) passes++;

    // 16. RORI: rotate right immediate 0x000000F0 by 4 -> 0x0000000F
    unsigned int r16;
    __asm__ ("rori %0, %1, 4" : "=r"(r16) : "r"(val));
    if (r16 == 0x0000000F) passes++;

    // 17. REV8: byte-swap (endianness reverse) -> 0xF0000000
    unsigned int r17;
    __asm__ ("rev8 %0, %1" : "=r"(r17) : "r"(val));
    if (r17 == 0xF0000000) passes++;

    // 18. ORC.B: byte-wise OR combine -> 0x000000FF
    unsigned int r18;
    __asm__ ("orc.b %0, %1" : "=r"(r18) : "r"(val));
    if (r18 == 0x000000FF) passes++;

    // Return total passed checks (18 if all passed)
    return passes;
}
