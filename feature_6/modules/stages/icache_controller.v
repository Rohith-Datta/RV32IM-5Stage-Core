// ============================================================================
// File: icache_controller.v
// Module: icache_controller
// Description: Direct-Mapped 2 KB L1 Instruction Cache with 10-Cycle Miss FSM,
//              Hardware Burst Refill, Flush On Branch, and Cache Bypass Mode.
// Project: Pipelined RV32IMF RISC-V Core (Feature 6: L1 I-Cache)
//
// Architecture Specifications:
//   - Organization:       Direct-Mapped Instruction Cache (Read-Only)
//   - Capacity:           2 KB (128 lines x 4 words/line x 4 bytes/word)
//   - Line Size:          16 bytes (4 words / 128 bits)
//   - Tag Width:          21 bits [31:11]
//   - Index Width:        7 bits  [10:4]
//   - Word Offset:        2 bits  [3:2]
//   - Byte Offset:        2 bits  [1:0] (ignored for word fetches)
//   - Hit Latency:        1 cycle (combinational SRAM read, zero stall)
//   - Miss Penalty:       10 cycles (burst refill FSM: 4 words from IMEM)
//   - Cache Bypass Mode:  When cache_bypass_i = 1, each fetch incurs 10 cycles
//                         directly from backing memory without line caching.
//   - Flush Support:      Active-high flush_i resets FSM to IDLE upon branch/jump.
//
// 32-Bit Address Breakdown:
//   31                            11 10            4 3           2 1           0
//   +-------------------------------+---------------+-------------+-------------+
//   |          TAG (21 bits)        | INDEX (7 bits)|  WO (2 bits)| BO (2 bits) |
//   +-------------------------------+---------------+-------------+-------------+
// ============================================================================

