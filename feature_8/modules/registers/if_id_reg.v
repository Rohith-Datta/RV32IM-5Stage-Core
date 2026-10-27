// ============================================================================
// File: if_id_reg.v
// Module: if_id_reg (Feature 7: BTB Branch Prediction Aware)
// Description: IF/ID Pipeline Register with Synchronous Stall & Flush
// ============================================================================

`timescale 1ns/1ps

module if_id_reg
#(
    parameter [31:0] RESET_PC = 32'h0000_0000
)
(
    input  wire        clk,
    input  wire        reset_n,
    input  wire        stall,
    input  wire        flush,

    // Inputs from IF Stage
    input  wire [31:0] pc_i,
    input  wire [31:0] pc_plus4_i,
    input  wire [31:0] instr_i,
    input  wire        pred_taken_i,
    input  wire [31:0] pred_target_i,

    // Outputs to ID Stage
    output reg  [31:0] pc_o,
    output reg  [31:0] pc_plus4_o,
    output reg  [31:0] instr_o,
    output reg         pred_taken_o,
    output reg  [31:0] pred_target_o
);

    `include "opcode.vh"

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            pc_o          <= RESET_PC;
            pc_plus4_o    <= RESET_PC + 32'd4;
            instr_o       <= NOP;
            pred_taken_o  <= 1'b0;
            pred_target_o <= 32'd0;
        end else if (flush) begin
            pc_o          <= 32'h0;
            pc_plus4_o    <= 32'h0;
            instr_o       <= NOP;
            pred_taken_o  <= 1'b0;
            pred_target_o <= 32'd0;
        end else if (!stall) begin
            pc_o          <= pc_i;
            pc_plus4_o    <= pc_plus4_i;
            instr_o       <= instr_i;
            pred_taken_o  <= pred_taken_i;
            pred_target_o <= pred_target_i;
        end
    end

endmodule
