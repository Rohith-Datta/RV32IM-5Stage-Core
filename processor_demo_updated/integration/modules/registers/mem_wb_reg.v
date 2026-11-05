// ============================================================================
// File: mem_wb_reg.v
// Module: mem_wb_reg
// Description: MEM/WB Pipeline Register with Synchronous Stall & Flush Control
// ============================================================================

`timescale 1ns/1ps

module mem_wb_reg (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        stall,
    input  wire        flush,

    // Inputs from Memory Stage
    input  wire        valid_i,
    input  wire [31:0] pc_i,
    input  wire [31:0] alu_result_i,
    input  wire [31:0] mem_rdata_i,
    input  wire [5:0]  rd_i,
    input  wire [2:0]  funct3_i,
    input  wire        mem_to_reg_i,
    input  wire        reg_write_i,

    // Outputs to Writeback Stage
    output reg         valid_o,
    output reg  [31:0] pc_o,
    output reg  [31:0] alu_result_o,
    output reg  [31:0] mem_rdata_o,
    output reg  [5:0]  rd_o,
    output reg  [2:0]  funct3_o,
    output reg         mem_to_reg_o,
    output reg         reg_write_o
);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            valid_o      <= 1'b0;
            pc_o         <= 32'h0;
            alu_result_o <= 32'h0;
            mem_rdata_o  <= 32'h0;
            rd_o         <= 5'h0;
            funct3_o     <= 3'b0;
            mem_to_reg_o <= 1'b0;
            reg_write_o  <= 1'b0;
        end else if (flush) begin
            valid_o      <= 1'b0;
            pc_o         <= 32'h0;
            alu_result_o <= 32'h0;
            mem_rdata_o  <= 32'h0;
            rd_o         <= 5'h0;
            funct3_o     <= 3'b0;
            mem_to_reg_o <= 1'b0;
            reg_write_o  <= 1'b0;
        end else if (!stall) begin
            valid_o      <= valid_i;
            pc_o         <= pc_i;
            alu_result_o <= alu_result_i;
            mem_rdata_o  <= mem_rdata_i;
            rd_o         <= rd_i;
            funct3_o     <= funct3_i;
            mem_to_reg_o <= mem_to_reg_i;
            reg_write_o  <= reg_write_i;
        end
    end

endmodule
