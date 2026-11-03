// ============================================================================
// File: opcode.vh
// Description: Fully Consolidated, Collision-Free RISC-V RV32IMF + Zbb + CSR
//              Opcode, Funct3, Funct7, Imm12, and Control Signal Definitions
// Project: Pipelined RV32IMF RISC-V Integrated Core
// ============================================================================

// Bit field slices
`define OPCODE      6:0
`define FUNC3       14:12
`define SUBTYPE     30
`define RD          11:7
`define RS1         19:15
`define RS2         24:20

// Standard NOP instruction (addi x0, x0, 0)
localparam [31:0] NOP = 32'h0000_0013;

// ----------------------------------------------------------------------------
// 1. Base Major Opcodes (instruction[6:0]) - Guaranteed Distinct
// ----------------------------------------------------------------------------
localparam [6:0] LUI      = 7'b0110111,  // U-type: rd = imm << 12
                 AUIPC    = 7'b0010111,  // U-type: rd = pc + (imm << 12)
                 JAL      = 7'b1101111,  // J-type: rd = pc + 4; pc += imm
                 JALR     = 7'b1100111,  // I-type: rd = pc + 4; pc = (rs1 + imm) & ~1
                 BRANCH   = 7'b1100011,  // B-type: conditional branch
                 LOAD     = 7'b0000011,  // I-type: lb, lh, lw, lbu, lhu
                 STORE    = 7'b0100011,  // S-type: sb, sh, sw
                 ARITHI   = 7'b0010011,  // I-type: addi, slti, xori, ... and Zbb immediate
                 ARITHR   = 7'b0110011,  // R-type: add, sub, mul, div, and Zbb reg-reg
                 SYSTEM   = 7'b1110011,  // System / CSR instructions (Feature 8)
                 OP_FP    = 7'b1010011,  // Single-precision Floating Point (Feature 4)
                 LOAD_FP  = 7'b0000111,  // FLW (Feature 4)
                 STORE_FP = 7'b0100111;  // FSW (Feature 4)

// ----------------------------------------------------------------------------
// 2. RV32M Extension Definitions (M-Extension in ARITHR opcode 7'b0110011)
// ----------------------------------------------------------------------------
localparam [6:0] FUNCT7_M_EXT = 7'b0000001;

localparam [2:0] F3_MUL    = 3'b000,
                 F3_MULH   = 3'b001,
                 F3_MULHSU = 3'b010,
                 F3_MULHU  = 3'b011,
                 F3_DIV    = 3'b100,
                 F3_DIVU   = 3'b101,
                 F3_REM    = 3'b110,
                 F3_REMU   = 3'b111;

// ----------------------------------------------------------------------------
// 3. RV32F Extension Definitions (Single-Precision IEEE 754 in OP_FP 7'b1010011)
// ----------------------------------------------------------------------------
localparam [6:0] FUNCT7_FADD    = 7'b0000000,  // FADD.S (5 cycles)
                 FUNCT7_FSUB    = 7'b0000100,  // FSUB.S (5 cycles)
                 FUNCT7_FMUL    = 7'b0001000,  // FMUL.S (4 cycles)
                 FUNCT7_FDIV    = 7'b0001100,  // FDIV.S (15 cycles)
                 FUNCT7_FCVT_S_W= 7'b1101000,  // FCVT.S.W / FCVT.S.WU (1 cycle)
                 FUNCT7_FMV_X_W = 7'b1110000,  // FMV.X.W (x[rd] = f[rs1])
                 FUNCT7_FMV_W_X = 7'b1111000;  // FMV.W.X (f[rd] = x[rs1])

localparam [2:0] FRM_RNE = 3'b000,  // Round to Nearest, ties to Even
                 FRM_RTZ = 3'b001,  // Round towards Zero
                 FRM_RDN = 3'b010,  // Round Down (-infinity)
                 FRM_RUP = 3'b011,  // Round Up (+infinity)
                 FRM_RMM = 3'b100,  // Round to Nearest, ties to Max Magnitude
                 FRM_DYN = 3'b111;  // Dynamic rounding mode

