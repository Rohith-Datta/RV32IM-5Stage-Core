// ============================================================================
// File: fpu.c
// Description: Bare-Metal Verification Test for RV32IMF Core
// Exercises:
//   1. FADD.S : 1.5f + 2.5f = 4.0f (0x40800000) [5-cycle latency, 4-cycle stall]
//   2. FMUL.S : 4.0f * 2.0f = 8.0f (0x41000000) [4-cycle latency, 3-cycle stall, RAW fwd]
//   3. FSUB.S : 8.0f - 2.5f = 5.5f (0x40B00000) [5-cycle latency, 4-cycle stall, RAW fwd]
//   4. FDIV.S : 10.0f / 2.0f = 5.0f (0x40A00000) [15-cycle latency, 14-cycle stall]
//   5. MUL    : 6 * 7 = 42 (RV32M Hardware Multiplier)
//   6. DIV    : 100 / 7 = 14 (RV32M Hardware 32-Cycle Restoring Divider)
// Returns: 60 (0x3C) in register a0 (x10) if all 6 tests pass (10 points each).
// ============================================================================

// --- IEEE 754 Single-Precision Floating-Point Instructions (RV32F) ---
static inline unsigned int __attribute__((always_inline)) fadd_s(unsigned int a, unsigned int b) {
    unsigned int res;
    __asm__ volatile (".insn r 0x53, 0, 0x00, %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    return res;
}

static inline unsigned int __attribute__((always_inline)) fsub_s(unsigned int a, unsigned int b) {
    unsigned int res;
    __asm__ volatile (".insn r 0x53, 0, 0x04, %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    return res;
}

static inline unsigned int __attribute__((always_inline)) fmul_s(unsigned int a, unsigned int b) {
    unsigned int res;
    __asm__ volatile (".insn r 0x53, 0, 0x08, %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    return res;
}

static inline unsigned int __attribute__((always_inline)) fdiv_s(unsigned int a, unsigned int b) {
    unsigned int res;
    __asm__ volatile (".insn r 0x53, 0, 0x0C, %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    return res;
}

// --- Hardware Integer Arithmetic Instructions (RV32M) ---
static inline int __attribute__((always_inline)) mul_i(int a, int b) {
    int res;
    __asm__ volatile ("mul %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    return res;
}

static inline int __attribute__((always_inline)) div_i(int a, int b) {
    int res;
    __asm__ volatile ("div %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    return res;
}

int main(void) {
    // ------------------------------------------------------------------------
    // 1. Floating-Point Operands (IEEE 754 bit representations)
    // ------------------------------------------------------------------------
    unsigned int x = 0x3FC00000; // 1.5f
    unsigned int y = 0x40200000; // 2.5f
    unsigned int z = 0x40000000; // 2.0f
    unsigned int w = 0x41200000; // 10.0f

    // 1. FADD.S : 1.5f + 2.5f = 4.0f (0x40800000) [5-cycle stall interlock]
    unsigned int r_add = fadd_s(x, y);

    // 2. FMUL.S : 4.0f * 2.0f = 8.0f (0x41000000) [4-cycle latency, RAW forward from r_add]
    unsigned int r_mul = fmul_s(r_add, z);

    // 3. FSUB.S : 8.0f - 2.5f = 5.5f (0x40B00000) [5-cycle latency, RAW forward from r_mul]
    unsigned int r_sub = fsub_s(r_mul, y);

    // 4. FDIV.S : 10.0f / 2.0f = 5.0f (0x40A00000) [15-cycle multi-cycle stall interlock]
    unsigned int r_div = fdiv_s(w, z);

    // ------------------------------------------------------------------------
    // 2. Hardware Integer Multiplication & Division (RV32M Instructions)
    // ------------------------------------------------------------------------
    volatile int val_a = 6;
    volatile int val_b = 7;
    volatile int val_c = 100;

    int r_imul = mul_i(val_a, val_b); // Hardware MUL: 6 * 7 = 42
    int r_idiv = div_i(val_c, val_b); // Hardware DIV: 100 / 7 = 14

    // ------------------------------------------------------------------------
    // 3. Verify all 6 operations produced exact results (10 points each)
    // ------------------------------------------------------------------------
    int score = 0;
    if (r_add  == 0x40800000) score += 10; // FADD.S passed (+10)
    if (r_mul  == 0x41000000) score += 10; // FMUL.S passed (+10)
    if (r_sub  == 0x40B00000) score += 10; // FSUB.S passed (+10)
    if (r_div  == 0x40A00000) score += 10; // FDIV.S passed (+10)
    if (r_imul == 42)         score += 10; // MUL passed (+10)
    if (r_idiv == 14)         score += 10; // DIV passed (+10)

    return score; // Returns 60 (0x3C)
}
