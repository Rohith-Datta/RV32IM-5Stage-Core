// ============================================================================
// File: decode_stage.v
// Module: decode_stage
// Description: Fully Integrated Instruction Decode Stage & Register File
//              Supports RV32I, RV32M, RV32F, RV32Zbb, and SYSTEM CSR Instructions
//              Strictly Collision-Free Opcode & Function Decoding
// ============================================================================

`timescale 1ns/1ps

module decode_stage (
    input  wire        clk,
    input  wire        reset_n,

    // Instruction and PC from IF/ID
    input  wire [31:0] instruction_i,
    input  wire [31:0] pc_i,

    // Writeback Interface from WB stage
    input  wire        wb_reg_write_i,
    input  wire [5:0]  wb_dest_reg_i,
    input  wire [31:0] wb_data_i,

    // Decoded Control Signals to ID/EX
    output reg  [2:0]  alu_op_o,
    output reg         arithsubtype_o,
    output reg         alu_o,
    output reg         lui_o,
    output reg         auipc_o,
    output reg         jal_o,
    output reg         jalr_o,
    output reg         branch_o,
    output reg         mem_read_o,
    output reg         mem_write_o,
    output reg         mem_to_reg_o,
    output reg         reg_write_o,
    output reg         immediate_sel_o,
    output reg         is_mul_o,
    output reg         is_div_o,
    output reg         is_fpu_o,
    output reg         is_csr_o,
    output reg  [11:0] csr_addr_o,
    output reg         illegal_inst_o,

    // Decoded Data Signals to ID/EX
    output wire [31:0] rdata1_o,
    output wire [31:0] rdata2_o,
    output reg  [31:0] imm_o,

    // Register specifiers
    output wire [5:0]  rs1_o,
    output wire [5:0]  rs2_o,
    output wire [5:0]  rd_o,
    output wire [2:0]  funct3_o,
    output wire [6:0]  funct7_o,

    // Hazard usage indicators to Hazard Unit
    output reg         id_rs1_used_o,
    output reg         id_rs2_used_o
);

    `include "opcode.vh"

    // ------------------------------------------------------------------------
    // Field Extraction
    // ------------------------------------------------------------------------
    wire [6:0] opcode = instruction_i[`OPCODE];

    wire op_fp = opcode == OP_FP;
    wire fp_rs1 = op_fp && funct7_o != 7'b1101000 && funct7_o != 7'b1111000;
    wire fp_rs2 = opcode == STORE_FP || (op_fp && funct7_o != 7'b1101000 && funct7_o != 7'b1111000);
    wire fp_rd = opcode == LOAD_FP || (op_fp && funct7_o != 7'b1110000 && funct7_o != 7'b1100000 && funct7_o != 7'b1010000);
    assign rs1_o    = {fp_rs1, instruction_i[`RS1]};
    assign rs2_o    = {fp_rs2, instruction_i[`RS2]};
    assign rd_o     = {fp_rd, instruction_i[`RD]};
    assign funct3_o = instruction_i[`FUNC3];
    assign funct7_o = instruction_i[31:25];

    // ------------------------------------------------------------------------
    // Banked Register Storage: IDs 0..31 = x0..x31, 32..63 = f0..f31; only x0 is hardwired
    // ------------------------------------------------------------------------
    reg [31:0] regs [1:63];
    integer i;

    // Synchronous Write Port
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 1; i < 64; i = i + 1) begin
                regs[i] <= 32'h0000_0000;
            end
        end else if (wb_reg_write_i && (wb_dest_reg_i != 5'd0)) begin
            regs[wb_dest_reg_i] <= wb_data_i;
        end
    end

    // Dual Asynchronous Read Ports with Internal Bypass (WB -> ID Forwarding)
    assign rdata1_o = (rs1_o == 5'd0) ? 32'd0 :
                      (wb_reg_write_i && (wb_dest_reg_i == rs1_o)) ? wb_data_i :
                      regs[rs1_o];

    assign rdata2_o = (rs2_o == 5'd0) ? 32'd0 :
                      (wb_reg_write_i && (wb_dest_reg_i == rs2_o)) ? wb_data_i :
                      regs[rs2_o];

    // ------------------------------------------------------------------------
    // Collision-Free Instruction Decoding
    // ------------------------------------------------------------------------
    always @(*) begin
        // Default control states (safe inactive defaults)
        alu_op_o        = instruction_i[`FUNC3];
        arithsubtype_o  = instruction_i[`SUBTYPE];
        alu_o           = 1'b0;
        lui_o           = 1'b0;
        auipc_o         = 1'b0;
        jal_o           = 1'b0;
        jalr_o          = 1'b0;
        branch_o        = 1'b0;
        mem_read_o      = 1'b0;
        mem_write_o     = 1'b0;
        mem_to_reg_o    = 1'b0;
        reg_write_o     = 1'b0;
        immediate_sel_o = 1'b0;
        is_mul_o        = 1'b0;
        is_div_o        = 1'b0;
        is_fpu_o        = 1'b0;
        is_csr_o        = 1'b0;
        csr_addr_o      = 12'h000;
        illegal_inst_o  = 1'b0;
        imm_o           = 32'h0000_0000;
        id_rs1_used_o   = 1'b0;
        id_rs2_used_o   = 1'b0;

        case (opcode)
            // ----------------------------------------------------------------
            // 1. ARITHR (0110011): Base Integer, M-Extension, and Zbb R-type
            // ----------------------------------------------------------------
            ARITHR: begin
                reg_write_o   = 1'b1;
                id_rs1_used_o = 1'b1;
                id_rs2_used_o = 1'b1;

                if (funct7_o == FUNCT7_M_EXT) begin
                    // RV32M Extension
                    if (instruction_i[14] == 1'b0) begin
                        // MUL, MULH, MULHSU, MULHU
                        is_mul_o = 1'b1;
                        alu_o    = 1'b0;
                    end else begin
                        // DIV, DIVU, REM, REMU
                        is_div_o = 1'b1;
                        alu_o    = 1'b0;
                    end
                end else begin
                    // Base RV32I R-type or Zbb R-type (andn, orn, xnor, min, max, rol, ror, zext.h)
                    alu_o = 1'b1;
                end
            end

            // ----------------------------------------------------------------
            // 2. ARITHI (0010011): Base Immediate Arithmetic & Zbb I-type
            // ----------------------------------------------------------------
            ARITHI: begin
                alu_o           = 1'b1;
                reg_write_o     = 1'b1;
                immediate_sel_o = 1'b1;
                id_rs1_used_o   = 1'b1;

                if (instruction_i[`FUNC3] == SLL || instruction_i[`FUNC3] == SR) begin
                    // Shift immediate or Zbb bit operations (rev8, orc.b, rori, clz, ctz, cpop, sext)
                    imm_o = {{20{instruction_i[31]}}, instruction_i[31:20]};
                end else begin
                    imm_o          = {{20{instruction_i[31]}}, instruction_i[31:20]};
                    arithsubtype_o = 1'b0;
                end
            end

            // ----------------------------------------------------------------
            // 3. OP_FP (1010011): IEEE 754 Floating-Point Unit (FADD, FSUB, FMUL, FDIV)
            // ----------------------------------------------------------------
            OP_FP: begin
                case (funct7_o)
                    FUNCT7_FADD, FUNCT7_FSUB, FUNCT7_FMUL, FUNCT7_FDIV, 7'b1101000, 7'b1111000, 7'b1110000, 7'b0010000: begin
                        is_fpu_o      = 1'b1;
                        alu_o         = 1'b0;
                        reg_write_o   = 1'b1;
                        id_rs1_used_o = 1'b1;
                        id_rs2_used_o = funct7_o != 7'b1101000 && funct7_o != 7'b1111000 && funct7_o != 7'b1110000;
                        if (funct7_o == 7'b1101000) imm_o = {27'd0, instruction_i[24:20]};
                    end
                    default: illegal_inst_o = 1'b1;
                endcase
            end

            // ----------------------------------------------------------------
            // 4. SYSTEM (1110011): Passive Performance Counters & CSR Read (Feature 8)
            // ----------------------------------------------------------------
            SYSTEM: begin
                id_rs1_used_o = !instruction_i[14] && instruction_i[14:12]!=0;
                is_csr_o        = 1'b1;
                reg_write_o     = 1'b1; // CSR read value writes to destination rd
                csr_addr_o      = instruction_i[31:20];
                immediate_sel_o = 1'b1;
                imm_o           = {20'h0, instruction_i[31:20]};
            end

            // ----------------------------------------------------------------
            // 5. Memory Loads (0000011) & Floating-Point Load FLW (0000111)
            // ----------------------------------------------------------------
            LOAD, LOAD_FP: begin
                mem_read_o      = 1'b1;
                mem_to_reg_o    = 1'b1;
                reg_write_o     = 1'b1;
                immediate_sel_o = 1'b1;
                id_rs1_used_o   = 1'b1;
                imm_o           = {{20{instruction_i[31]}}, instruction_i[31:20]};
            end

            // ----------------------------------------------------------------
            // 6. Memory Stores (0100011) & Floating-Point Store FSW (0100111)
            // ----------------------------------------------------------------
            STORE, STORE_FP: begin
                mem_write_o     = 1'b1;
                immediate_sel_o = 1'b1;
                id_rs1_used_o   = 1'b1;
                id_rs2_used_o   = 1'b1;
                imm_o           = {{20{instruction_i[31]}}, instruction_i[31:25], instruction_i[11:7]};
            end

            // ----------------------------------------------------------------
            // 7. Conditional Branch (1100011)
            // ----------------------------------------------------------------
            BRANCH: begin
                branch_o      = 1'b1;
                id_rs1_used_o = 1'b1;
                id_rs2_used_o = 1'b1;
                imm_o         = {{20{instruction_i[31]}}, instruction_i[7], instruction_i[30:25], instruction_i[11:8], 1'b0};
            end

            // ----------------------------------------------------------------
            // 8. Upper Immediate Instructions (LUI & AUIPC)
            // ----------------------------------------------------------------
            LUI: begin
                lui_o           = 1'b1;
                reg_write_o     = 1'b1;
                immediate_sel_o = 1'b1;
                imm_o           = {instruction_i[31:12], 12'b0};
            end

            AUIPC: begin
                auipc_o         = 1'b1;
                reg_write_o     = 1'b1;
                immediate_sel_o = 1'b1;
                imm_o           = {instruction_i[31:12], 12'b0};
            end

            // ----------------------------------------------------------------
            // 9. Unconditional Jumps (JAL & JALR)
            // ----------------------------------------------------------------
            JAL: begin
                jal_o       = 1'b1;
                reg_write_o = 1'b1;
                imm_o       = {{12{instruction_i[31]}}, instruction_i[19:12], instruction_i[20], instruction_i[30:21], 1'b0};
            end

            JALR: begin
                jalr_o          = 1'b1;
                reg_write_o     = 1'b1;
                immediate_sel_o = 1'b1;
                id_rs1_used_o   = 1'b1;
                imm_o           = {{20{instruction_i[31]}}, instruction_i[31:20]};
            end

            // Default: Illegal / Unimplemented Instruction
            default: begin
                illegal_inst_o = 1'b1;
            end
        endcase
    end

endmodule