// ----------------------------------------------------------------------------
// 4. RV32 Zbb Extension Definitions (Feature 9 Bit Manipulation)
// ----------------------------------------------------------------------------
localparam [6:0] FUNCT7_ZBB_LOGIC  = 7'b0100000, // ANDN (f3=111), ORN (f3=110), XNOR (f3=100)
                 FUNCT7_ZBB_MINMAX = 7'b0000101, // MIN (f3=100), MINU (f3=101), MAX (f3=110), MAXU (f3=111)
                 FUNCT7_ZBB_ROT    = 7'b0110000, // ROL (f3=001), ROR (f3=101)
                 FUNCT7_ZBB_PACK   = 7'b0000100; // ZEXT.H (f3=100, rs2=x0)

localparam [11:0] IMM12_CLZ        = 12'h600,    // CLZ (I-type, funct3=001)
                   IMM12_CTZ        = 12'h601,    // CTZ (I-type, funct3=001)
                   IMM12_CPOP       = 12'h602,    // CPOP (I-type, funct3=001)
                   IMM12_SEXTB      = 12'h604,    // SEXT.B (I-type, funct3=001)
                   IMM12_SEXTH      = 12'h605,    // SEXT.H (I-type, funct3=001)
                   IMM12_REV8       = 12'h698,    // REV8 (I-type, funct3=101)
                   IMM12_ORCB       = 12'h287;    // ORC.B (I-type, funct3=101)

// ----------------------------------------------------------------------------
// 5. Branch Funct3 (when opcode == BRANCH)
// ----------------------------------------------------------------------------
localparam [2:0] BEQ  = 3'b000,
                 BNE  = 3'b001,
                 BLT  = 3'b100,
                 BGE  = 3'b101,
                 BLTU = 3'b110,
                 BGEU = 3'b111;

// ----------------------------------------------------------------------------
// 6. Memory Load / Store Funct3
// ----------------------------------------------------------------------------
localparam [2:0] LB  = 3'b000,
                 LH  = 3'b001,
                 LW  = 3'b010,
                 LBU = 3'b100,
                 LHU = 3'b101;

localparam [2:0] SB  = 3'b000,
                 SH  = 3'b001,
                 SW  = 3'b010;

// ----------------------------------------------------------------------------
// 7. Base Arithmetic Funct3 (ARITHR and ARITHI)
// ----------------------------------------------------------------------------
localparam [2:0] ADD  = 3'b000,  // R-type inst[30]=0: ADD, inst[30]=1: SUB
                 SLL  = 3'b001,
                 SLT  = 3'b010,
                 SLTU = 3'b011,
                 XOR  = 3'b100,
                 SR   = 3'b101,  // inst[30]=0: SRL, inst[30]=1: SRA
                 OR   = 3'b110,
                 AND  = 3'b111;

// ----------------------------------------------------------------------------
// 8. Forwarding Mux Select Codes (hazard_unit)
// ----------------------------------------------------------------------------
localparam [1:0] FWD_NONE = 2'b00,  // Use register file read data from ID/EX
                 FWD_WB   = 2'b01,  // Forward from MEM/WB stage
                 FWD_MEM  = 2'b10;  // Forward from EX/MEM stage

// ----------------------------------------------------------------------------
// 9. Passive Performance Counter CSR Addresses (Feature 8)
// ----------------------------------------------------------------------------
localparam [11:0] CSR_CYCLE        = 12'hC00,
                  CSR_TIME         = 12'hC01,
                  CSR_INSTRET      = 12'hC02,
                  CSR_HPMCOUNTER3  = 12'hC03, // Pipeline Stall cycles counter
                  CSR_HPMCOUNTER4  = 12'hC04, // Branch & Jump instructions counter
                  CSR_HPMCOUNTER5  = 12'hC05, // Branch mispredict counter
                  CSR_HPMCOUNTER6  = 12'hC06, // L1 I-Cache miss counter
                  CSR_HPMCOUNTER7  = 12'hC07, // L1 D-Cache miss counter
                  CSR_CYCLEH       = 12'hC80,
                  CSR_TIMEH        = 12'hC81,
                  CSR_INSTRETH     = 12'hC82,
                  CSR_HPMCOUNTER3H = 12'hC83,
                  CSR_HPMCOUNTER4H = 12'hC84,
                  CSR_HPMCOUNTER5H = 12'hC85,
                  CSR_HPMCOUNTER6H = 12'hC86,
                  CSR_HPMCOUNTER7H = 12'hC87;

localparam [2:0]  CSR_RW  = 3'b001,
                  CSR_RS  = 3'b010,
                  CSR_RC  = 3'b011,
                  CSR_RWI = 3'b101,
                  CSR_RSI = 3'b110,
                  CSR_RCI = 3'b111;
