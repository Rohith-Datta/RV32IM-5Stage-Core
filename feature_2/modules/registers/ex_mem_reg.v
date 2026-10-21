// ============================================================================
// File: ex_mem_reg.v
// Description: EX/MEM Pipeline Register with Synchronous Stall & Flush
// Project: Pipelined RV32IM RISC-V Core (Feature 1: 5-Stage Upgrade)
// ============================================================================

`timescale 1ns/1ps

module ex_mem_reg (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        stall,   // Active high: hold pipeline register
    input  wire        flush,   // Active high: clear to bubble

    // Control Signals from EX
    input  wire        mem_read_i,
    input  wire        mem_write_i,
    input  wire        mem_to_reg_i,
    input  wire        reg_write_i,
    input  wire [2:0]  funct3_i,

    // Data Signals from EX
    input  wire [31:0] alu_result_i,
    input  wire [31:0] store_data_i,
    input  wire [4:0]  rd_i,
    input  wire [31:0] pc_i,
    input  wire [31:0] pc_plus4_i,

    // Control Outputs to MEM
    output reg         mem_read_o,
    output reg         mem_write_o,
    output reg         mem_to_reg_o,
    output reg         reg_write_o,
    output reg  [2:0]  funct3_o,

    // Data Outputs to MEM
    output reg  [31:0] alu_result_o,
    output reg  [31:0] store_data_o,
    output reg  [4:0]  rd_o,
    output reg  [31:0] pc_o,
    output reg  [31:0] pc_plus4_o
);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            mem_read_o   <= 1'b0;
            mem_write_o  <= 1'b0;
            mem_to_reg_o <= 1'b0;
            reg_write_o  <= 1'b0;
            funct3_o     <= 3'b000;
            alu_result_o <= 32'h0;
            store_data_o <= 32'h0;
            rd_o         <= 5'h0;
            pc_o         <= 32'h0;
            pc_plus4_o   <= 32'h0;
        end else if (flush) begin
            mem_read_o   <= 1'b0;
            mem_write_o  <= 1'b0;
            mem_to_reg_o <= 1'b0;
            reg_write_o  <= 1'b0;
            funct3_o     <= 3'b000;
            alu_result_o <= 32'h0;
            store_data_o <= 32'h0;
            rd_o         <= 5'h0;
            pc_o         <= 32'h0;
            pc_plus4_o   <= 32'h0;
        end else if (!stall) begin
            mem_read_o   <= mem_read_i;
            mem_write_o  <= mem_write_i;
            mem_to_reg_o <= mem_to_reg_i;
            reg_write_o  <= reg_write_i;
            funct3_o     <= funct3_i;
            alu_result_o <= alu_result_i;
            store_data_o <= store_data_i;
            rd_o         <= rd_i;
            pc_o         <= pc_i;
            pc_plus4_o   <= pc_plus4_i;
        end
    end

endmodule
