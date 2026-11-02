// ============================================================================
// File: ex_mem_reg.v
// Module: ex_mem_reg
// Description: EX/MEM Pipeline Register with Synchronous Stall & Flush Control
// ============================================================================

`timescale 1ns/1ps

module ex_mem_reg (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        stall,
    input  wire        flush,

    // Inputs from Execute Stage
    input  wire        valid_i,
    input  wire [31:0] pc_i,
    input  wire [31:0] pc_plus4_i,
    input  wire [31:0] alu_result_i,
    input  wire [31:0] mem_wdata_i,
    input  wire [4:0]  rd_i,
    input  wire [2:0]  funct3_i,
    input  wire        mem_read_i,
    input  wire        mem_write_i,
    input  wire        mem_to_reg_i,
    input  wire        reg_write_i,

    // Outputs to Memory Stage
    output reg         valid_o,
    output reg  [31:0] pc_o,
    output reg  [31:0] pc_plus4_o,
    output reg  [31:0] alu_result_o,
    output reg  [31:0] mem_wdata_o,
    output reg  [4:0]  rd_o,
    output reg  [2:0]  funct3_o,
    output reg         mem_read_o,
    output reg         mem_write_o,
    output reg         mem_to_reg_o,
    output reg         reg_write_o
);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            valid_o      <= 1'b0;
            pc_o         <= 32'h0;
            pc_plus4_o   <= 32'h0;
            alu_result_o <= 32'h0;
            mem_wdata_o  <= 32'h0;
            rd_o         <= 5'h0;
            funct3_o     <= 3'b0;
            mem_read_o   <= 1'b0;
            mem_write_o  <= 1'b0;
            mem_to_reg_o <= 1'b0;
            reg_write_o  <= 1'b0;
        end else if (flush) begin
            valid_o      <= 1'b0;
            pc_o         <= 32'h0;
            pc_plus4_o   <= 32'h0;
            alu_result_o <= 32'h0;
            mem_wdata_o  <= 32'h0;
            rd_o         <= 5'h0;
            funct3_o     <= 3'b0;
            mem_read_o   <= 1'b0;
            mem_write_o  <= 1'b0;
            mem_to_reg_o <= 1'b0;
            reg_write_o  <= 1'b0;
        end else if (!stall) begin
            valid_o      <= valid_i;
            pc_o         <= pc_i;
            pc_plus4_o   <= pc_plus4_i;
            alu_result_o <= alu_result_i;
            mem_wdata_o  <= mem_wdata_i;
            rd_o         <= rd_i;
            funct3_o     <= funct3_i;
            mem_read_o   <= mem_read_i;
            mem_write_o  <= mem_write_i;
            mem_to_reg_o <= mem_to_reg_i;
            reg_write_o  <= reg_write_i;
        end
    end

endmodule
