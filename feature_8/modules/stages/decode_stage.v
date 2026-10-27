// ============================================================================
// File: decode_stage.v (Feature 8: Passive Performance CSRs & Counters)
// Description: Instruction Decode & Register File with RV32IMF + SYSTEM CSR Decoding
// Project: Pipelined RV32IMF RISC-V Core (Feature 8: Passive CSRs)
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
    input  wire [4:0]  wb_dest_reg_i,
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
    output reg         illegal_inst_o,

    // Feature 8 CSR Control Signals
    output reg         is_csr_o,
    output reg  [11:0] csr_addr_o,

    // Decoded Data Signals to ID/EX
    output wire [31:0] rdata1_o,
    output wire [31:0] rdata2_o,
    output reg  [31:0] imm_o,

    // Register specifiers
    output wire [4:0]  rs1_o,
    output wire [4:0]  rs2_o,
    output wire [4:0]  rd_o,
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
    assign rs1_o    = instruction_i[`RS1];
    assign rs2_o    = instruction_i[`RS2];
    assign rd_o     = instruction_i[`RD];
    assign funct3_o = instruction_i[`FUNC3];
    assign funct7_o = instruction_i[31:25];

    wire [6:0] opcode = instruction_i[`OPCODE];

    // ------------------------------------------------------------------------
    // Register File (32 x 32-bit, x0 hardwired to 0)
    // ------------------------------------------------------------------------
    reg [31:0] regs [1:31];
    integer i;

    // Synchronous Write Port
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 1; i < 32; i = i + 1) begin
                regs[i] <= 32'h0;
            end
        end else if (wb_reg_write_i && (wb_dest_reg_i != 5'd0)) begin
            regs[wb_dest_reg_i] <= wb_data_i;
        end
    end

    // Dual Asynchronous Read Ports with Internal Forwarding (WB -> ID)
    assign rdata1_o = (rs1_o == 5'd0) ? 32'd0 :
                      (wb_reg_write_i && (wb_dest_reg_i == rs1_o)) ? wb_data_i :
                      regs[rs1_o];

    assign rdata2_o = (rs2_o == 5'd0) ? 32'd0 :
                      (wb_reg_write_i && (wb_dest_reg_i == rs2_o)) ? wb_data_i :
                      regs[rs2_o];

    // ------------------------------------------------------------------------
    // Control Signal Decoding and Immediate Generation
    // ------------------------------------------------------------------------
    always @(*) begin
        // Defaults
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
        imm_o           = 32'h0;
        id_rs1_used_o   = 1'b0;
        id_rs2_used_o   = 1'b0;

        case (opcode)
            ARITHR: begin
                if (instruction_i[31:25] == FUNCT7_M_EXT) begin
                    if (instruction_i[14] == 1'b0) begin
                        // RV32M Hardware Multiplication (MUL, MULH, MULHSU, MULHU)
                        is_mul_o      = 1'b1;
                        alu_o         = 1'b0;
                        reg_write_o   = 1'b1;
                        id_rs1_used_o = 1'b1;
                        id_rs2_used_o = 1'b1;
                    end else begin
                        // RV32M Hardware Division (DIV, DIVU, REM, REMU)
                        is_div_o      = 1'b1;
                        alu_o         = 1'b0;
                        reg_write_o   = 1'b1;
                        id_rs1_used_o = 1'b1;
                        id_rs2_used_o = 1'b1;
                    end
                end else begin
                    alu_o         = 1'b1;
                    reg_write_o   = 1'b1;
                    id_rs1_used_o = 1'b1;
                    id_rs2_used_o = 1'b1;
                end
            end

            OP_FP: begin
                // RV32F IEEE 754 Floating Point (FADD.S, FSUB.S, FMUL.S, FDIV.S)
                is_fpu_o      = 1'b1;
                alu_o         = 1'b0;
                reg_write_o   = 1'b1;
                id_rs1_used_o = 1'b1;
                id_rs2_used_o = 1'b1;
            end

            ARITHI: begin
                alu_o           = 1'b1;
                reg_write_o     = 1'b1;
                immediate_sel_o = 1'b1;
                id_rs1_used_o   = 1'b1;
                if (instruction_i[`FUNC3] == SLL || instruction_i[`FUNC3] == SR) begin
                    imm_o = {27'h0, instruction_i[24:20]};
                end else begin
                    imm_o = {{20{instruction_i[31]}}, instruction_i[31:20]};
                    arithsubtype_o = 1'b0;
                end
            end

            LOAD: begin
                mem_read_o      = 1'b1;
                mem_to_reg_o    = 1'b1;
                reg_write_o     = 1'b1;
                immediate_sel_o = 1'b1;
                id_rs1_used_o   = 1'b1;
                imm_o           = {{20{instruction_i[31]}}, instruction_i[31:20]};
            end

            STORE: begin
                mem_write_o     = 1'b1;
                immediate_sel_o = 1'b1;
                id_rs1_used_o   = 1'b1;
                id_rs2_used_o   = 1'b1;
                imm_o           = {{20{instruction_i[31]}}, instruction_i[31:25], instruction_i[11:7]};
            end

            BRANCH: begin
                branch_o      = 1'b1;
                id_rs1_used_o = 1'b1;
                id_rs2_used_o = 1'b1;
                imm_o         = {{20{instruction_i[31]}}, instruction_i[7], instruction_i[30:25], instruction_i[11:8], 1'b0};
            end

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

            ////////////////////////////////////////////////////////////////////
            // TODO: Feature 8 RISC-V SYSTEM / CSR Instruction Decoding
            //
            // Instructions:
            //   When opcode == SYSTEM (7'b1110011):
            //     1. Assert is_csr_o = 1'b1
            //     2. Assert reg_write_o = 1'b1 (the read CSR value writes to rd)
            //     3. Extract 12-bit CSR address: instruction_i[31:20]
            //     4. Set immediate_sel_o = 1'b1
            //     5. Immediate is zero-extended CSR address: {20'h0, instruction_i[31:20]}
            ////////////////////////////////////////////////////////////////////
            SYSTEM: begin
                is_csr_o        = /* TODO: 1'b1 */                     1'b1;
                reg_write_o     = /* TODO: 1'b1 */                     1'b1;
                csr_addr_o      = /* TODO: instruction_i[31:20] */      instruction_i[31:20];
                immediate_sel_o = 1'b1;
                imm_o           = {20'h0, instruction_i[31:20]};
            end

            default: begin
                illegal_inst_o = 1'b1;
            end
        endcase
    end

endmodule
