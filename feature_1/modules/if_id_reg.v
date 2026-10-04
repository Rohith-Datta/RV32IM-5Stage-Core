// ============================================================================
// File: if_id_reg.v
// Description: IF/ID Pipeline Register with Synchronous Stall & Flush
// Project: Pipelined RV32IM RISC-V Core (Feature 1: 5-Stage Upgrade)
// ============================================================================

`timescale 1ns/1ps

module if_id_reg
#(
    parameter [31:0] RESET_PC = 32'h0000_0000
)
(
    input  wire        clk,
    input  wire        reset_n,
    input  wire        stall,   // Active high: hold pipeline stage
    input  wire        flush,   // Active high: clear stage (insert NOP bubble)

    // Inputs from IF Stage
    input  wire [31:0] pc_i,
    input  wire [31:0] pc_plus4_i,
    input  wire [31:0] instr_i,

    // Outputs to ID Stage
    output reg  [31:0] pc_o,
    output reg  [31:0] pc_plus4_o,
    output reg  [31:0] instr_o
);

    `include "opcode.vh"

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            pc_o       <= RESET_PC;
            pc_plus4_o <= RESET_PC + 32'd4;
            instr_o    <= NOP;
        end else if (flush) begin
            // Bubble insertion on branch misprediction / flush
            pc_o       <= 32'h0;
            pc_plus4_o <= 32'h0;
            instr_o    <= NOP;
        end else if (!stall) begin
            // Normal pipeline advance
            pc_o       <= pc_i;
            pc_plus4_o <= pc_plus4_i;
            instr_o    <= instr_i;
        end
        // If stall is active, maintain current values
    end

endmodule
