# Feature 8: Pipelined RV32IMF Processor Core with Passive Performance CSRs

## 1. Overview & Architectural Scope
Feature 8 integrates a complete **Passive Hardware Performance Counters and Control/Status Register (CSR) Subsystem** into the 5-stage pipelined RV32IMF processor core.
- **Microarchitecture Target**: 5-Stage RV32IMF Core running at 50 MHz.
- **Target FPGA**: Digilent Nexys A7-100T (Xilinx Artix-7 XC7A100T-1CSG324C).
- **Core Benefit**: Enables runtime software profiling and microarchitectural observability by providing read-only hardware performance counters accessible via standard RISC-V `csrr` instructions (`CSRRS rd, csr, x0`).

---

## 2. Supported Passive CSR Registers

| CSR Address | Register Name | Description | Width |
|:---:|:---:|:---|:---:|
| `0xC00` | `cycle` | Lower 32 bits of monotonic clock cycle counter | 32-bit |
| `0xC80` | `cycleh` | Upper 32 bits of monotonic clock cycle counter | 32-bit |
| `0xC01` | `time` | Lower 32 bits of real-time timer ticks (mirrors cycle) | 32-bit |
| `0xC81` | `timeh` | Upper 32 bits of real-time timer ticks | 32-bit |
| `0xC02` | `instret` | Lower 32 bits of retired/committed instructions | 32-bit |
| `0xC82` | `instreth` | Upper 32 bits of retired/committed instructions | 32-bit |
| `0xC03` | `hpmcounter3` | Lower 32 bits of pipeline stall cycles (load-use, DIV, FPU) | 32-bit |
| `0xC83` | `hpmcounter3h` | Upper 32 bits of pipeline stall cycles | 32-bit |
| `0xC04` | `hpmcounter4` | Lower 32 bits of branch/jump instructions executed | 32-bit |
| `0xC84` | `hpmcounter4h` | Upper 32 bits of branch/jump instructions executed | 32-bit |
| `0xC05` | `hpmcounter5` | Lower 32 bits of branch mispredictions | 32-bit |
| `0xC85` | `hpmcounter5h` | Upper 32 bits of branch mispredictions | 32-bit |

---

## 3. Student Implementation & Guided `TODO` Sections
Per project specifications, key architectural sections contain guided `TODO` blocks with detailed theory for student self-learning:
1. `modules/stages/csr_perf_counters.v`:
   - **TODO 1**: 64-bit performance counter updates on positive clock edge (`cycle_cnt`, `instret_cnt`, `stall_cnt`, `branch_cnt`, `mispredict_cnt`).
   - **TODO 2**: 12-bit passive CSR address decode multiplexer returning the correct 32-bit slice.
2. `modules/stages/decode_stage.v`:
   - **TODO**: RISC-V SYSTEM opcode (`7'b1110011`) decoding, `reg_write_o` assertion, and 12-bit CSR address extraction (`instruction[31:20]`).
3. `modules/stages/execute_stage.v`:
   - **TODO**: Execution result multiplexer routing `csr_rdata_i` into `alu_result_o`.
4. `modules/pipeline/pipe.v`:
   - Register forwarding multiplexers (`reg_rdata1`, `reg_rdata2`), reset zeroing, and WB stage port connections.

---

## 4. Hardware Verification & FPGA Peripheral Mapping

### 16 Discrete Status LEDs:
- **LED[0]**: Hazard Stall Active (Load-use, DIV, FPU)
- **LED[1]**: Data Forwarding Active (Operand bypass active)
- **LED[2]**: Branch Pipeline Flush (`hazard_flush_id`)
- **LED[3]**: Instruction Writeback Commit (`wb_reg_write`)
- **LED[4]**: Multiplier Unit Active (`mul_active`)
- **LED[5]**: Divider Unit Active (`div_active`)
- **LED[6]**: FPU Unit Active (`fpu_active`)
- **LED[7]**: Program Execution Completed (`prog_done`)
- **LED[8]**: **CSR Instruction Active** (Stretched for visibility)
- **LED[15:9]**: Low bits of return value or committed data

### 8-Digit Seven-Segment Display (Multiplexed via `SW[2:0]`):
- `SW[2:0] = 3'b000`: Fetch PC Address (`pc_if`)
- `SW[2:0] = 3'b001`: Fetched Machine Instruction (`imem_rdata`)
- `SW[2:0] = 3'b010`: CSR `cycle` Counter (`0xC00`)
- `SW[2:0] = 3'b011`: CSR `instret` Counter (`0xC02`)
- `SW[2:0] = 3'b100`: CSR `hpmcounter3` (Stall Cycles `0xC03`)
- `SW[2:0] = 3'b101`: CSR `hpmcounter4` (Branch Count `0xC04`)
- `SW[2:0] = 3'b110`: Final Return Value in `x10` (`a0`)

---

## 5. Verification Commands

### Vivado Simulator:
```bash
cd simulation
make sim_csr       # Runs unit CSR counters testbench (8 assertions)
make sim_pipeline  # Runs full 5-stage pipeline CSR execution testbench
```

### Icarus Verilog (`iverilog`):
```bash
# Unit CSR Testbench
iverilog -I modules -o sim_csr testbench/tb_csr.v modules/stages/csr_perf_counters.v && ./sim_csr

# Full Pipeline Integration Testbench
iverilog -I modules -I modules/stages -I modules/pipeline -I modules/registers \
  -o sim_pipe testbench/tb_feature8_pipeline.v modules/pipeline/pipeline_5stage.v \
  modules/hazard_unit.v modules/stages/*.v modules/registers/*.v && ./sim_pipe
```
