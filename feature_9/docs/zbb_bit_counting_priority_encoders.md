# RISC-V Zbb Bit Counting (CLZ, CTZ, CPOP) Hardware Datapath

## Implementations
1. **`clz` (Count Leading Zeros)**: 32-bit hierarchical priority encoder detects highest set bit position.
2. **`ctz` (Count Trailing Zeros)**: Evaluated as `clz(bit_reverse(rs1))` or dual-direction encoder.
3. **`cpop` (Count Population)**: 4-stage Wallace-tree style adder tree summing set bits in 1 cycle.
