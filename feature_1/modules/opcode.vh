// ============================================================================
// File: opcode.vh
// Description: RISC-V RV32I / RV32M Opcode and Control Definitions
// Project: Pipelined RV32IM RISC-V Core (Feature 1: 5-Stage Upgrade)
// Note: No header guard so each module can include localparams locally.
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
localparam [6:0] LUI    = 7'b0110111,  // U-type
                 AUIPC  = 7'b0010111,  // U-type
                 JAL    = 7'b1101111,  // J-type
                 JALR   = 7'b1100111,  // I-type
                 BRANCH = 7'b1100011,  // B-type
                 LOAD   = 7'b0000011,  // I-type
                 STORE  = 7'b0100011,  // S-type
                 ARITHI = 7'b0010011,  // I-type
                 ARITHR = 7'b0110011;  // R-type (and M-extension)

// Reserved custom opcode for MAC Coprocessor (Feature 6)
localparam [6:0] CUSTOM_MAC = 7'b0001011;

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
