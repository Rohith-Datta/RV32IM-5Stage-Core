// ============================================================================
// File: id_ex_reg.v (Feature 4: RV32F IEEE 754 Floating-Point Unit Support)
// Description: ID/EX Pipeline Register with Synchronous Stall, Flush, & FPU Signals
// Project: Pipelined RV32IMF RISC-V Core (Feature 4: IEEE 754 FPU)
// ============================================================================

`timescale 1ns/1ps

module id_ex_reg (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        stall,   // Active high: hold pipeline register
    input  wire        flush,   // Active high: clear to bubble (NOP)

    // Control Signals from ID
    input  wire [2:0]  alu_op_i,
    input  wire        arithsubtype_i,
    input  wire        alu_i,
    input  wire        lui_i,
    input  wire        auipc_i,
    input  wire        jal_i,
    input  wire        jalr_i,
    input  wire        branch_i,
    input  wire        mem_read_i,
    input  wire        mem_write_i,
    input  wire        mem_to_reg_i,
    input  wire        reg_write_i,
    input  wire        immediate_sel_i,
    input  wire        is_mul_i,
    input  wire        is_div_i,
    input  wire        is_fpu_i,
    input  wire        illegal_inst_i,

    // Data Signals from ID
    input  wire [31:0] pc_i,
    input  wire [31:0] pc_plus4_i,
    input  wire [31:0] rdata1_i,
    input  wire [31:0] rdata2_i,
    input  wire [31:0] imm_i,

    // Register specifiers
    input  wire [4:0]  rs1_i,
    input  wire [4:0]  rs2_i,
    input  wire [4:0]  rd_i,
    input  wire [2:0]  funct3_i,
    input  wire [6:0]  funct7_i,
    // WB Snooping during stalls to update stale operands
    input  wire        wb_reg_write_i,
    input  wire [4:0]  wb_dest_reg_i,
    input  wire [31:0] wb_data_i,

    // Control Outputs to EX
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

    // Data Outputs to EX
    output reg  [31:0] pc_o,
    output reg  [31:0] pc_plus4_o,
    output reg  [31:0] rdata1_o,
    output reg  [31:0] rdata2_o,
    output reg  [31:0] imm_o,

    // Register specifiers to EX / Hazard Unit
    output reg  [4:0]  rs1_o,
    output reg  [4:0]  rs2_o,
    output reg  [4:0]  rd_o,
    output reg  [2:0]  funct3_o,
    output reg  [6:0]  funct7_o
);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            alu_op_o        <= 3'b000;
            arithsubtype_o  <= 1'b0;
            alu_o           <= 1'b0;
            lui_o           <= 1'b0;
            auipc_o         <= 1'b0;
            jal_o           <= 1'b0;
            jalr_o          <= 1'b0;
            branch_o        <= 1'b0;
            mem_read_o      <= 1'b0;
            mem_write_o     <= 1'b0;
            mem_to_reg_o    <= 1'b0;
            reg_write_o     <= 1'b0;
            immediate_sel_o <= 1'b0;
            is_mul_o        <= 1'b0;
            is_div_o        <= 1'b0;
            is_fpu_o        <= 1'b0;
            illegal_inst_o  <= 1'b0;

            pc_o            <= 32'h0;
            pc_plus4_o      <= 32'h0;
            rdata1_o        <= 32'h0;
            rdata2_o        <= 32'h0;
            imm_o           <= 32'h0;

            rs1_o           <= 5'd0;
            rs2_o           <= 5'd0;
            rd_o            <= 5'd0;
            funct3_o        <= 3'b000;
            funct7_o        <= 7'b0000000;
        end else if (flush) begin
            alu_op_o        <= 3'b000;
            arithsubtype_o  <= 1'b0;
            alu_o           <= 1'b0;
            lui_o           <= 1'b0;
            auipc_o         <= 1'b0;
            jal_o           <= 1'b0;
            jalr_o          <= 1'b0;
            branch_o        <= 1'b0;
            mem_read_o      <= 1'b0;
            mem_write_o     <= 1'b0;
            mem_to_reg_o    <= 1'b0;
            reg_write_o     <= 1'b0;
            immediate_sel_o <= 1'b0;
            is_mul_o        <= 1'b0;
            is_div_o        <= 1'b0;
            is_fpu_o        <= 1'b0;
            illegal_inst_o  <= 1'b0;

            pc_o            <= 32'h0;
            pc_plus4_o      <= 32'h0;
            rdata1_o        <= 32'h0;
            rdata2_o        <= 32'h0;
            imm_o           <= 32'h0;

            rs1_o           <= 5'd0;
            rs2_o           <= 5'd0;
            rd_o            <= 5'd0;
            funct3_o        <= 3'b000;
            funct7_o        <= 7'b0000000;
        end else if (!stall) begin
            alu_op_o        <= alu_op_i;
            arithsubtype_o  <= arithsubtype_i;
            alu_o           <= alu_i;
            lui_o           <= lui_i;
            auipc_o         <= auipc_i;
            jal_o           <= jal_i;
            jalr_o          <= jalr_i;
            branch_o        <= branch_i;
            mem_read_o      <= mem_read_i;
            mem_write_o     <= mem_write_i;
            mem_to_reg_o    <= mem_to_reg_i;
            reg_write_o     <= reg_write_i;
            immediate_sel_o <= immediate_sel_i;
            is_mul_o        <= is_mul_i;
            is_div_o        <= is_div_i;
            is_fpu_o        <= is_fpu_i;
            illegal_inst_o  <= illegal_inst_i;

            pc_o            <= pc_i;
            pc_plus4_o      <= pc_plus4_i;
            rdata1_o        <= rdata1_i;
            rdata2_o        <= rdata2_i;
            imm_o           <= imm_i;

            rs1_o           <= rs1_i;
            rs2_o           <= rs2_i;
            rd_o            <= rd_i;
            funct3_o        <= funct3_i;
            funct7_o        <= funct7_i;
        end else begin
            // While stalled, snoop WB writeback to update any operand that was
            // sampled before an in-flight producer committed to the register file.
            if (wb_reg_write_i && (wb_dest_reg_i != 5'd0)) begin
                if (wb_dest_reg_i == rs1_o) rdata1_o <= wb_data_i;
                if (wb_dest_reg_i == rs2_o) rdata2_o <= wb_data_i;
            end
        end
    end

endmodule
