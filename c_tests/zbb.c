// ============================================================================
// File: zbb.c
// Description: Bare-Metal C Program for RISC-V Zbb Extension Verification
// Target: RV32I_ZBB / RV32IM_ZBB
// ============================================================================

static inline unsigned int rv32_andn(unsigned int a, unsigned int b) {
    unsigned int rd;
    __asm__ ("andn %0, %1, %2" : "=r"(rd) : "r"(a), "r"(b));
    return rd;
}

static inline unsigned int rv32_orn(unsigned int a, unsigned int b) {
    unsigned int rd;
    __asm__ ("orn %0, %1, %2" : "=r"(rd) : "r"(a), "r"(b));
    return rd;
}

static inline unsigned int rv32_xnor(unsigned int a, unsigned int b) {
    unsigned int rd;
    __asm__ ("xnor %0, %1, %2" : "=r"(rd) : "r"(a), "r"(b));
    return rd;
}

static inline int rv32_max(int a, int b) {
    int rd;
    __asm__ ("max %0, %1, %2" : "=r"(rd) : "r"(a), "r"(b));
    return rd;
}

static inline unsigned int rv32_maxu(unsigned int a, unsigned int b) {
    unsigned int rd;
    __asm__ ("maxu %0, %1, %2" : "=r"(rd) : "r"(a), "r"(b));
    return rd;
}

static inline int rv32_min(int a, int b) {
    int rd;
    __asm__ ("min %0, %1, %2" : "=r"(rd) : "r"(a), "r"(b));
    return rd;
}

static inline unsigned int rv32_minu(unsigned int a, unsigned int b) {
    unsigned int rd;
    __asm__ ("minu %0, %1, %2" : "=r"(rd) : "r"(a), "r"(b));
    return rd;
}

static inline unsigned int rv32_zext_h(unsigned int a) {
    unsigned int rd;
    __asm__ ("zext.h %0, %1" : "=r"(rd) : "r"(a));
    return rd;
}

static inline int rv32_sext_h(int a) {
    int rd;
    __asm__ ("sext.h %0, %1" : "=r"(rd) : "r"(a));
    return rd;
}

static inline int rv32_sext_b(int a) {
    int rd;
    __asm__ ("sext.b %0, %1" : "=r"(rd) : "r"(a));
    return rd;
}

static inline unsigned int rv32_clz(unsigned int a) {
    unsigned int rd;
    __asm__ ("clz %0, %1" : "=r"(rd) : "r"(a));
    return rd;
}

static inline unsigned int rv32_ctz(unsigned int a) {
    unsigned int rd;
    __asm__ ("ctz %0, %1" : "=r"(rd) : "r"(a));
    return rd;
}

static inline unsigned int rv32_cpop(unsigned int a) {
    unsigned int rd;
    __asm__ ("cpop %0, %1" : "=r"(rd) : "r"(a));
    return rd;
}

static inline unsigned int rv32_rol(unsigned int a, unsigned int b) {
    unsigned int rd;
    __asm__ ("rol %0, %1, %2" : "=r"(rd) : "r"(a), "r"(b));
    return rd;
}

static inline unsigned int rv32_ror(unsigned int a, unsigned int b) {
    unsigned int rd;
    __asm__ ("ror %0, %1, %2" : "=r"(rd) : "r"(a), "r"(b));
    return rd;
}

static inline unsigned int rv32_rori4(unsigned int a) {
    unsigned int rd;
    __asm__ ("rori %0, %1, 4" : "=r"(rd) : "r"(a));
    return rd;
}

static inline unsigned int rv32_rev8(unsigned int a) {
    unsigned int rd;
    __asm__ ("rev8 %0, %1" : "=r"(rd) : "r"(a));
    return rd;
}

static inline unsigned int rv32_orc_b(unsigned int a) {
    unsigned int rd;
    __asm__ ("orc.b %0, %1" : "=r"(rd) : "r"(a));
    return rd;
}

int main(void) {
    int pass_count = 0;

    int x1 = -2;
    int x2 = 5;

    // 1. andn
    if (rv32_andn(x2, x1) == 0x00000001) pass_count++;

    // 2. orn
    if (rv32_orn(x2, x1) == 0x00000005) pass_count++;

    // 3. xnor
    if (rv32_xnor(x2, x1) == 0x00000004) pass_count++;

    // 4. max
    if (rv32_max(x1, x2) == 5) pass_count++;

    // 5. maxu
    if (rv32_maxu((unsigned int)x1, (unsigned int)x2) == 0xFFFFFFFE) pass_count++;

    // 6. min
    if (rv32_min(x1, x2) == -2) pass_count++;

    // 7. minu
    if (rv32_minu((unsigned int)x1, (unsigned int)x2) == 5) pass_count++;

    int x10 = -1;
    // 8. zext.h
    if (rv32_zext_h((unsigned int)x10) == 0x0000FFFF) pass_count++;

    // 9. sext.h
    if (rv32_sext_h(x10) == -1) pass_count++;

    // 10. sext.b
    if (rv32_sext_b(x10) == -1) pass_count++;

    unsigned int x14 = 0x000000F0;
    // 11. clz
    if (rv32_clz(x14) == 24) pass_count++;

    // 12. ctz
    if (rv32_ctz(x14) == 4) pass_count++;

    // 13. cpop
    if (rv32_cpop(x14) == 4) pass_count++;

    // 14. rol
    if (rv32_rol(x14, (unsigned int)x2) == 0x00001E00) pass_count++;

    // 15. ror
    if (rv32_ror(x14, (unsigned int)x2) == 0x80000007) pass_count++;

    // 16. rori
    if (rv32_rori4(x14) == 0x0000000F) pass_count++;

    // 17. rev8
    if (rv32_rev8(x14) == 0xF0000000) pass_count++;

    // 18. orc.b
    if (rv32_orc_b(x14) == 0x000000FF) pass_count++;

    return pass_count; // Returns 18 on full pass
}
