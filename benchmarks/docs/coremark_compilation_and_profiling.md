# CoreMark Benchmark Compilation & Hardware Profiling

## Compilation Settings
- **Toolchain**: `riscv32-unknown-elf-gcc` (RV32IMF architecture, ILP32 ABI).
- **Optimization Flags**: `-O3 -fno-common -funroll-loops`.
- **Target Memory**: 8 KB Instruction Memory, 8 KB Data Memory.

### Profiling Results on FPGA (50 MHz)
- **CoreMark Score**: 1.84 CoreMark/MHz.
- **Hardware Acceleration Benefit**: Hardware divider and multiplier reduce math-heavy loop iterations by $4.2\times$ compared to software emulation routines.
