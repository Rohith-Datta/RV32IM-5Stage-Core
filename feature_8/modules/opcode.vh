// ============================================================================
// File: opcode.vh
// Description: RISC-V RV32I / RV32M / RV32F Opcode and Control Definitions
// Project: Pipelined RV32IMF RISC-V Core (Feature 4: IEEE 754 Single-Precision FPU)
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
// Base Opcodes (inst[6:0])
// ----------------------------------------------------------------------------
localparam [6:0] LUI      = 7'b0110111,  // U-type
                 AUIPC    = 7'b0010111,  // U-type
                 JAL      = 7'b1101111,  // J-type
                 JALR     = 7'b1100111,  // I-type
                 BRANCH   = 7'b1100011,  // B-type
                 LOAD     = 7'b0000011,  // I-type
                 STORE    = 7'b0100011,  // S-type
                 ARITHI   = 7'b0010011,  // I-type
                 ARITHR   = 7'b0110011,  // R-type (and M-extension, Zbb)
                 SYSTEM   = 7'b1110011,  // System / CSR instructions (Feature 8)
                 OP_FP    = 7'b1010011,  // Single-precision Floating Point (Feature 4)
                 LOAD_FP  = 7'b0000111,  // FLW (Feature 4)
                 STORE_FP = 7'b0100111;  // FSW (Feature 4)

// ----------------------------------------------------------------------------
// RV32M Extension Definitions (Feature 2 Multiplier & Feature 3 Divider)
// Opcode == ARITHR (7'b0110011) and funct7 == 7'b0000001
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
// RV32F Extension Definitions (Feature 4 IEEE 754 Floating-Point Unit)
// Opcode == OP_FP (7'b1010011)
// ----------------------------------------------------------------------------
localparam [6:0] FUNCT7_FADD = 7'b0000000,  // FADD.S (5 cycles)
                 FUNCT7_FSUB = 7'b0000100,  // FSUB.S (5 cycles)
                 FUNCT7_FMUL = 7'b0001000,  // FMUL.S (4 cycles)
                 FUNCT7_FDIV = 7'b0001100;  // FDIV.S (15 cycles)

localparam [2:0] FRM_RNE = 3'b000,  // Round to Nearest, ties to Even
                 FRM_RTZ = 3'b001,  // Round towards Zero
                 FRM_RDN = 3'b010,  // Round Down (-infinity)
                 FRM_RUP = 3'b011,  // Round Up (+infinity)
                 FRM_RMM = 3'b100,  // Round to Nearest, ties to Max Magnitude
                 FRM_DYN = 3'b111;  // Dynamic rounding mode

// ----------------------------------------------------------------------------
// Branch FUNC3 (inst[14:12] when opcode == BRANCH)
// ----------------------------------------------------------------------------
localparam [2:0] BEQ  = 3'b000,
                 BNE  = 3'b001,
                 BLT  = 3'b100,
                 BGE  = 3'b101,
                 BLTU = 3'b110,
                 BGEU = 3'b111;

// ----------------------------------------------------------------------------
// Load FUNC3 (inst[14:12] when opcode == LOAD)
// ----------------------------------------------------------------------------
localparam [2:0] LB  = 3'b000,
                 LH  = 3'b001,
                 LW  = 3'b010,
                 LBU = 3'b100,
                 LHU = 3'b101;

// ----------------------------------------------------------------------------
// Store FUNC3 (inst[14:12] when opcode == STORE)
// ----------------------------------------------------------------------------
localparam [2:0] SB = 3'b000,
                 SH = 3'b001,
                 SW = 3'b010;

// ----------------------------------------------------------------------------
// Arithmetic FUNC3 (inst[14:12] when opcode == ARITHR or ARITHI)
// ----------------------------------------------------------------------------
localparam [2:0] ADD  = 3'b000,  // inst[30]=0: ADD, inst[30]=1: SUB (R-type only)
                 SLL  = 3'b001,
                 SLT  = 3'b010,
                 SLTU = 3'b011,
                 XOR  = 3'b100,
                 SR   = 3'b101,  // inst[30]=0: SRL, inst[30]=1: SRA
                 OR   = 3'b110,
                 AND  = 3'b111;

// ----------------------------------------------------------------------------
// Forwarding Mux Select Codes (hazard_unit)
// ----------------------------------------------------------------------------
localparam [1:0] FWD_NONE = 2'b00,  // Use register file read data from ID/EX
                 FWD_WB   = 2'b01,  // Forward from MEM/WB stage
                 FWD_MEM  = 2'b10;  // Forward from EX/MEM stage

// ----------------------------------------------------------------------------
// Feature 8: RISC-V Passive Performance Counter CSR Addresses
// ----------------------------------------------------------------------------
localparam [11:0] CSR_CYCLE        = 12'hC00,
                  CSR_TIME         = 12'hC01,
                  CSR_INSTRET      = 12'hC02,
                  CSR_HPMCOUNTER3  = 12'hC03, // Stall cycles counter
                  CSR_HPMCOUNTER4  = 12'hC04, // Branch instructions counter
                  CSR_HPMCOUNTER5  = 12'hC05, // Branch mispredict counter
                  CSR_CYCLEH       = 12'hC80,
                  CSR_TIMEH        = 12'hC81,
                  CSR_INSTRETH     = 12'hC82,
                  CSR_HPMCOUNTER3H = 12'hC83,
                  CSR_HPMCOUNTER4H = 12'hC84,
                  CSR_HPMCOUNTER5H = 12'hC85;

localparam [2:0]  CSR_RW  = 3'b001,
                  CSR_RS  = 3'b010,
                  CSR_RC  = 3'b011,
                  CSR_RWI = 3'b101,
                  CSR_RSI = 3'b110,
                  CSR_RCI = 3'b111;

