// ============================================================================
// File: mem_wb_reg.v
// Description: MEM/WB Pipeline Register with Synchronous Stall
// Project: Pipelined RV32IM RISC-V Core (Feature 1: 5-Stage Upgrade)
// ============================================================================

`timescale 1ns/1ps

module mem_wb_reg (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        stall,   // Active high: hold pipeline register

    // Control Signals from MEM
    input  wire        mem_to_reg_i,
    input  wire        reg_write_i,
    input  wire [2:0]  funct3_i,
    input  wire [1:0]  byte_offset_i,

    // Data Signals from MEM
    input  wire [31:0] alu_result_i,
    input  wire [31:0] mem_rdata_i,
    input  wire [4:0]  rd_i,
    input  wire [31:0] pc_plus4_i,

    // Control Outputs to WB
    output reg         mem_to_reg_o,
    output reg         reg_write_o,
    output reg  [2:0]  funct3_o,
    output reg  [1:0]  byte_offset_o,

    // Data Outputs to WB
    output reg  [31:0] alu_result_o,
    output reg  [31:0] mem_rdata_o,
    output reg  [4:0]  rd_o,
    output reg  [31:0] pc_plus4_o
);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            mem_to_reg_o  <= 1'b0;
            reg_write_o   <= 1'b0;
            funct3_o      <= 3'b000;
            byte_offset_o <= 2'b00;
            alu_result_o  <= 32'h0;
            mem_rdata_o   <= 32'h0;
            rd_o          <= 5'h0;
            pc_plus4_o    <= 32'h0;
        end else if (!stall) begin
            mem_to_reg_o  <= mem_to_reg_i;
            reg_write_o   <= reg_write_i;
            funct3_o      <= funct3_i;
            byte_offset_o <= byte_offset_i;
            alu_result_o  <= alu_result_i;
            mem_rdata_o   <= mem_rdata_i;
            rd_o          <= rd_i;
            pc_plus4_o    <= pc_plus4_i;
        end
    end

endmodule
