# Block Diagram Report

**Project Title:** Design and FPGA Implementation of a Pipelined RV32IMF Processor Core with L1 Cache Hierarchy, Branch Prediction, and Hardware Math Accelerators  
**Group Number:** Group 13  
**Target Device:** Xilinx Artix-7 XC7A100T-1CSG324C (Digilent Nexys A7-100T FPGA)  
**Authors / Team Members:**
- Pisini Ramana (`thisispisiniramana`)
- Chimbili Sahithi (`chimbilisahithi`)
- Siddharth Misro (`sidmisro`)
- Bandaru Rohith Datta (`Rohith-Datta`)
- Sigilipelli Praneeth Sai Bharath (`praneethsaibharath`)

---

## 1. Top-Level Hardware Block Diagram

The complete top-level hardware block diagram for the Group 13 Extended RV32IMF 5-stage pipelined processor core is illustrated below in comprehensive ASCII schematic form and structural Mermaid dataflow form. All 5 pipeline stages (**IF**, **ID**, **EX**, **MEM**, **WB**), 4 pipeline register sets (**IF/ID**, **ID/EX**, **EX/MEM**, **MEM/WB**), global clock/reset distribution, complete signal names, bit widths, control buses, hazard interlocks, and the 9 integrated feature modules are fully delineated.

