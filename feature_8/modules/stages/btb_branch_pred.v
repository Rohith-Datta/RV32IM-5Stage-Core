// ============================================================================
// File: btb_branch_pred.v
// Module: btb_branch_pred
// Description: Feature 7 - Static 32-Entry Branch Target Buffer (BTB)
// Architecture:
//   - 32-entry direct-mapped buffer indexed by PC[6:2]
//   - Tag array: 25 bits (PC[31:7])
//   - Target array: 32 bits (Pre-computed destination PC)
//   - Valid array: 1 bit per entry (indicates allocated branch/jump)
// Operation:
//   - Query (IF stage): Parallel lookup using current fetch PC.
//     On hit, predicts taken and supplies target_pc with 0 bubble penalty.
//   - Update (EX stage): Evaluates actual branch condition and updates BTB.
//     On misprediction, invalidates or updates target, triggering recovery flush.
// ============================================================================

`timescale 1ns/1ps

module btb_branch_pred #(
    parameter ENTRIES   = 32,
    parameter TAG_WIDTH = 25
)(
    input  wire        clk,
    input  wire        reset_n,

    // ------------------------------------------------------------------------
    // Fetch Stage (IF) Query Interface
    // ------------------------------------------------------------------------
    input  wire [31:0] fetch_pc,        // Current PC being fetched in IF stage
    output wire        pred_hit,        // 1 if fetch_pc matches a valid BTB entry
    output wire        pred_taken,      // 1 if predicted branch taken
    output wire [31:0] pred_target,     // Predicted target PC

    // ------------------------------------------------------------------------
    // Execute Stage (EX) Update Interface
    // ------------------------------------------------------------------------
    input  wire        update_en,       // 1 if instruction in EX is a branch or jump
    input  wire [31:0] update_pc,       // PC of branch/jump in EX stage
    input  wire [31:0] update_target,   // Actual computed branch target
    input  wire        update_taken     // Actual branch decision (1=taken, 0=not taken)
);

    // 32-Entry Storage Arrays
    reg                 valid_array  [0:ENTRIES-1];
    reg [TAG_WIDTH-1:0] tag_array    [0:ENTRIES-1];
    reg [31:0]          target_array [0:ENTRIES-1];

    ////////////////////////////////////////////////////////////////////////////
    // TODO 1: Index and Tag Extraction
    //
    // - For a 32-entry table (2^5 = 32), word-aligned address PC[1:0] is ignored.
    // - Index is 5 bits: PC[6:2].
    // - Tag is upper 25 bits: PC[31:7].
    //
    // Instructions:
    //   Extract the 5-bit index and 25-bit tag for both:
    //     1. fetch_pc  (Query from IF stage)
    //     2. update_pc (Update from EX stage)
    ////////////////////////////////////////////////////////////////////////////

    wire [4:0]           fetch_index  = /* TODO: fetch_pc index [6:2] */  fetch_pc[6:2];
    wire [TAG_WIDTH-1:0] fetch_tag    = /* TODO: fetch_pc tag [31:7] */   fetch_pc[31:7];

    wire [4:0]           update_index = /* TODO: update_pc index [6:2] */ update_pc[6:2];
    wire [TAG_WIDTH-1:0] update_tag   = /* TODO: update_pc tag [31:7] */  update_pc[31:7];


    ////////////////////////////////////////////////////////////////////////////
    // TODO 2: BTB Query & Prediction Logic (IF Stage)
    //
    // - A BTB Hit occurs when:
    //     1. The indexed entry in valid_array is 1 (valid_array[fetch_index] == 1)
    //     2. AND the stored tag matches the incoming fetch_tag (tag_array[fetch_index] == fetch_tag)
    //
    // - For static branch prediction with BTB:
    //     - If it hits in BTB, predict TAKEN (pred_taken = 1), target = target_array[fetch_index].
    //     - If it misses in BTB, predict NOT TAKEN (pred_taken = 0), target = fetch_pc + 4.
    ////////////////////////////////////////////////////////////////////////////

    wire btb_hit = /* TODO: valid_array[fetch_index] && (tag_array[fetch_index] == fetch_tag) */
                   (valid_array[fetch_index] && (tag_array[fetch_index] == fetch_tag));

    assign pred_hit    = btb_hit;
    assign pred_taken  = /* TODO: btb_hit */ btb_hit;
    assign pred_target = /* TODO: btb_hit ? target_array[fetch_index] : (fetch_pc + 32'd4) */
                         btb_hit ? target_array[fetch_index] : (fetch_pc + 32'd4);


    ////////////////////////////////////////////////////////////////////////////
    // TODO 3: BTB State Allocation & Update on Clock Edge (EX Stage)
    //
    // On Reset:
    //   - Clear all valid bits in valid_array (set to 0).
    //
    // On Valid Update (update_en asserted):
    //   - If actual branch was TAKEN (update_taken == 1):
    //       1. Set valid_array[update_index] = 1'b1
    //       2. Set tag_array[update_index] = update_tag
    //       3. Set target_array[update_index] = update_target
    //   - If actual branch was NOT TAKEN (update_taken == 0):
    //       - Invalidate the entry: valid_array[update_index] = 1'b0
    ////////////////////////////////////////////////////////////////////////////

    integer i;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 0; i < ENTRIES; i = i + 1) begin
                valid_array[i]  <= /* TODO: 1'b0 */ 1'b0;
                tag_array[i]    <= {TAG_WIDTH{1'b0}};
                target_array[i] <= 32'd0;
            end
        end else if (update_en) begin
            if (update_taken) begin
                valid_array[update_index]  <= /* TODO: 1'b1 */ 1'b1;
                tag_array[update_index]    <= /* TODO: update_tag */ update_tag;
                target_array[update_index] <= /* TODO: update_target */ update_target;
            end else begin
                // Invalidate on branch not-taken
                valid_array[update_index]  <= /* TODO: 1'b0 */ 1'b0;
            end
        end
    end

endmodule
