// ============================================================================
// File: if_id_reg.v
// Module: if_id_reg
// Description: IF/ID Pipeline Register with Synchronous Stall & Flush Control
// ============================================================================

`timescale 1ns/1ps

module if_id_reg (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        stall,
    input  wire        flush,

    // Inputs from Fetch Stage
    input  wire        valid_i,
    input  wire [31:0] pc_i,
    input  wire [31:0] pc_plus4_i,
    input  wire [31:0] instruction_i,
    input  wire        pred_hit_i,
    input  wire        pred_taken_i,
    input  wire [31:0] pred_target_i,

    // Outputs to Decode Stage
    output reg         valid_o,
    output reg  [31:0] pc_o,
    output reg  [31:0] pc_plus4_o,
    output reg  [31:0] instruction_o,
    output reg         pred_hit_o,
    output reg         pred_taken_o,
    output reg  [31:0] pred_target_o
);

    `include "opcode.vh"

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            valid_o       <= 1'b0;
            pc_o          <= 32'h0;
            pc_plus4_o    <= 32'h0;
            instruction_o <= NOP;
            pred_hit_o    <= 1'b0;
            pred_taken_o  <= 1'b0;
            pred_target_o <= 32'h0;
        end else if (flush) begin
            valid_o       <= 1'b0;
            pc_o          <= 32'h0;
            pc_plus4_o    <= 32'h0;
            instruction_o <= NOP;
            pred_hit_o    <= 1'b0;
            pred_taken_o  <= 1'b0;
            pred_target_o <= 32'h0;
        end else if (!stall) begin
            valid_o       <= valid_i;
            pc_o          <= pc_i;
            pc_plus4_o    <= pc_plus4_i;
            instruction_o <= instruction_i;
            pred_hit_o    <= pred_hit_i;
            pred_taken_o  <= pred_taken_i;
            pred_target_o <= pred_target_i;
        end
    end

endmodule
