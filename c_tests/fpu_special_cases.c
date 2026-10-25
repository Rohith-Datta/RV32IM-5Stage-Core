// ==============================================================================
// Bare-Metal C Program: IEEE-754 FPU & Arithmetic Special/Corner Cases
// Designed for Pipelined RV32IMF Core Demonstration on Nexys A7 FPGA
// ==============================================================================

// Inline assembly wrappers to directly issue RV32F hardware instructions
static inline float fadd_s(float a, float b) {
    float res;
    asm volatile ("fadd.s %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    return res;
}

static inline float fsub_s(float a, float b) {
    float res;
    asm volatile ("fsub.s %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    return res;
}

static inline float fmul_s(float a, float b) {
    float res;
    asm volatile ("fmul.s %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    return res;
}

// 15-cycle Newton-Raphson Hardware Divider
static inline float fdiv_s(float a, float b) {
    float res;
    asm volatile ("fdiv.s %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    return res;
}

// Helper to convert float bit-pattern to unsigned int without soft-float conversion
static inline unsigned int float_to_bits(float f) {
    union { float f; unsigned int u; } conv;
    conv.f = f;
    return conv.u;
}

static inline float bits_to_float(unsigned int u) {
    union { float f; unsigned int u; } conv;
    conv.u = u;
    return conv.f;
}

int main(void) {
    // -------------------------------------------------------------------------
    // 1. Standard Arithmetic Operations
    // -------------------------------------------------------------------------
    float a = 1.5f; // 0x3FC00000
    float b = 2.5f; // 0x40200000
    float c = 2.0f; // 0x40000000
    float d = 7.0f; // 0x40E00000

    float r_add = fadd_s(a, b); // 1.5 + 2.5 = 4.0f (0x40800000)
    float r_sub = fsub_s(r_add, a); // 4.0 - 1.5 = 2.5f (0x40200000)
    float r_mul = fmul_s(c, b); // 2.0 * 2.5 = 5.0f (0x40A00000)
    float r_div = fdiv_s(d, c); // 7.0 / 2.0 = 3.5f (0x40600000 via Newton-Raphson)

    // -------------------------------------------------------------------------
    // 2. Special Case 1: Division by Zero (x / 0.0) -> +Infinity (0x7F800000)
    // -------------------------------------------------------------------------
    float zero = 0.0f;
    float r_div_zero = fdiv_s(c, zero); // 2.0 / 0.0 -> +Inf (0x7F800000)

    // -------------------------------------------------------------------------
    // 3. Special Case 2: Negative Div by Zero (-x / 0.0) -> -Infinity (0xFF800000)
    // -------------------------------------------------------------------------
    float neg_two = bits_to_float(0xC0000000); // -2.0f
    float r_neg_div_zero = fdiv_s(neg_two, zero); // -2.0 / 0.0 -> -Inf (0xFF800000)

    // -------------------------------------------------------------------------
    // 4. Special Case 3: Zero divided by Zero (0.0 / 0.0) -> NaN (0x7FC00000)
    // -------------------------------------------------------------------------
    float r_zero_div_zero = fdiv_s(zero, zero); // 0.0 / 0.0 -> qNaN (0x7FC00000)

    // -------------------------------------------------------------------------
    // 5. Special Case 4: Infinity divided by Infinity -> NaN (0x7FC00000)
    // -------------------------------------------------------------------------
    float pos_inf = bits_to_float(0x7F800000); // +Inf
    float r_inf_div_inf = fdiv_s(pos_inf, pos_inf); // Inf / Inf -> qNaN (0x7FC00000)

    // -------------------------------------------------------------------------
    // 6. Special Case 5: Negative Float Division with Sign Preservation
    // -------------------------------------------------------------------------
    float neg_six = bits_to_float(0xC0C00000); // -6.0f
    float r_neg_div = fdiv_s(neg_six, c); // -6.0 / 2.0 = -3.0f (0xC0400000)

    // -------------------------------------------------------------------------
    // 7. Special Case 6: Integer Hardware Division by Zero (10 / 0)
    //    RISC-V spec specifies: x / 0 = -1 (0xFFFFFFFF), remainder = x (10)
    // -------------------------------------------------------------------------
    int int_ten = 10;
    int int_zero = 0;
    int int_div_zero = int_ten / int_zero; // Expected: -1 (0xFFFFFFFF)

    // -------------------------------------------------------------------------
    // 8. Special Case 7: Integer Signed Overflow (INT_MIN / -1)
    //    -2147483648 / -1 -> overflow produces -2147483648 (0x80000000)
    // -------------------------------------------------------------------------
    int int_min = 0x80000000;
    int int_neg_one = -1;
    int int_overflow = int_min / int_neg_one; // Expected: 0x80000000

    // Store test results to designated memory area (RAM offset 0x200 / word 128)
    volatile unsigned int* mem_out = (volatile unsigned int*) 0x00000200;
    mem_out[0] = float_to_bits(r_add);          // 0x40800000 (4.0f)
    mem_out[1] = float_to_bits(r_sub);          // 0x40200000 (2.5f)
    mem_out[2] = float_to_bits(r_mul);          // 0x40A00000 (5.0f)
    mem_out[3] = float_to_bits(r_div);          // 0x40600000 (3.5f)
    mem_out[4] = float_to_bits(r_div_zero);     // 0x7F800000 (+Inf)
    mem_out[5] = float_to_bits(r_neg_div_zero); // 0xFF800000 (-Inf)
    mem_out[6] = float_to_bits(r_zero_div_zero);// 0x7FC00000 (NaN)
    mem_out[7] = float_to_bits(r_inf_div_inf);  // 0x7FC00000 (NaN)
    mem_out[8] = float_to_bits(r_neg_div);      // 0xC0400000 (-3.0f)
    mem_out[9] = (unsigned int)int_div_zero;    // 0xFFFFFFFF (-1)
    mem_out[10]= (unsigned int)int_overflow;    // 0x80000000 (INT_MIN)

    // Completion signature: 0xCAFEFEED indicates all tests passed successfully!
    mem_out[11]= 0xCAFEFEED;

    return 0;
}