An interactive, high-resolution vector visualizer is available in [block_diagram_visualizer.html](file:///c:/CS2202L/RISCV/block_diagram_visualizer.html).

### Arithmetic Units Implementation Specification

| Instruction / Unit | Clock Cycles | Hardware Implementation Method |
|---|:---:|---|
| **MUL (Integer)** | **1** | Direct combinational execution utilizing FPGA DSP Slices. |
| **FMUL.S (Float)** | **4** | Multi-cycle FSM utilizing DSP Slices for 24-bit mantissa multiplication. |
| **FADD.S (Float)** | **5** | Multi-cycle FSM using Standard Logic (LUTs, Adders, Shifters). *No DSP slices.* |
| **FSUB.S (Float)** | **5** | Multi-cycle FSM using Standard Logic (inverts sign bit, shares FADD hardware). *No DSP slices.* |
| **FDIV.S (Float)\*** | **15** | Newton-Raphson Algorithm utilizing DSP Slices (for iterative multiplication) and BRAM (for initial guess lookup). |
| **DIV (Integer)** | **32** | Shift-and-Subtract state machine using Standard Logic (LUTs and Registers). *No DSP slices.* |

### Comprehensive Hardware Architecture ASCII Schematic

```text
===================================================================================================================================================================================
                                              TOP-LEVEL HARDWARE BLOCK DIAGRAM: EXTENDED RV32IMF 5-STAGE PIPELINED CORE
===================================================================================================================================================================================

===================================================================================================================================================================================
 GLOBAL CLOCK & SYNCHRONOUS ACTIVE-LOW RESET DISTRIBUTION BUS:
   clk     (100 MHz) --------+--------------------+---------------------+--------------------+--------------------+--------------------+--------------------+----------------->
                             |                    |                     |                    |                    |                    |                    |
   reset_n (Active-Low) -----+--------------------+---------------------+--------------------+--------------------+--------------------+--------------------+----------------->
                             |                    |                     |                    |                    |                    |                    |
                             v                    v                     v                    v                    v                    v                    v
                        +---------+          +---------+           +---------+          +---------+          +---------+          +---------+          +---------+
                        | PC Reg  |          |  IF/ID  |           | RegFile |          |  ID/EX  |          | DIV/FPU |          | EX/MEM  |          | D-Cache |  (and MEM/WB,
                        | & Caches|          |   Reg   |           | & BTB   |          |   Reg   |          | Modules |          |   Reg   |          | & CSRs) |   Reg, CSRs)
===================================================================================================================================================================================

   STAGE 1: INSTRUCTION FETCH (IF)                                                STAGE 2: INSTRUCTION DECODE (ID)
  --------------------------------------------------                             -----------------------------------------------------------------------------
                                                                                                                              +------------------------------+
  +------------------------------------------------+                                                                          |    CONTROL UNIT              |
  | Feature 7: Static 32-Entry Branch Target Buffer|                                                                          |    (Opcode / Funct3 / Funct7)|
  | - Tag Array: 32 entries [31:7]                 |                                                                          +------------------------------+
  | - Target Cache: [31:0]                         |                                                                                         |
  +------------------------------------------------+                                                                                         | Control Buses
           | pc[31:0]            ^ [update_pc, target,                                                                                       v
           v                     |  actual_taken from EX]                                                 +----------------------------------------------------------+
     [btb_hit, btb_target[31:0]] |                                                                        | Control Lines Generated:                                 |
           |                     |                                                                        | - EX  : ALUSrcA, ALUSrcB, ALUOp[3:0], Branch, Jump       |
           v                     |                                                                        | - Math: is_mul, is_div, is_fpu, is_zbb                     |
      +----------+               |                                                                        | - MEM : MemRead, MemWrite                                |
  +-->|00: pc+4  |               |                                                                        | - WB  : RegWrite, MemToReg[1:0], is_csr                  |
  +-->|01: btb   |               |                                                                        +----------------------------------------------------------+
  +-->|10: branch|               |                                                                                                   |
  +-->|11: jalr  |               |                                                                                                   v
      +----------+               |                                                  instr[31:0]                              [ Control Signals ]
           | pc_next[31:0]       |                                                       |                                                   |
           v                     |                       +-------------------------------+-------------------------------+                   |
     +-----------+               |                       | instr[19:15]  | instr[24:20]  | instr[31:0]   | instr[11:7]   |                   |
     |  PC Reg   |               |                       v rs1[4:0]      v rs2[4:0]      v               v rd[4:0]       v                   |
     |  [31:0]   |               |                   +-------------------------------+ +---------------+ |             +-------------------+ |
     +-----------+               |                   | Register File (x0 - x31)      | | Immediate     | |             | HAZARD DETECTION  | |
       |       |                 |                   | - Dual 32-bit Read Ports      | | Generator     | |             | UNIT              | |
       |       | pc[31:0]        |                   | - Single 32-bit Write Port    | | (I,S,B,U,J)   | |             +-------------------+ |
       |       +---------------+ |                   +-------------------------------+ +---------------+ |               | Inputs:           | |
       v                       | |                      | rdata1[31:0]  | rdata2[31:0]   | imm[31:0]     |               | - id_rs1, id_rs2  | |
  +---------+                  v |                      v               v                v               |               | - id_ex_rd, mem_rd| |
  | Add (+4)|    +-------------------------------+      |               |                |               |               | - div_busy        | |
  +---------+    | Feature 3: L1 I-Cache         |      |               |                |               |               | - fpu_busy        | |
       |         | - 2 KB Direct-Mapped (16B L)  |      |               |                |               |               | - icache_stall    | |
       | pc+4    | - 1-Cycle Hit SRAM            |      |               |                |               |               | - dcache_stall    | |
       | [31:0]  | - Burst Refill FSM to Memory  |      |               |                |               |               | - branch_taken    | |
       |         +-------------------------------+      |               |                |               |               +-------------------+ |
       |               | instr[31:0]   | icache_stall   |               |                |               |                 | Outputs:          |
       |               v               v                |               |                |               |                 | - pc_stall        |
       |               |         (to Hazard Unit)       |               |                |               |                 | - if_id_stall     |
       |               |                                |               |                |               |                 | - id_ex_flush     |
       |               |                                |               |                |               |                 | - if_id_flush     |
       |               |                                |               |                |               |                 v                   v
=======v===============v================================v===============v================v===============v=================[ ID/EX PIPELINE REGISTER ]======
  [ IF/ID PIPELINE REGISTER ]                           | rs1_data      | rs2_data       | imm           | rd              | Control Flags     |
  - pc[31:0]                                            | [31:0]        | [31:0]         | [31:0]        | [4:0]           | (EX, MEM, WB)     |
  - pc_plus_4[31:0]                                     +-------+-------+--------+-------+-------+-------+--------+--------+---------+---------+
  - instr[31:0]                                                 |                |               |                |                  |
  Controls: clk, reset_n, ~if_id_stall, if_id_flush             |                |               |                |                  |
================================================================|================|===============|================|==================|=================

   STAGE 3: EXECUTE (EX)
  -----------------------------------------------------------------------------------------------------------------------------------------------------
                           ForwardA [1:0]                               ForwardB [1:0]
                                 |                                            |
                                 v                                            v
                         +---------------+                            +---------------+
                         | Forward Mux A |                            | Forward Mux B |<--------+ [mem_wdata to EX/MEM]
                         | (3-to-1, 32b) |                            | (3-to-1, 32b) |         |
                         +---------------+                            +---------------+         |
                           | op_a_fwd[31:0]                             | op_b_fwd[31:0]        |
               +-----------+-----------+                     +----------+-----------+-----------+
               |                       |                     |                      |
               v                       v                     v                      v
        +-------------+         +-------------+       +-------------+        +-------------+
        | ALUSrcA Mux |         | ALU_A Bus   |       | ALUSrcB Mux |        | ALU_B Bus   |
        | (0:rs1,1:pc)|         | [31:0]      |       | (0:rs2,1:imm|        | [31:0]      |
        +-------------+         +-------------+       +-------------+        +-------------+
               |                       |                     |                      |
               v alu_in_a              |                     v alu_in_b             |
       +-------------------------------+                     +----------------------+
       |
       |  ======================== PARALLEL HARDWARE EXECUTION UNITS ========================
       |
       +---> [1] BASE ALU (RV32I) : ADD, SUB, SLT, SLTU, XOR, OR, AND, SLL, SRL, SRA ------> base_alu_out[31:0] ------+
       |                                                                                                              |
       +---> [2] FEATURE 2: HARDWARE MULTIPLIER (Artix-7 DSP48E1 / Booth) --------------------> mul_out[31:0] ----------+
       |         Instructions: MUL, MULH, MULHSU, MULHU (1-Cycle Latency via DSP Slices)                              |
       |                                                                                                              |
       +---> [3] FEATURE 5: HARDWARE DIVIDER (32-Cycle Shift-and-Subtract Standard Logic) ----> div_out[31:0] ----------+
       |         Instructions: DIV, DIVU, REM, REMU (32 cycles, div_busy handshaking)           [div_busy to Hazard]   |
       |                                                                                                              |
       +---> [4] FEATURE 4: IEEE 754 SINGLE-PRECISION FPU (FMUL 4c, FADD/SUB 5c, FDIV 15c) ---> fpu_out[31:0] ----------+
       |         Instructions: FADD.S, FSUB.S, FMUL.S, FDIV.S (fpu_busy handshaking)            [fpu_busy to Hazard]   |
       |                                                                                                              |
       +---> [5] FEATURE 9: BIT-MANIPULATION UNIT (Zbb Extension) --------------------------> zbb_out[31:0] ----------+
       |         Instructions: CLZ, CTZ, CPOP, MIN/MAX, SEXT, ANDN, ORN, XNOR, ROL/ROR                                |
       |                                                                                                              |
       +---> [6] LINK ADDRESS RETURN BUS : pass-through of id_ex_pc_plus_4[31:0] -----------> pc_plus_4[31:0] --------+
                                                                                                                      |
                                                                                                                      v
                                                                                                        +----------------------------+
                                                                                                        | EX RESULT MULTIPLEXER      |
                                                                                                        | (6-to-1, 32-bit Output)    |
                                                                                                        +----------------------------+
                                                                                                                      | ex_result[31:0]
       +--------------------------------------------------------------------------------------------------------------+
       |
       v
  +-----------------------------------------------------------------------------------+
  | BRANCH & JUMP EVALUATION UNIT (EX Stage)                                          |
  | - Target Adder 1: id_ex_pc + id_ex_imm                                            |======> actual_target[31:0] (Feedback to IF PC Mux)
  | - Target Adder 2: (op_a_fwd + id_ex_imm) & ~1 (for JALR)                          |
  | - Condition Comparator: BEQ, BNE, BLT, BGE, BLTU, BGEU                            |======> branch_taken / mispredict (to IF & Hazard)
  +-----------------------------------------------------------------------------------+

=======================================================================================================================================================
 [ EX/MEM PIPELINE REGISTER ]
 - pc_plus_4[31:0]               - ex_result[31:0] (dmem_addr)
 - mem_wdata[31:0]               - rd[4:0], funct3[2:0]
 - Control Signals               : RegWrite, MemRead, MemWrite, MemToReg[1:0], is_csr
 Controls: clk, reset_n, enable ~dcache_stall
=======================================================================================================================================================

   STAGE 4: MEMORY ACCESS (MEM)                                                   STAGE 5: WRITEBACK (WB)
  -------------------------------------------------------------                  ------------------------------------------------------
                           ex_result[31:0] (dmem_addr)
                                 |
        +------------------------+-----------------------------+
        |                                                      |
        v                                                      |
  +----------------------------------------------------+       |
  | STORE BYTE-ENABLE GENERATOR                        |       |
  | Funct3 (SB, SH, SW) + addr[1:0] -> dmem_wstrb[3:0] |       |
  +----------------------------------------------------+       |
        | dmem_wstrb[3:0]                                      |
        v                                                      |
  +----------------------------------------------------+       |
  | FEATURE 6: L1 DATA CACHE (Direct-Mapped, 2 KB)     |       |
  | - Tag SRAM Array & 16B Line Data BRAMs             |       |
  | - Write-Through Policy with Write Buffer           |       |
  | - Memory Refill Bus (Burst 128-bit) to BRAM/DDR    |       |
  +----------------------------------------------------+       |
        | raw_rdata[31:0]         | dcache_stall               |
        v                         v (to Hazard Unit)           |
  +---------------------------+                                |
  | LOAD SIGN/ZERO EXTENDER   |                                |
  | LB, LBU, LH, LHU, LW      |                                |
  +---------------------------+                                |
        | formatted_rdata[31:0]                                |
        |                                                      |
        v                                                      v
=======================================================================================================================================================
 [ MEM/WB PIPELINE REGISTER ]
 - pc_plus_4[31:0]               - formatted_mem_data[31:0]
 - ex_result[31:0]               - csr_rdata[31:0]
 - rd[4:0]                       - Control: RegWrite, MemToReg[1:0]
 Controls: clk, reset_n
=======================================================================================================================================================
                                                                                        |             |               |              |
                                                                                        v             v               v              v
                                                                                 +-----------------------------------------------------------+
                                                                                 | FEATURE 8: PERFORMANCE COUNTERS (Passive CSRs)            |
                                                                                 | CSR Addresses: 0xC00(CYCLE), 0xC02(INSTRET), 0xC80-0xC82  |
                                                                                 | Profiling: cycle[63:0], instret[63:0], stalls, misses     |
                                                                                 +-----------------------------------------------------------+
                                                                                                              | csr_rdata[31:0]
                                                                                                              v
                                                                                               +------------------------------+
                                                                                               | WRITEBACK MULTIPLEXER (4:1)  |
                                                                                               | Select: MemToReg[1:0]        |
                                                                                               | - 00: ex_result[31:0]        |
                                                                                               | - 01: mem_data[31:0]         |
                                                                                               | - 10: pc_plus_4[31:0]        |
                                                                                               | - 11: csr_rdata[31:0]        |
                                                                                               +------------------------------+
                                                                                                              | wb_data[31:0]
                                                                                                              v
=======================================================================================================================================================
 FEEDBACK BYPASS & RETIREMENT BUSES:
 1. Writeback to RegFile : wb_data[31:0], mem_wb_rd[4:0], mem_wb_regwrite -----------------------------------------------------> [RegFile wdata/waddr/we in ID]
 2. EX/MEM Forward Bus   : Distance-1 Forwarding [ex_mem_result, ex_mem_rd, ex_mem_regwrite] ------------------------------------> [Forward Muxes in EX Stage]
 3. MEM/WB Forward Bus   : Distance-2 Forwarding [wb_data, mem_wb_rd, mem_wb_regwrite] -----------------------------------------> [Forward Muxes in EX Stage]
=======================================================================================================================================================
```

---

### Structural Pipeline Flow Diagram (Mermaid)

```mermaid
flowchart TD
    %% Global Network
    subgraph CLK_TREE ["Global Clock & Reset Distribution Bus"]
        CLK["clk: 100 MHz Master Oscillator"]
        RST["reset_n: Synchronous Active-Low Reset"]
    end

    %% STAGE 1: IF
    subgraph STAGE_IF ["Stage 1: Instruction Fetch (IF)"]
        direction TB
        PCMUX{"PC Multiplexer (4:1)"}
        PCREG["PC Register [31:0]"]
        ADD4["Adder (+4)"]
        ICACHE["Feature 3: L1 I-Cache (2 KB Direct-Mapped)"]
        BTB["Feature 7: Static 32-Entry BTB"]
    end

    %% IF/ID Register
    subgraph REG_IF_ID ["IF / ID Pipeline Register"]
        IF_ID_PC["pc [31:0]"]
        IF_ID_PC4["pc_plus_4 [31:0]"]
        IF_ID_INSTR["instr [31:0]"]
    end

    %% STAGE 2: ID
    subgraph STAGE_ID ["Stage 2: Instruction Decode (ID)"]
        direction TB
        CTRL["Control Unit (Opcode/Funct3/Funct7)"]
        RF["Register File (32 x 32-bit x0-x31)"]
        IMMGEN["Immediate Generator (I/S/B/U/J)"]
        HAZARD["Hazard Detection Unit"]
    end

    %% ID/EX Register
    subgraph REG_ID_EX ["ID / EX Pipeline Register"]
        ID_EX_DATA["pc, pc_plus_4, rs1_data, rs2_data, imm [31:0], rs1, rs2, rd [4:0]"]
        ID_EX_CTRL["RegWrite, MemRead, MemWrite, MemToReg, ALUSrc, ALUOp, Math flags"]
    end

    %% STAGE 3: EX
    subgraph STAGE_EX ["Stage 3: Execute (EX)"]
        direction TB
        FWD_UNIT["Forwarding Unit"]
        MUXA{"Forward Mux A (3:1)"}
        MUXB{"Forward Mux B (3:1)"}
        ALU_SRCA{"ALUSrcA Mux"}
        ALU_SRCB{"ALUSrcB Mux"}
        BASE_ALU["Base ALU (RV32I)"]
        F2_MUL["Feature 2: Radix-4 Booth Multiplier"]
        F5_DIV["Feature 5: Radix-2 Non-Restoring Divider"]
        F4_FPU["Feature 4: IEEE 754 Single-Precision FPU"]
        F9_ZBB["Feature 9: Bit-Manipulation Unit (Zbb)"]
        BRANCH_UNIT["Branch & Jump Evaluation Unit"]
        EX_MUX{"EX Result Multiplexer (6:1)"}
    end

    %% EX/MEM Register
    subgraph REG_EX_MEM ["EX / MEM Pipeline Register"]
        EX_MEM_DATA["pc_plus_4 [31:0], ex_result [31:0], mem_wdata [31:0], rd [4:0]"]
        EX_MEM_CTRL["RegWrite, MemRead, MemWrite, MemToReg [1:0], is_csr"]
    end

    %% STAGE 4: MEM
    subgraph STAGE_MEM ["Stage 4: Memory Access (MEM)"]
        direction TB
        STRB_GEN["Store Byte-Enable Generator"]
        DCACHE["Feature 6: L1 D-Cache (2 KB Direct-Mapped)"]
        LOAD_EXT["Load Sign/Zero Extender & Formatter"]
    end

    %% MEM/WB Register
    subgraph REG_MEM_WB ["MEM / WB Pipeline Register"]
        MEM_WB_DATA["pc_plus_4 [31:0], ex_result [31:0], mem_rdata [31:0], rd [4:0]"]
        MEM_WB_CTRL["RegWrite, MemToReg [1:0]"]
    end

    %% STAGE 5: WB
    subgraph STAGE_WB ["Stage 5: Writeback (WB)"]
        direction TB
        CSR_PERF["Feature 8: Passive Performance CSRs"]
        WB_MUX{"Writeback Multiplexer (4:1)"}
    end

    %% Connections
    PCMUX -->|"pc_next [31:0]"| PCREG
    PCREG -->|"pc [31:0]"| ADD4
    PCREG -->|"pc [31:0]"| ICACHE
    PCREG -->|"pc [31:0]"| BTB
    ADD4 -->|"pc_plus_4 [31:0]"| PCMUX
    BTB -->|"btb_target [31:0] (on btb_hit)"| PCMUX

    ADD4 --> IF_ID_PC4
    PCREG --> IF_ID_PC
    ICACHE -->|"instr [31:0]"| IF_ID_INSTR

    IF_ID_INSTR -->|"opcode [6:0], funct3 [2:0], funct7 [6:0]"| CTRL
    IF_ID_INSTR -->|"rs1 [4:0]"| RF
    IF_ID_INSTR -->|"rs2 [4:0]"| RF
    IF_ID_INSTR -->|"instr [31:0]"| IMMGEN
    IF_ID_INSTR -->|"rs1 [4:0], rs2 [4:0]"| HAZARD

    CTRL --> ID_EX_CTRL
    RF -->|"rs1_data [31:0], rs2_data [31:0]"| ID_EX_DATA
    IMMGEN -->|"imm [31:0]"| ID_EX_DATA

    REG_ID_EX --> MUXA
    REG_ID_EX --> MUXB
    FWD_UNIT -->|"forward_a [1:0]"| MUXA
    FWD_UNIT -->|"forward_b [1:0]"| MUXB

    MUXA -->|"op_a_fwd [31:0]"| ALU_SRCA
    MUXB -->|"op_b_fwd [31:0]"| ALU_SRCB

    ALU_SRCA --> BASE_ALU
    ALU_SRCB --> BASE_ALU
    MUXA --> F2_MUL
    MUXB --> F2_MUL
    MUXA --> F5_DIV
    MUXB --> F5_DIV
    MUXA --> F4_FPU
    MUXB --> F4_FPU
    MUXA --> F9_ZBB
    MUXB --> F9_ZBB
    MUXA --> BRANCH_UNIT
    MUXB --> BRANCH_UNIT

    BASE_ALU --> EX_MUX
    F2_MUL -->|"mul_out [31:0]"| EX_MUX
    F5_DIV -->|"div_out [31:0]"| EX_MUX
    F4_FPU -->|"fpu_out [31:0]"| EX_MUX
    F9_ZBB -->|"zbb_out [31:0]"| EX_MUX

    F5_DIV -.->|"div_busy (32-cycle hold)"| HAZARD
    F4_FPU -.->|"fpu_busy"| HAZARD
    ICACHE -.->|"icache_stall"| HAZARD
    DCACHE -.->|"dcache_stall"| HAZARD

    BRANCH_UNIT -->|"actual_target [31:0]"| PCMUX
    BRANCH_UNIT -->|"branch_taken / mispredict"| HAZARD
    BRANCH_UNIT -->|"update_pc, target, taken"| BTB

    HAZARD -->|"pc_stall"| PCREG
    HAZARD -->|"if_id_stall, if_id_flush"| REG_IF_ID
    HAZARD -->|"id_ex_flush"| REG_ID_EX

    EX_MUX -->|"ex_result [31:0]"| REG_EX_MEM
    MUXB -->|"mem_wdata [31:0]"| REG_EX_MEM

    REG_EX_MEM -->|"ex_result (addr) [31:0]"| DCACHE
    REG_EX_MEM -->|"mem_wdata [31:0]"| DCACHE
    REG_EX_MEM -->|"funct3 [2:0]"| STRB_GEN
    STRB_GEN -->|"dmem_wstrb [3:0]"| DCACHE
    DCACHE -->|"raw_rdata [31:0]"| LOAD_EXT
    LOAD_EXT -->|"formatted_rdata [31:0]"| REG_MEM_WB
    REG_EX_MEM -->|"ex_result bypass [31:0]"| REG_MEM_WB

    REG_EX_MEM -.->|"Distance-1 Bypass [31:0]"| FWD_UNIT
    REG_MEM_WB -.->|"Distance-2 Bypass [31:0]"| FWD_UNIT

    REG_MEM_WB --> WB_MUX
    CSR_PERF -->|"csr_rdata [31:0]"| WB_MUX

    WB_MUX -->|"wb_data [31:0]"| RF
```

---

### Architectural Signal and Bus Width Definitions

| Signal Name | Source Module | Destination Module(s) | Bit Width | Hardware Function / Operational Description |
|---|---|---|:---:|---|
| `clk` | Master Clock Generator | All Sequential Elements (PC, RegFile, Pipeline Registers, Caches, Divider, FPU, BTB, CSRs) | 1 bit | 100 MHz primary synchronous clock edge |
| `reset_n` | Reset Synchronizer | All Sequential Elements | 1 bit | Active-low global synchronous system reset |
| `pc` | PC Register | L1 I-Cache, Adder (+4), Feature 7 BTB, IF/ID Reg | 32 bits | Current program counter instruction address |
| `pc_plus_4` | Adder (+4) | PC Multiplexer (input `00`), IF/ID Pipeline Register | 32 bits | Sequential next instruction address ($pc + 4$) |
| `pc_next` | PC Multiplexer (4:1) | PC Register | 32 bits | Target address selected for next fetch cycle |
| `btb_target` | Feature 7 BTB | PC Multiplexer (input `01`) | 32 bits | Speculative branch target address on BTB cache hit |
| `btb_hit` | Feature 7 BTB | Fetch Multiplexer Control Logic | 1 bit | Asserted when $pc$ matches a valid entry in the 32-entry BTB |
| `update_pc` | Branch/Jump Unit (EX) | Feature 7 BTB Update Port | 32 bits | Branch instruction PC passed to update BTB entry |
| `actual_target` | Branch/Jump Unit (EX) | PC Multiplexer (input `10`), Feature 7 BTB | 32 bits | Actual evaluated branch/jump target address |
| `actual_taken` | Branch/Jump Unit (EX) | Feature 7 BTB, Hazard Detection Unit | 1 bit | Asserted when conditional branch evaluates TRUE |
| `instr` | Feature 3 L1 I-Cache | IF/ID Pipeline Register | 32 bits | 32-bit RISC-V machine instruction word fetched from I-Cache |
| `icache_stall` | Feature 3 L1 I-Cache | Hazard Detection Unit | 1 bit | Hold request asserted during I-Cache miss 16-byte burst refill |
| `if_id_pc` | IF/ID Pipeline Register | ID/EX Pipeline Register, Branch Adder | 32 bits | Registered program counter of instruction in Decode stage |
| `if_id_pc_plus_4` | IF/ID Pipeline Register | ID/EX Pipeline Register | 32 bits | Registered sequential link address ($pc + 4$) in Decode |
| `if_id_instr` | IF/ID Pipeline Register | Control Unit, RegFile, ImmGen, Hazard Unit | 32 bits | Registered instruction word currently being decoded |
| `opcode` | Instruction Field `[6:0]` | Main Control Unit, Hazard Unit | 7 bits | RV32I/M base and extension opcode identifier |
| `funct3` | Instruction Field `[14:12]` | Control Unit, ALU Control, Branch Unit, ID/EX Reg | 3 bits | Sub-operation selector for arithmetic, branch, load, store |
| `funct7` | Instruction Field `[31:25]` | Control Unit, ALU Control, ID/EX Reg | 7 bits | Extended operation selector for math, FPU, and Zbb |
| `rs1` | Instruction Field `[19:15]` | Register File (Read Port 1), Hazard Unit, ID/EX Reg | 5 bits | Source register 1 address index ($x0 - x31$) |
| `rs2` | Instruction Field `[24:20]` | Register File (Read Port 2), Hazard Unit, ID/EX Reg | 5 bits | Source register 2 address index ($x0 - x31$) |
| `rd` | Instruction Field `[11:7]` | ID/EX Pipeline Register | 5 bits | Destination register index for writeback retirement |
| `rs1_data` | Register File | ID/EX Pipeline Register | 32 bits | Register value read from Port 1 asynchronously |
| `rs2_data` | Register File | ID/EX Pipeline Register | 32 bits | Register value read from Port 2 asynchronously |
| `imm` | Immediate Generator | ID/EX Pipeline Register | 32 bits | Sign-extended 32-bit immediate (I, S, B, U, J types) |
| `pc_stall` | Hazard Detection Unit | PC Register Enable (`~pc_stall`) | 1 bit | Active-high stall freeze holding PC on load-use, cache, or math stalls |
| `if_id_stall` | Hazard Detection Unit | IF/ID Pipeline Register Enable (`~if_id_stall`)| 1 bit | Active-high stall freeze holding IF/ID register |
| `id_ex_flush` | Hazard Detection Unit | ID/EX Pipeline Register Synchronous Clear | 1 bit | Injects synchronous bubble (NOP) into ID/EX on hazard or branch |
| `if_id_flush` | Hazard Detection Unit | IF/ID Pipeline Register Synchronous Clear | 1 bit | Annuls speculative instruction in IF/ID on branch taken |
| `RegWrite` | Control Unit | ID/EX ➔ EX/MEM ➔ MEM/WB ➔ RegFile `we` | 1 bit | Register write enable asserted for instructions retiring to `rd` |
| `MemRead` | Control Unit | ID/EX ➔ EX/MEM ➔ D-Cache `re`, Hazard Unit | 1 bit | Data memory read strobe for load instructions (`LB`, `LH`, `LW`) |
| `MemWrite` | Control Unit | ID/EX ➔ EX/MEM ➔ D-Cache `we` | 1 bit | Data memory write strobe for store instructions (`SB`, `SH`, `SW`) |
| `MemToReg` | Control Unit | ID/EX ➔ EX/MEM ➔ MEM/WB ➔ WB Mux Select | 2 bits | Selects WB source (`00`: ALU, `01`: Mem, `10`: PC+4, `11`: CSR) |
| `ALUSrcA` | Control Unit | ID/EX ➔ ALUSrcA Mux | 1 bit | Selects operand A (`0`: forwarded rs1, `1`: PC for AUIPC/JAL) |
| `ALUSrcB` | Control Unit | ID/EX ➔ ALUSrcB Mux | 1 bit | Selects operand B (`0`: forwarded rs2, `1`: immediate value) |
| `ALUOp` | Control Unit | ID/EX ➔ ALU Control Logic | 4 bits | Encoded operation category for ALU Control decoder |
| `Branch` | Control Unit | ID/EX ➔ Branch/Jump Evaluation Unit | 1 bit | Asserted for conditional branch instructions (`B-type`) |
| `Jump` | Control Unit | ID/EX ➔ Branch/Jump Evaluation Unit | 1 bit | Asserted for unconditional jump instructions (`JAL`, `JALR`) |
| `is_mul` | Control Unit | ID/EX ➔ Feature 2 Multiplier Unit | 1 bit | Multiplier operation enable strobe |
| `is_div` | Control Unit | ID/EX ➔ Feature 5 Divider Unit, Hazard Unit | 1 bit | Divider start request strobe initiating 32-cycle FSM |
| `is_fpu` | Control Unit | ID/EX ➔ Feature 4 FPU Unit, Hazard Unit | 1 bit | Single-precision FPU start request strobe |
| `is_zbb` | Control Unit | ID/EX ➔ Feature 9 Zbb Unit | 1 bit | Zbb bit-manipulation operation enable strobe |
| `is_csr` | Control Unit | ID/EX ➔ EX/MEM ➔ MEM/WB ➔ Feature 8 CSR Unit | 1 bit | Performance counter CSR read enable |
| `forward_a` | Forwarding Unit | Forwarding Multiplexer A Select | 2 bits | Bypass select for operand A (`00`: RF, `01`: EX/MEM, `10`: MEM/WB) |
| `forward_b` | Forwarding Unit | Forwarding Multiplexer B Select | 2 bits | Bypass select for operand B (`00`: RF, `01`: EX/MEM, `10`: MEM/WB) |
| `op_a_fwd` | Forwarding Multiplexer A | ALUSrcA Mux, Multiplier, Divider, FPU, Zbb, Branch | 32 bits | Hazard-resolved operand A value fed into EX stage modules |
| `op_b_fwd` | Forwarding Multiplexer B | ALUSrcB Mux, Multiplier, Divider, FPU, Zbb, Store Bus| 32 bits | Hazard-resolved operand B value (also passes to `mem_wdata`) |
| `alu_in_a` | ALUSrcA Multiplexer | Base ALU Input A | 32 bits | Final arithmetic operand A (rs1 data or PC) |
| `alu_in_b` | ALUSrcB Multiplexer | Base ALU Input B | 32 bits | Final arithmetic operand B (rs2 data or immediate) |
| `base_alu_out` | Base ALU (RV32I) | EX Result Multiplexer (input `000`) | 32 bits | RV32I base arithmetic and logic result |
| `mul_out` | Feature 2 Multiplier | EX Result Multiplexer (input `001`) | 32 bits | Hardware multiplier output (`MUL`, `MULH`, `MULHSU`, `MULHU`) |
| `div_out` | Feature 5 Divider | EX Result Multiplexer (input `010`) | 32 bits | Hardware divider quotient or remainder output |
| `div_busy` | Feature 5 Divider | Hazard Detection Unit | 1 bit | Multi-cycle stall request holding pipeline during 32 division cycles |
| `fpu_out` | Feature 4 IEEE 754 FPU | EX Result Multiplexer (input `011`) | 32 bits | IEEE 754 float result (`FADD.S`, `FSUB.S`, `FMUL.S`, `FDIV.S`) |
| `fpu_busy` | Feature 4 IEEE 754 FPU | Hazard Detection Unit | 1 bit | FPU multi-cycle stall request signal |
| `zbb_out` | Feature 9 Zbb Unit | EX Result Multiplexer (input `100`) | 32 bits | Bit manipulation result (`CLZ`, `CTZ`, `CPOP`, `MIN`, `MAX`) |
| `ex_result` | EX Result Multiplexer | EX/MEM Reg, Forwarding Distance-1 Bus | 32 bits | Selected execution result (memory address or computational data) |
| `branch_taken` | Branch/Jump Unit (EX) | PC Multiplexer, Hazard Unit, Feature 7 BTB | 1 bit | Asserted when branch condition is evaluated TRUE |
| `mem_wdata` | ID/EX Register (`op_b_fwd`)| EX/MEM Register ➔ L1 D-Cache Write Data | 32 bits | Store data operand forwarded from EX stage |
| `dmem_wstrb` | Store Byte-Enable Gen | Feature 6 L1 D-Cache | 4 bits | Byte write enable mask generated from `funct3` (`SB`, `SH`, `SW`) |
| `raw_rdata` | Feature 6 L1 D-Cache | Load Sign/Zero Extender & Formatter | 32 bits | Raw 32-bit data word read from L1 D-Cache SRAM array |
| `dcache_stall` | Feature 6 L1 D-Cache | Hazard Detection Unit | 1 bit | Stall request asserted during D-Cache miss burst refill |
| `formatted_mem_data`| Load Sign Extender | MEM/WB Pipeline Register | 32 bits | Aligned and sign/zero-extended load data (`LB`, `LH`, `LW`, etc.) |
| `csr_rdata` | Feature 8 CSR Counters | Writeback Multiplexer (input `11`) | 32 bits | Passive performance counter value (`cycle`, `instret`, `misses`) |
| `wb_data` | Writeback Multiplexer (4:1) | Register File `wdata`, Forwarding Distance-2 Bus | 32 bits | Final retirement result written back to destination register |
| `rd_wb` | MEM/WB Pipeline Register | Register File Write Address (`waddr`) | 5 bits | Destination register index ($x0 - x31$) retiring in WB |
| `reg_write` | MEM/WB Pipeline Register | Register File Write Enable (`we`) | 1 bit | Write strobe committing `wb_data` into Register File |

---

## 2. Timing Diagram (31 Clock Cycles with Hazards)

![Hand-Drawn 31-Cycle Pipeline Timing Diagram](timing_diagram_drawn.jpg)

### Requirements & Hardware Execution Overview
- **Requirements Satisfied:** Comprehensive **31 clock cycles** (exceeding the $\ge 20$ cycles requirement), derived directly from a compiled benchmark sequence with realistic hazards, stalls, forwarding, and multi-cycle execution units.
- **Key Hardware Events & Trace Characteristics:**
  1. **L1 D-Cache Miss & 10-Cycle Memory Stall (`mem_stall = 1`)**: Instruction `I1` (`LW x5, 0(x10)`) triggers a 10-cycle cache refill FSM in the MEM stage (Cycles 4–13) while main memory performs a burst line refill, freezing the entire pipeline and PC.
  2. **Distance-1 RAW Load-Use Operand Forwarding**: Upon cache refill completion in Cycle 14, `x5 = 42` is forwarded directly from the MEM/WB stage to the EX stage for `I2` (`ADDI x6, x5, 4`), computing `42 + 4 = 46` with 0 software delay slots.
  3. **Control Hazard (Branch Taken) & Speculative Instruction Flush**: `I3` (`BNE x6, x0, 0x20`) receives forwarded operand `x6 = 46` in Cycle 15 and resolves TAKEN to `0x20`. The speculatively fetched fall-through instruction `I4` (`SUB x7, x7, x1` at `0x0C`) is flushed via `branch_flush = 1`, entering EX as a bubble (`NOP (flushed)`) in Cycle 16 while PC redirects to `0x20`.
  4. **Multi-Cycle IEEE 754 Floating-Point Unit (FPU) Execution**:
     - **`FADD.S f3, f1, f2` (`I5`)**: Executes in EX across **5 clock cycles** (Cycles 18–22) using standard logic FSM, asserting `FPU_Busy = 1` and freezing ID/IF. Calculates sum `1.5 + 2.5 = 4.0`.
     - **RAW FP Forwarding**: The computed sum `f3 = 4.0` is forwarded directly into `I6` (`FMUL.S`).
     - **`FMUL.S f5, f3, f4` (`I6`)**: Executes in EX across **4 clock cycles** (Cycles 23–26) utilizing DSP Slices for 24-bit mantissa multiplication, holding `FPU_Busy = 1`. Calculates product `4.0 * 2.0 = 8.0`.
  5. **Memory Store (`SW`) & Pipeline Completion**:
     - `I7` (`SW x6, 0(x11)`) is held in ID during `FPU_Busy`, enters EX in Cycle 27 (calculating address `0x200`), and asserts `Mem_write = 1` in Cycle 28, storing `Mem[0x200] = 46`.
     - Architectural writebacks commit at Cycle 14 (`x5 = 42`), Cycle 16 (`x6 = 46`), Cycle 24 (`f3 = 4.0`), and Cycle 28 (`f5 = 8.0`).

---

### Table 2.1: Real Benchmark Instruction Sequence with Hazard Characteristics

| ID | Address | Instruction | Format | Initial / Input Operands | Hazard, Stall & Forwarding Characteristics |
|:---:|:---:|---|:---:|---|---|
| **I1** | `0x00` | `LW x5, 0(x10)` | I-Type | `x10 = 0x100, Mem[0x100] = 42` | Memory Load: Triggers 10-cycle L1 D-Cache miss refill (Cycles 4–13, `mem_stall = 1`). Writes back `x5 = 42` in Cycle 14. |
| **I2** | `0x04` | `ADDI x6, x5, 4` | I-Type | `x5 = 42 (fwd), imm = 4` | Load-Use Data Hazard: Receives forwarded `x5 = 42` from MEM/WB in Cycle 14 (`alu_op1 = 42`). Computes `42 + 4 = 46`. Writes back `x6 = 46` in Cycle 16. |
| **I3** | `0x08` | `BNE x6, x0, 0x20` | B-Type | `x6 = 46 (fwd), x0 = 0` | Control Hazard: Receives forwarded `x6 = 46` in EX in Cycle 15 (`alu_op1 = 46`). Evaluates TAKEN (`46 != 0`) to PC `0x20`. Asserts `branch_flush` to flush fall-through `I4`. |
| **I4** | `0x0C` | `SUB x7, x7, x1` | R-Type | `x7 = —, x1 = —` | Speculative Misprediction: Fetched on fall-through wrong path. Invalidation triggered by `branch_flush` in Cycle 15; enters EX as `NOP (flushed)` in Cycle 16. |
| **I5** | `0x20` | `FADD.S f3, f1, f2` | R-Type (FP) | `f1 = 1.5, f2 = 2.5` | Branch Target: Multi-cycle IEEE 754 addition (5-cycle standard logic FSM, Cycles 18–22, `FPU_Busy = 1`). Computes `f3 = 1.5 + 2.5 = 4.0`. Writes back in Cycle 24. |
| **I6** | `0x24` | `FMUL.S f5, f3, f4` | R-Type (FP) | `f3 = 4.0 (fwd), f4 = 2.0` | RAW FP Dependency: Receives forwarded `f3 = 4.0` in Cycle 23. Multi-cycle IEEE 754 multiplication (4-cycle DSP FSM, Cycles 23–26). Computes `f5 = 4.0 * 2.0 = 8.0`. Writes back in Cycle 28. |
| **I7** | `0x28` | `SW x6, 0(x11)` | S-Type | `x11 = 0x200, x6 = 46` | Memory Store: Held in ID during `FPU_Busy` (Cycles 18–26). Calculates address `0x200` in Cycle 27. Asserts `Mem_write = 1` in Cycle 28 storing `Mem[0x200] = 46`. Commits in Cycle 29. |

---

### Table 2.2: Cycle-by-Cycle Pipeline Reservation Table (Cycles 1 to 31)

| Cycle | PC | IF Stage | ID Stage | EX Stage | MEM Stage | WB Stage | `alu_op1` | `alu_op2` | Pipeline Control & Hardware Interlock Status |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|---|
| **CC01** | `0x00` | `I1 (LW)` | — | — | — | — | — | — | Normal fetch of `I1 (LW x5, 0(x10))` at PC `0x00`; PC becomes `0x04`. |
| **CC02** | `0x04` | `I2 (ADDI)` | `I1 (LW)` | — | — | — | — | — | Fetch `I2 (ADDI)`; `I1` in Decode reads base register `x10 = 0x100`; PC becomes `0x08`. |
| **CC03** | `0x08` | `I3 (BNE)` | `I2 (ADDI)` | `I1 (LW)` | — | — | `0x100` | `0` | Fetch `I3 (BNE)`; `I2` in Decode; `I1` in EX computes address `0x100 + 0 = 0x100`; PC becomes `0x0C`. |
| **CC04** | `0x0C` | `I4 (SUB)` | `I3 (BNE)` | `I2 (held)` | `I1 (miss)` | — | — | — | `I1` accesses `0x100`: **L1 D-Cache miss!** `mem_stall = 1` asserts; 10-cycle BRAM refill FSM begins. Pipeline frozen. |
| **CC05** | `0x08` | `I3 (held)` | `I2 (held)` | — | `I1 (2/10)` | — | — | — | `mem_stall = 1`; DRAM burst line refill in progress; IF/ID/EX held; PC frozen at `0x08`. |
| **CC06** | `0x08` | `I3 (held)` | `I2 (held)` | — | `I1 (3/10)` | — | — | — | `mem_stall = 1`; Burst word 1 transferred into refill line buffer; core frozen. |
| **CC07** | `0x08` | `I3 (held)` | `I2 (held)` | — | `I1 (4/10)` | — | — | — | `mem_stall = 1`; Burst word 2 transferred into refill line buffer; core frozen. |
| **CC08** | `0x08` | `I3 (held)` | `I2 (held)` | — | `I1 (5/10)` | — | — | — | `mem_stall = 1`; Mid-burst DRAM latency cycle; core pipeline frozen. |
| **CC09** | `0x08` | `I3 (held)` | `I2 (held)` | — | `I1 (6/10)` | — | — | — | `mem_stall = 1`; Burst transfer ongoing; pipeline frozen. |
| **CC10** | `0x08` | `I3 (held)` | `I2 (held)` | — | `I1 (7/10)` | — | — | — | `mem_stall = 1`; Burst word 3 transferred into refill line buffer; core frozen. |
| **CC11** | `0x08` | `I3 (held)` | `I2 (held)` | — | `I1 (8/10)` | — | — | — | `mem_stall = 1`; Burst word 4 transferred into refill line buffer; core frozen. |
| **CC12** | `0x08` | `I3 (held)` | `I2 (held)` | — | `I1 (9/10)` | — | — | — | `mem_stall = 1`; Cache line assembly completed; SRAM tag update prepared. |
| **CC13** | `0x08` | `I3 (held)` | `I2 (held)` | — | `I1 (10/10)`| — | — | — | `mem_stall = 1`; Final refill cycle; cache line valid bit set; `mem_stall` deasserts at clock edge. |
| **CC14** | `0x0C` | `I4 (path)` | `I3 (BNE)` | `I2 (ADDI)` | — | `I1 (x5=42)` | `42 (fwd)` | `4` | Refill complete (`mem_stall = 0`). `I1` writes `x5 = 42`. **RAW Forwarding**: `x5 = 42` bypassed to EX. `I2` computes `42 + 4 = 46`. |
| **CC15** | `0x10` | — | `I4 (flush)`| `I3 (BNE)` | `I2 (ADDI)` | — | `46 (fwd)` | `0` | **RAW Forwarding**: `x6 = 46` bypassed to EX. `I3` evaluates `46 != 0` $\rightarrow$ **TAKEN to `0x20`**! `branch_flush = 1` pulses; `I4` flushed. |
| **CC16** | `0x20` | `I5 (FADD)` | — | `NOP (flush)` | `I3 (BNE)` | `I2 (x6=46)` | — | — | PC redirects to `0x20`; fetch `I5 (FADD.S)`. Flushed `I4` enters EX as NOP bubble. `I2` writes back `x6 = 46`. |
| **CC17** | `0x24` | `I6 (FMUL)` | `I5 (FADD)` | `NOP` | `NOP` | `I3 (BNE)` | — | — | Fetch `I6 (FMUL.S)` at `0x24`; `I5` in ID reads `f1 = 1.5`, `f2 = 2.5`. Bubble propagates through MEM. |
| **CC18** | `0x28` | `I7 (SW)` | `I6 (held)` | `I5 (1/5)` | — | — | `1.5` | `2.5` | `I5` enters EX: **`FPU_Busy = 1` asserts!** 5-cycle FADD.S begins (Cycle 1/5: exponent diff). Fetch `I7 (SW)` at `0x28`. |
| **CC19** | `0x28` | — | `I7 (held)` | `I5 (2/5)` | — | — | `1.5` | `2.5` | `FPU_Busy = 1`; FADD.S Cycle 2/5 (mantissa alignment); IF and ID frozen; PC held at `0x28`. |
| **CC20** | `0x28` | — | `I7 (held)` | `I5 (3/5)` | — | — | `1.5` | `2.5` | `FPU_Busy = 1`; FADD.S Cycle 3/5 (24-bit mantissa addition: $1.5 + 2.5 = 4.0$); core held. |
| **CC21** | `0x28` | — | `I7 (held)` | `I5 (4/5)` | — | — | `1.5` | `2.5` | `FPU_Busy = 1`; FADD.S Cycle 4/5 (leading-zero detection & normalization); core held. |
| **CC22** | `0x28` | — | `I7 (held)` | `I5 (5/5)` | — | — | `1.5` | `2.5` | `FPU_Busy = 1`; FADD.S Cycle 5/5 (round-to-nearest-even); final sum `f3 = 4.0` ready. |
| **CC23** | `0x28` | — | `I7 (held)` | `I6 (1/4)` | `I5 (FADD)` | — | `4.0 (f3 fwd)` | `2.0` | `I5` advances to MEM (sum 4.0). `I6 (FMUL.S)` enters EX. **RAW FP Forwarding**: `f3 = 4.0` bypassed to FMUL.S! 4-cycle FMUL.S begins (Cycle 1/4). |
| **CC24** | `0x28` | — | `I7 (held)` | `I6 (2/4)` | — | `I5 (f3=4.0)` | `4.0` | `2.0` | `FPU_Busy = 1`; FMUL.S Cycle 2/4 (48-bit product reduction in DSP). `I5` in WB writes `f3 = 4.0`. |
| **CC25** | `0x28` | — | `I7 (held)` | `I6 (3/4)` | — | — | `4.0` | `2.0` | `FPU_Busy = 1`; FMUL.S Cycle 3/4 (exponent sum & mantissa normalization); core held. |
| **CC26** | `0x28` | — | `I7 (held)` | `I6 (4/4)` | — | — | `4.0` | `2.0` | `FPU_Busy = 1`; FMUL.S Cycle 4/4 (rounding to `f5 = 8.0`); `FPU_Busy` deasserts at clock edge. |
| **CC27** | — | — | — | `I7 (SW)` | `I6 (FMUL)` | — | `0x200` | `0` | `FPU_Busy = 0`; `I7` enters EX: calculates address `0x200 + 0 = 0x200`. `I6` in MEM passes product `f5 = 8.0`. |
| **CC28** | — | — | — | — | `I7 (SW)` | `I6 (f5=8.0)` | — | — | `I7` in MEM: **`Mem_write = 1` asserts!** Store data `x6 = 46` written: **`Mem[0x200] = 46`**! `I6` in WB writes `f5 = 8.0`. |
| **CC29** | — | — | — | — | — | `I7 (SW)` | — | — | `I7` in WB commits (no register write, `RegWrite = 0`). All 7 benchmark instructions retired. |
| **CC30** | — | — | — | — | — | — | — | — | Pipeline fully drained; core quiescent; passive CSRs profile 31 total elapsed clock cycles. |
| **CC31** | — | — | — | — | — | — | — | — | Execution verified: `x5 = 42`, `x6 = 46`, `f3 = 4.0`, `f5 = 8.0`, `Mem[0x200] = 46`. Correctness 100%. |

---

---

## 3. Module Summary Table

| Module | Purpose | File | Implementation Type |
|---|---|---|---|
| `pipeline_5stage` | Top-level structural core integrating IF, ID, EX, MEM, WB | `feature_1/modules/pipeline_5stage.v` | Hardware (Verilog HDL) |
| `if_id_reg` | Pipeline register with synchronous stall freeze and branch flush | `feature_1/modules/if_id_reg.v` | Hardware (Verilog HDL) |
| `decode_stage` | Instruction decoder, sign extender, 32-entry dual-port RegFile | `feature_1/modules/decode_stage.v` | Hardware (Verilog HDL) |
| `id_ex_reg` | Pipeline register holding operands and control lines for EX | `feature_1/modules/id_ex_reg.v` | Hardware (Verilog HDL) |
| `execute_stage` | Base 32-bit ALU, branch comparator, and EX output multiplexer | `feature_1/modules/execute_stage.v` | Hardware (Verilog HDL) |
| `hazard_unit` | Detects load-use hazards, branch taken, and multi-cycle stalls | `feature_1/modules/hazard_unit.v` | Hardware (Verilog HDL) |
| `forwarding_unit` | Selects EX/MEM and MEM/WB bypass multiplexer paths (Mux A/B) | `feature_1/modules/hazard_unit.v` | Hardware (Verilog HDL) |
| `ex_mem_reg` | Pipeline register passing memory address, write data, control | `feature_1/modules/ex_mem_reg.v` | Hardware (Verilog HDL) |
| `memory_stage` | Memory interface with byte/halfword alignment masking | `feature_1/modules/memory_stage.v` | Hardware (Verilog HDL) |
| `mem_wb_reg` | Pipeline register passing final load data and ALU result to WB | `feature_1/modules/mem_wb_reg.v` | Hardware (Verilog HDL) |
| `writeback_stage` | Writeback multiplexer selecting memory, ALU, link PC, or CSR | `feature_1/modules/writeback_stage.v` | Hardware (Verilog HDL) |
| `multiplier_unit` | **Feature 2**: Dual-Mode Multiplier (1-cycle Artix-7 DSP48E1 & Radix-4 Booth) | `feature_2/modules/multiplier_unit.v` | Hardware (Verilog HDL) |
| `icache_controller`| **Feature 3**: Direct-mapped 2 KB L1 Instruction Cache & 10-cyc miss FSM | `feature_3/icache_controller.v` | Hardware (Verilog HDL) |
| `fpu_single_core` | **Feature 4**: IEEE 754 FPU (FMUL 4c DSP; FADD/SUB 5c logic; FDIV 15c NR with BRAM) | `feature_4/fpu_single_core.v` | Hardware (Verilog HDL) |
| `divider_unit` | **Feature 5**: 32-cycle Shift-and-Subtract integer divider (Standard Logic, no DSPs) | `feature_5/divider_unit.v` | Hardware (Verilog HDL) |
| `dcache_controller`| **Feature 6**: Direct-mapped 2 KB L1 Data Cache & write buffer | `feature_6/dcache_controller.v` | Hardware (Verilog HDL) |
| `btb_branch_pred` | **Feature 7**: Static 32-entry Branch Target Buffer (BTB) | `feature_7/btb_branch_pred.v` | Hardware (Verilog HDL) |
| `csr_perf_counters`| **Feature 8**: Passive performance CSR monitoring registers | `feature_8/csr_perf_counters.v` | Hardware (Verilog HDL) |
| `bitmanip_unit` | **Feature 9**: Zbb bit manipulation ALU (`CLZ`, `CPOP`, `MIN`, `MAX`)| `feature_9/bitmanip_unit.v` | Hardware (Verilog HDL) |

---

## 4. Hardware Resource Estimates

Target FPGA Architecture: **Xilinx Artix-7 XC7A100T-1CSG324C** (Digilent Nexys A7 Board)

| Hardware Resource | Maximum Available on XC7A100T | Estimated Core Usage | % Utilization | Engineering Justification |
|---|:---:|:---:|:---:|---|
| **LUTs (Look-Up Tables)** | **63,400** | **4,850** | **7.6 %** | Base core (2,100), 5-cycle FADD/FSUB standard logic adders/shifters (1,800), 32-cycle DIV shift-and-subtract (450), Booth/CSRs (500) |
| **FF (Flip-Flops)** | **126,800** | **4,200** | **3.3 %** | Pipeline registers (1,200), FPU registers (1,024), Cache tags/data (1,336), CSR counters (640) |
| **BRAM (36Kb Blocks)** | **135 blocks** (4,860 Kb) | **8 blocks** | **5.9 %** | 4 BRAMs for L1 I-Cache, 3 BRAMs for L1 D-Cache, 1 BRAM for FDIV.S Newton-Raphson initial guess lookup |
| **DSP48E1 Slices** | **240 slices** | **4 slices** | **1.7 %** | Dedicated to 1-cycle integer MUL, 4-cycle FMUL.S mantissa multiply, and 15-cycle FDIV.S iterative multiply. *No DSPs for FADD/SUB/DIV.* |

---

## 5. Verification Plans

- **Automated C Benchmark Suite**: Validate full-system processor execution across arithmetic, iterative loops, memory arrays, and logic operations using standalone bare-metal C programs (`addition.c`, `fibonacci.c`, `sort.c`, `negative.c`, `xor.c`) running on Vivado Simulator (`xsim`).
- **Targeted Unit Math Testbenches**: Exhaustively verify the Hardware Multiplier (Feature 2) and Divider (Feature 5) across signed/unsigned boundary conditions, division by zero ($rs2 = 0$), and overflow ($\text{INT\_MIN} / -1$).
- **Cache Hit/Miss Assertion Framework**: Verify L1 I-Cache and D-Cache refill state machines using memory access patterns that provoke sequential hits, cold misses, capacity evictions, and byte-enable store masking.
- **Hardware-in-the-Loop FPGA Validation**: Synthesize the core with a UART diagnostic interface and 7-segment display on the Nexys A7 FPGA to verify real-time performance counters and retired instruction metrics at 100 MHz.

---

## 6. Project Gantt Chart & Milestone Schedule

**Team Members (Group 13):**
- **Student 1 (S1):** Pisini Ramana
- **Student 2 (S2):** Chimbili Sahithi
- **Student 3 (S3):** Siddharth Misro
- **Student 4 (S4):** Bandaru Rohith Datta
- **Student 5 (S5):** Sigilipelli Praneeth Sai Bharath

**Key Deadlines:**
- **Milestone 1 Core Completion:** October 25, 2026
- **Minimum System Commitment:** November 1, 2026
- **Final Demonstration:** November 8, 2026

| # | Concrete Testable Activity | Owner | Duration | Oct 01–10 | Oct 11–18 | Oct 19–25 | Oct 26–Nov 01 | Nov 02–08 |
|:---:|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| 1 | IF & ID pipeline register logic & instruction fetch | S1 | Oct 02–08 | [DONE] | | | | |
| 2 | Direct-mapped L1 Instruction Cache & 10-cycle FSM | S1 | Oct 09–17 | | [ACTIVE] | | | |
| 3 | Cache hit/miss testbenches & burst memory model | S1 | Oct 18–25 | | | [PLANNED] | | |
| 4 | EX/MEM pipeline registers & store byte-enable masking | S2 | Oct 04–10 | [DONE] | | | | |
| 5 | Multi-cycle Radix-2 Non-Restoring Divider RTL | S2 | Oct 12–20 | | [ACTIVE] | [PLANNED] | | |
| 6 | Divider stall handshaking & divide-by-zero handling | S2 | Oct 19–26 | | | [PLANNED] | [PLANNED] | |
| 7 | Artix-7 DSP48E1 hardware multiplier instantiation | S3 | Oct 08–14 | [DONE] | [ACTIVE] | | | |
| 8 | Synthesizable Radix-4 Modified Booth Multiplier RTL | S3 | Oct 12–18 | | [ACTIVE] | | | |
| 9 | Dual-mode multiplier unit wrapper (sw[3] selection) | S3 | Oct 16–21 | | [ACTIVE] | [PLANNED] | | |
| 10| IEEE 754 single-precision FPU core (FADD, FMUL, FDIV) | S3 | Oct 20–30 | | | [PLANNED] | [PLANNED] | |
| 11| Control Unit instruction decoder & stall logic | S4 | Oct 03–09 | [DONE] | | | | |
| 12| Direct-mapped L1 Data Cache & write buffer FSM | S4 | Oct 14–22 | | [ACTIVE] | [PLANNED] | | |
| 13| Performance Counter CSRs (cycle, instret, misses) | S4 | Oct 23–29 | | | [PLANNED] | [PLANNED] | |
| 14| Zbb Bit-Manipulation ALU (CLZ, CTZ, POPCNT) | S4 | Oct 28–Nov 02| | | | [PLANNED] | [PLANNED] |
| 15| 5-Stage base pipeline registers & datapath integration | S5 | Oct 01–07 | [DONE] | | | | |
| 16| Hazard Detection Unit & forwarding multiplexers RTL | S5 | Oct 04–10 | [DONE] | | | | |
| 17| Static 32-entry Branch Target Buffer (BTB) RTL | S5 | Oct 18–25 | | | [PLANNED] | | |
| 18| Automated C trace suite & full-system testbench | S5 | Oct 24–31 | | | [PLANNED] | [PLANNED] | |
| 19| **Pipeline Subsystem Integration & Stall Interlocking** | **ALL** | **Oct 11–17** | | **[ACTIVE]** | | | |
| 20| **★ MILESTONE 1: Core Subsystem Review & Integration Check** | **ALL** | **Oct 25** | | | **[◆ MS 1]** | | |
| 21| **Full-System 9-Feature Datapath Integration & Interconnect** | **ALL** | **Oct 26–31** | | | | **[PLANNED]** | |
| 22| **★ MILESTONE 2: Minimum System Commitment Met (All 9 Features)**| **ALL** | **Nov 01** | | | | **[◆ COMMIT]**| |
| 23| Nexys A7 FPGA Demo: 7-Seg, LEDs, 1Hz Clk, UART streaming | ALL | Nov 01–06 | | | | | [PLANNED]|
| 24| **★ FINAL MILESTONE: Timing Closure & Project Grading Demo** | **ALL** | **Nov 05–08** | | | | | **[★ FINAL]**|

### Gantt Chart Legend & Milestone Highlights:
- **Active Work Period (`[ACTIVE]` / `[DONE]`):** Scheduled RTL design, logic synthesis, unit testbench verification, and FPGA prototyping.
- **Mid-Project Subsystem Integration (`ALL`, Oct 11–17):** Collaborative whole-team integration window where all members (especially pipeline and hazard leads) integrate incoming math units (DSP48E1 / Booth Multipliers) and L1 I-Cache into the 5-stage datapath with multi-cycle stall interlocking.
- **◆ MILESTONE 1 (Oct 25):** Core functionality milestone satisfied. 5-Stage pipeline, Hazard Detection Unit, operand forwarding, dual-mode multiplier, Radix-2 divider base, and L1 I-Cache fully functional and verified.
- **◆ MINIMUM SYSTEM COMMITMENT (Nov 01):** All 9 required project features (32-entry BTB, DSP/Booth Multipliers, Radix-2 Divider, IEEE 754 FPU, L1 I-Cache, L1 D-Cache, CSR counters, Zbb ALU, and Hazard Unit) fully integrated into core.
- **★ FINAL MILESTONE (Nov 08):** Full-speed 100 MHz timing closure achieved on Artix-7 FPGA fabric, bitstream generated, UART / 7-segment / LED diagnostics active, and final TA grading demonstration.

---

## 7. Risks and Challenges

1. **Multi-Cycle Stall Interlocking**: Coordinating concurrent stall requests from the divider, FPU, and cache misses without causing deadlock in the hazard unit.
2. **FPGA Timing Closure on DSP Paths**: Critical path timing violations through cascading 32-bit multiply-accumulate and FPU mantissa normalization stages at 100 MHz.
3. **Cache Coherency During Refills**: Ensuring instruction fetch and data memory accesses serialize correctly without stale data when reading recently modified lines.
4. **IEEE 754 Corner Case Compliance**: Accurately handling edge cases including NaN propagation, subnormal numbers, signed zeros, and rounding modes.
5. **Branch Penalty Overheads**: Preventing excessive speculative fetch flushes on unpredictable control flows by tuning the BTB indexing and tag match logic.

---

## 8. Response to TA Feedback

| TA Feedback Item | Specific Technical Response & Implementation Plan |
|---|---|
| **1. Limited hardware contribution in base 3-stage core** | The project has expanded the hardware scope to a complete 5-stage pipelined processor featuring **9 fully integrated hardware modules**, including dedicated Radix-4 Booth multiplication, multi-cycle division, an IEEE 754 FPU, separate L1 instruction/data caches, a 32-entry BTB, and passive performance counters. |
| **2. Hazard resolution without software delays** | All data hazards (distance-1 and distance-2 RAW) are resolved entirely in hardware using dual 3:1 operand forwarding multiplexers, and load-use hazards trigger automatic single-cycle hardware interlocks without requiring compiler NOP insertion. |
| **3. Demonstration of realistic workloads** | The processor execution is verified using compiled bare-metal C benchmark programs (`addition.c`, `fibonacci.c`, `sort.c`, `negative.c`, `xor.c`) with cycle-accurate terminal profiling rather than synthetic stimulus vectors. |
| **4. Realistic timing diagram showing hazards** | A full 24-cycle timing diagram has been included that explicitly details multi-cycle divider execution, single-cycle DSP multiplication, load-use stall freezes, and 2-cycle branch flushes. |

