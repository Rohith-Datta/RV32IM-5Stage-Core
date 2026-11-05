// ============================================================================
// File: fetch_stage.v
// Module: fetch_stage
// Description: Instruction Fetch Stage with Static 32-Entry BTB Branch Prediction
//              and Interface to L1 Instruction Cache.
// Priority for Next PC:
//   1. ex_mispredict: Redirect to ex_redirect_pc (Highest priority recovery)
//   2. btb_hit && pred_taken: Speculative jump to pred_target (0-cycle penalty)
//   3. Default: Sequential fetch pc + 4
// ============================================================================

`timescale 1ns/1ps

module fetch_stage (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        stall_if,
    input  wire        bp_bypass_i,

    // Resolution & Recovery Interface from Execute Stage
    input  wire        ex_mispredict,
    input  wire [31:0] ex_redirect_pc,
    input  wire        btb_update_en,
    input  wire [31:0] btb_update_pc,
    input  wire [31:0] btb_update_target,
    input  wire        btb_update_taken,

    // Interface with L1 I-Cache
    output wire [31:0] icache_fetch_addr,
    input  wire [31:0] icache_rdata,

    // Outputs to IF/ID Pipeline Register
    output reg  [31:0] pc_o,
    output wire [31:0] pc_plus4_o,
    output wire [31:0] instruction_o,
    output wire        pred_hit_o,
    output wire        pred_taken_o,
    output wire [31:0] pred_target_o
);

    // PC + 4 Adder
    assign pc_plus4_o = pc_o + 32'd4;

    // ------------------------------------------------------------------------
    // BTB Branch Target Buffer Instantiation
    // ------------------------------------------------------------------------
    wire        btb_pred_hit;
    wire        btb_pred_taken;
    wire [31:0] btb_pred_target;

    btb_branch_pred #(
        .ENTRIES(32),
        .TAG_WIDTH(25)
    ) u_btb (
        .clk           (clk),
        .reset_n       (reset_n),
        .fetch_pc      (pc_o),
        .pred_hit      (btb_pred_hit),
        .pred_taken    (btb_pred_taken),
        .pred_target   (btb_pred_target),
        .update_en     (btb_update_en),
        .update_pc     (btb_update_pc),
        .update_target (btb_update_target),
        .update_taken  (btb_update_taken)
    );

    assign pred_hit_o    = btb_pred_hit && !stall_if && !bp_bypass_i;
    assign pred_taken_o  = btb_pred_taken && !stall_if && !bp_bypass_i;
    assign pred_target_o = bp_bypass_i ? pc_plus4_o : btb_pred_target;

    // ------------------------------------------------------------------------
    // Prioritized Next-PC Multiplexer
    // ------------------------------------------------------------------------
    reg [31:0] pc_next;

    always @(*) begin
        if (ex_mispredict) begin
            // Highest priority: flush recovery to calculated target or pc+4
            pc_next = ex_redirect_pc;
        end else if (!bp_bypass_i && btb_pred_hit && btb_pred_taken) begin
            // Zero-bubble speculative branch redirection from BTB
            pc_next = btb_pred_target;
        end else begin
            // Default sequential execution
            pc_next = pc_plus4_o;
        end
    end

    // ------------------------------------------------------------------------
    // Program Counter Register
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            pc_o <= 32'h0000_0000;
        end else if (ex_mispredict || !stall_if) begin
            pc_o <= pc_next;
        end
    end

    // Instruction address to I-Cache
    assign icache_fetch_addr = pc_o;
    assign instruction_o     = icache_rdata;

endmodule
