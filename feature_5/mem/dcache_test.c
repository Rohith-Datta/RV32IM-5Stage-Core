// ============================================================================
// File: dcache_test.c
// Description: Compact D-Cache Verification Program (~40 cycles)
// Tests:
//   1. Memory Stores (SW): Writes to array on stack / data memory.
//   2. Compulsory Miss (LW arr[0]): Triggers 10-cycle burst refill of 16B block.
//   3. Spatial Locality Hit (LW arr[1]): Same 16B block, 1-cycle hit (0 stall).
//   4. Temporal Locality Hit (LW arr[0]): Re-reading cached line, 1-cycle hit (0 stall).
// Expected Return Value: 40 (10 + 20 + 10)
// ============================================================================

int main(void) {
    volatile int arr[4];
    arr[0] = 10;
    arr[1] = 20;
    int a = arr[0];
    int b = arr[1];
    int c = arr[0];
    return a + b + c; // Expected return: 40
}
