// ============================================================================
// File: icache.c
// Description: Simple Bare-Metal C Test for L1 Instruction Cache Verification
//              Clean, understandable arithmetic test like addition.c
// ============================================================================

int main(void) {
    register int a asm("x11") = 12;
    register int b asm("x12") = 25;
    return a + b; // Expected return: 37 (0x25)
}
