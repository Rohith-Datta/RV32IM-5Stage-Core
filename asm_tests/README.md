# RISC-V Assembly Test Suite & FPGA Toolchain

This directory contains standalone, hand-crafted RISC-V assembly programs (`.s`) designed for demonstration and verification on the **Pipelined RV32IMF Core** on the **Digilent Nexys A7-100T FPGA**.

---

## 📁 Available Assembly Programs

| File | Architecture | Description | Expected RAM Signature |
|---|---|---|---|
| [`01_basic_arithmetic.s`](file:///Users/siddharthmisro/Documents/RISCV/asm_tests/01_basic_arithmetic.s) | RV32I | Base integer arithmetic, logical operations, shift instructions, comparisons, and loop summation ($1+2+3+4+5=15$). | `0xCAFE0001` at `[0x210]` |
| [`02_pipeline_hazards.s`](file:///Users/siddharthmisro/Documents/RISCV/asm_tests/02_pipeline_hazards.s) | RV32I | Tests RAW EX-to-EX and MEM-to-EX data forwarding, load-use interlock 1-cycle stall, and branch misprediction flushes. | `0xCAFE0002` at `[0x214]` |
| [`03_hardware_multiplier.s`](file:///Users/siddharthmisro/Documents/RISCV/asm_tests/03_hardware_multiplier.s) | RV32IM | Verifies hardware multiplier (`MUL`, `MULH`, `MULHU`) and divider (`DIV`, `DIVU`, `REM`, `REMU`), signed div-by-zero, and signed overflow. | `0xCAFE0003` at `[0x220]` |
| [`04_fpu_special_cases.s`](file:///Users/siddharthmisro/Documents/RISCV/asm_tests/04_fpu_special_cases.s) | RV32IMF | Verifies IEEE-754 FPU (`FADD.S`, `FSUB.S`, `FMUL.S`, `FDIV.S`) plus **all 7 special corner cases** ($\text{div0}$, $-\text{div0}$, $0/0$, $\infty/\infty$, negative division, integer div0, signed overflow). | `0xCAFEFEED` at `[0x22C]` |
| [`05_fpga_io_demo.s`](file:///Users/siddharthmisro/Documents/RISCV/asm_tests/05_fpga_io_demo.s) | RV32I | Visual binary counter with programmable delay loop designed specifically for watching live LED increments and 7-segment display on the Nexys A7 FPGA. | `0xCAFE0005` at `[0x204]` |

---

## 🛠️ Toolchain & Converters (`tools/`)

No heavy external GCC installation is required:
1. **`tools/riscv_as.py`**: A pure-Python assembler that parses RV32IMF assembly (`.s`), resolves labels, produces a valid 32-bit ELF binary (`.elf`), and generates Vivado-compatible `imem.hex` and `dmem.hex`.
2. **`tools/elf2hex.py`**: A pure-Python ELF32 parser that reads standard ELF executable binaries (from GCC or clang) and formats them into Vivado BRAM `$readmemh` memory hex files.
3. **`run_asm.py`**: Unified project manager that compiles assembly, converts ELF, deploys memory files to `feature_4/mem/`, and runs pipeline simulation.

---

## 🚀 How to Assemble and Deploy to FPGA

From the root of the repository:

### 1. List Available Tests
```bash
python3 run_asm.py --list
```

### 2. Assemble and Deploy a Specific Test
```bash
# Example: Assemble and deploy the FPU Special Cases test
python3 run_asm.py 04

# Example: Assemble and deploy the FPGA Visual Counter demo
python3 run_asm.py 05
```

### 3. Assemble and Immediately Run Pipeline Simulation
```bash
python3 run_asm.py 04 --sim
```

### 4. Convert Any Existing External `.elf` Binary
```bash
python3 run_asm.py --elf path/to/external.elf
```

Once deployed, open Vivado ([`feature_4/open_vivado.bat`](file:///Users/siddharthmisro/Documents/RISCV/feature_4/open_vivado.bat)) and generate the bitstream or run simulation directly.