`timescale 1ns/1ps

module icache_controller #(
    parameter NUM_LINES      = 128,   // 128 cache lines
    parameter WORDS_PER_LINE = 4,     // 4 words (16 bytes) per line
    parameter ADDR_WIDTH     = 32,
    parameter TAG_WIDTH      = 21,    // [31:11]
    parameter INDEX_WIDTH    = 7,     // [10:4]
    parameter OFFSET_WIDTH   = 2      // [3:2]
)(
    input  wire        clk,
    input  wire        reset_n,
    input  wire        flush_i,          // Flushes refill FSM on branch/jump in EX stage
    input  wire        counter_reset_i,  // Resets diagnostic performance counters

    // Cache Bypass Control (1 = Bypass cache to evaluate uncached penalty, 0 = Normal L1)
    input  wire        cache_bypass_i,

    // CPU-side interface (from/to pipeline IF stage)
    input  wire [31:0] cpu_addr,         // Fetch PC from Fetch Stage
    output wire [31:0] cpu_rdata,        // Fetched instruction to IF/ID register
    output wire        icache_stall,     // 1 = miss in progress, freezes PC

    // Backing memory interface (to backing instr_mem model / main memory)
    output wire [31:0] mem_addr,         // Burst address to backing memory
    input  wire [31:0] mem_rdata,        // Read word from backing memory
    output wire        mem_req,          // Memory read strobe

    // Diagnostic & performance observation signals
    output wire        cache_hit,
    output wire        cache_miss,
    output reg  [31:0] hit_count,
    output reg  [31:0] miss_count
);

    // ------------------------------------------------------------------------
    // Cache Storage Arrays
    // ------------------------------------------------------------------------
    // Tag array: 128 lines x 21 bits (Distributed LUT RAM)
    reg [TAG_WIDTH-1:0] tag_array [0:NUM_LINES-1];

    // Valid array: 128 lines x 1 bit
    reg valid_array [0:NUM_LINES-1];

    // Data array: 128 lines x 4 words = 512 words (4 BRAM banks, 1 bank per word offset)
    (* ram_style = "block" *) reg [31:0] data_mem0 [0:NUM_LINES-1];
    (* ram_style = "block" *) reg [31:0] data_mem1 [0:NUM_LINES-1];
    (* ram_style = "block" *) reg [31:0] data_mem2 [0:NUM_LINES-1];
    (* ram_style = "block" *) reg [31:0] data_mem3 [0:NUM_LINES-1];

    // ------------------------------------------------------------------------
    // Address Field Extraction
    // ------------------------------------------------------------------------
    wire [TAG_WIDTH-1:0]    curr_tag    = cpu_addr[31:11];
    wire [INDEX_WIDTH-1:0]  curr_index  = cpu_addr[10:4];
    wire [OFFSET_WIDTH-1:0] curr_offset = cpu_addr[3:2];

    // Tag comparison and valid check
    wire                   line_valid = valid_array[curr_index];
    wire [TAG_WIDTH-1:0]   line_tag   = tag_array[curr_index];

    wire bypass_act = (cache_bypass_i === 1'b1);
    wire flush_act  = (flush_i === 1'b1);

    // When cache_bypass_i is active, hit condition is NEVER met
    wire hit_condition  = !bypass_act && line_valid && (line_tag == curr_tag);
    wire miss_condition = bypass_act || !hit_condition;

    // ------------------------------------------------------------------------
    // FSM States
    // ------------------------------------------------------------------------
    localparam STATE_IDLE   = 2'b00;
    localparam STATE_REFILL = 2'b01;
    localparam STATE_BYPASS = 2'b10;

    reg [1:0]  state;
    reg [3:0]  refill_cnt;
    reg [31:0] latched_pc;
    reg [31:0] bypass_word;

    wire [INDEX_WIDTH-1:0]  refill_index  = latched_pc[10:4];
    wire [TAG_WIDTH-1:0]    refill_tag    = latched_pc[31:11];
    wire [OFFSET_WIDTH-1:0] refill_offset = latched_pc[3:2];

    // Combinational hit/miss status
    assign cache_hit  = (state == STATE_IDLE) && hit_condition && reset_n;
    assign cache_miss = (state == STATE_REFILL) || ((state == STATE_IDLE) && miss_condition && reset_n);

    // Pipeline stall: assert combinationally on miss in IDLE, hold through REFILL.
    // In STATE_BYPASS, deassert stall for exactly 1 cycle so IF/ID captures instruction!
    assign icache_stall = (state == STATE_BYPASS) ? 1'b0 : cache_miss;

    // Combinational word selection from line for 1-cycle hit
    wire [31:0] line_w0 = data_mem0[curr_index];
    wire [31:0] line_w1 = data_mem1[curr_index];
    wire [31:0] line_w2 = data_mem2[curr_index];
    wire [31:0] line_w3 = data_mem3[curr_index];

    reg [31:0] selected_word;
    always @(*) begin
        case (curr_offset)
            2'b00:   selected_word = line_w0;
            2'b01:   selected_word = line_w1;
            2'b10:   selected_word = line_w2;
            2'b11:   selected_word = line_w3;
            default: selected_word = 32'h0000_0013;
        endcase
    end

    // Instruction output: valid on hit, bypass word during bypass release, NOP during stall
    assign cpu_rdata = (state == STATE_BYPASS) ? bypass_word :
                       cache_hit               ? selected_word :
                                                 32'h0000_0013; // NOP during refill stall

    // ------------------------------------------------------------------------
    // Backing Memory Burst Request Logic
    // ------------------------------------------------------------------------
    reg [1:0] burst_word_sel;
    always @(*) begin
        case (refill_cnt)
            4'd2, 4'd3: burst_word_sel = 2'b00;
            4'd4:       burst_word_sel = 2'b01;
            4'd5:       burst_word_sel = 2'b10;
            4'd6, 4'd7: burst_word_sel = 2'b11;
            default:    burst_word_sel = 2'b00;
        endcase
    end

    // Base address aligned to 16 bytes + word offset
    assign mem_addr = {latched_pc[31:4], burst_word_sel, 2'b00};
    assign mem_req  = (state == STATE_REFILL) && (refill_cnt >= 4'd2 && refill_cnt <= 4'd7);

    // ------------------------------------------------------------------------
    // FSM State & Storage Sequential Updates
    // ------------------------------------------------------------------------
    integer i;
    reg just_refilled;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state         <= STATE_IDLE;
            refill_cnt    <= 4'd0;
            latched_pc    <= 32'd0;
            bypass_word   <= 32'd0;
            hit_count     <= 32'd0;
            miss_count    <= 32'd0;
            just_refilled <= 1'b0;
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                valid_array[i] <= 1'b0;
                tag_array[i]   <= {TAG_WIDTH{1'b0}};
            end
        end else if (flush_act) begin
            // Branch or jump taken in EX stage cancels in-flight fetch
            state         <= STATE_IDLE;
            refill_cnt    <= 4'd0;
            just_refilled <= 1'b0;
        end else begin
            if (counter_reset_i === 1'b1) begin
                hit_count  <= 32'd0;
                miss_count <= 32'd0;
            end

            case (state)
                STATE_IDLE: begin
                    just_refilled <= 1'b0;
                    if (miss_condition) begin
                        state        <= STATE_REFILL;
                        refill_cnt   <= 4'd0;
                        latched_pc   <= cpu_addr;
                        if (counter_reset_i !== 1'b1)
                            miss_count   <= miss_count + 32'd1;
                    end else if (!just_refilled) begin
                        if (counter_reset_i !== 1'b1)
                            hit_count    <= hit_count + 32'd1;
                    end
                end

                STATE_REFILL: begin
                    refill_cnt <= refill_cnt + 4'd1;

                    // Latch burst words into cache data banks
                    if (refill_cnt == 4'd3) begin
                        if (!bypass_act) data_mem0[refill_index] <= mem_rdata;
                        if (refill_offset == 2'b00) bypass_word <= mem_rdata;
                    end else if (refill_cnt == 4'd4) begin
                        if (!bypass_act) data_mem1[refill_index] <= mem_rdata;
                        if (refill_offset == 2'b01) bypass_word <= mem_rdata;
                    end else if (refill_cnt == 4'd5) begin
                        if (!bypass_act) data_mem2[refill_index] <= mem_rdata;
                        if (refill_offset == 2'b10) bypass_word <= mem_rdata;
                    end else if (refill_cnt == 4'd6) begin
                        if (!bypass_act) data_mem3[refill_index] <= mem_rdata;
                        if (refill_offset == 2'b11) bypass_word <= mem_rdata;
                    end else if (refill_cnt == 4'd8) begin
                        if (bypass_act) begin
                            // In bypass mode, do not write tag or valid bit
                            state         <= STATE_BYPASS;
                            refill_cnt    <= 4'd0;
                        end else begin
                            // Finalize line: commit tag and set valid bit
                            tag_array[refill_index]   <= refill_tag;
                            valid_array[refill_index] <= 1'b1;
                            state                     <= STATE_IDLE;
                            refill_cnt                <= 4'd0;
                            just_refilled             <= 1'b1;
                        end
                    end
                end

                STATE_BYPASS: begin
                    // Release the CPU for exactly 1 cycle to latch instruction & advance PC
                    state         <= STATE_IDLE;
                    refill_cnt    <= 4'd0;
                    just_refilled <= 1'b0;
                end
            endcase
        end
    end

endmodule
