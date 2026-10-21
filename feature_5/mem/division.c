// ============================================================================
// File: division.c
// Description: Optimized Bare-Metal Verification for RV32M Hardware Divider
// Project: Pipelined RV32IM RISC-V Processor (Feature 3: Hardware Divider)
// Target Execution Latency: ~60 Clock Cycles
//
// Verification Coverage:
//   1. Standard Division: 100 / 7 = 14 (32-cycle hardware stall)
//   2. Edge Case: Divide-by-Zero (100 / 0) -> Returns -1 (1-cycle early exit)
//   3. Edge Case: Remainder-by-Zero (100 % 0) -> Returns 100 (1-cycle early exit)
//   4. Edge Case: Signed Overflow (INT_MIN / -1) -> Returns INT_MIN (1-cycle early exit)
//   5. Edge Case: Signed Overflow Remainder (INT_MIN % -1) -> Returns 0 (1-cycle early exit)
//
// Expected Return Value in a0: 16 (0x00000010)
// ============================================================================

int __attribute__((naked)) main(void) {
    asm volatile (
        "li   t0, 100\n"
        "li   t1, 7\n"
        "div  t2, t0, t1\n"         // 1. Standard Division: 100 / 7 = 14 (32-cycle hardware stall)
        "div  t3, t0, zero\n"       // 2. Edge Case 1: Divide-by-Zero (100 / 0 = -1, 1-cycle early exit)
        "rem  t4, t0, zero\n"       // 3. Edge Case 2: Remainder-by-Zero (100 % 0 = 100, 1-cycle early exit)
        "lui  t5, 0x80000\n"        // 0x80000000 (INT_MIN)
        "li   t6, -1\n"
        "div  a1, t5, t6\n"         // 4. Edge Case 3: Signed Overflow (INT_MIN / -1 = INT_MIN, 1-cycle early exit)
        "rem  a2, t5, t6\n"         // 5. Edge Case 4: Signed Overflow Remainder (INT_MIN % -1 = 0, 1-cycle early exit)
        // Verify all 5 results branchlessly
        "xori t2, t2, 14\n"
        "addi t3, t3, 1\n"
        "xori t4, t4, 100\n"
        "xor  a1, a1, t5\n"
        "or   t2, t2, t3\n"
        "or   t4, t4, a1\n"
        "or   t2, t2, t4\n"
        "or   t2, t2, a2\n"         // t2 == 0 if all 5 test cases passed
        "bnez t2, 1f\n"
        "li   a0, 16\n"             // Pass: return 16 (0x10)
        "ret\n"
        "1:\n"
        "li   a0, 255\n"            // Fail: return 255
        "ret\n"
    );
}
