// ============================================================================
// File: dcache_controller.v
// Module: dcache_controller
// Description: Direct-Mapped 2 KB L1 Data Cache with 10-Cycle Read Miss FSM,
//              Write-Through with Write Buffer, and No-Write-Allocate (Write-Around).
// Project: Pipelined RV32IMF RISC-V Core (Feature 5: L1 D-Cache)
//
// Architecture Specifications:
//   - Organization:       Direct-Mapped
//   - Capacity:           2 KB (128 lines x 4 words/line x 4 bytes/word)
//   - Line Size:          16 bytes (4 words / 128 bits)
//   - Tag Width:          21 bits [31:11]
//   - Index Width:        7 bits  [10:4]
//   - Word Offset:        2 bits  [3:2]
//   - Byte Offset:        2 bits  [1:0]
//   - Read Hit Latency:   1 cycle (combinational SRAM read, zero penalty)
//   - Write Hit Latency:  1 cycle (cache line update + write-through)
//   - Read Miss Penalty:  10 cycles (burst refill FSM: 4 words)
//   - Write Miss Policy:  No-Write-Allocate / Write-Around (1 cycle, 0 stall)
//   - Write Policy:       Write-Through with Write Buffer
//   - Sub-word Support:   Byte write enables for SB (1B), SH (2B), SW (4B)
//
// Address Decomposition:
//   31                            11 10            4 3           2 1           0
//   +-------------------------------+---------------+-------------+-------------+
//   |          TAG (21 bits)        | INDEX (7 bits)|  WO (2 bits)| BO (2 bits) |
//   +-------------------------------+---------------+-------------+-------------+
// ============================================================================

`timescale 1ns/1ps

module dcache_controller #(
    parameter NUM_LINES      = 128,   // 128 cache lines
    parameter WORDS_PER_LINE = 4,     // 4 words (16 bytes) per line
    parameter ADDR_WIDTH     = 32,
    parameter TAG_WIDTH      = 21,    // [31:11]
    parameter INDEX_WIDTH    = 7,     // [10:4]
    parameter OFFSET_WIDTH   = 2      // [3:2] word offset
)(
    input  wire        clk,
    input  wire        reset_n,
    input  wire        counter_reset_i,

    // CPU Pipeline Interface (from EX/MEM stage & memory_stage)
    input  wire [31:0] cpu_addr,        // Target memory address from EX/MEM
    input  wire [31:0] cpu_wdata,       // Store data (formatted by memory_stage)
    input  wire [3:0]  cpu_wstrb,       // Byte write strobes (SB, SH, SW)
    input  wire        cpu_we,          // Store enable (MemWrite)
    input  wire        cpu_re,          // Load enable (MemRead)
    output wire [31:0] cpu_rdata,       // Raw 32-bit word to Load Extender in MEM
    output wire        dcache_stall,    // Freeze pipeline on load miss

    // Backing Data Memory Interface (to data_mem model / main memory)
    output wire [31:0] mem_addr,        // Refill or Write-Through address
    input  wire [31:0] mem_rdata,       // Burst read data from backing memory
    output wire [31:0] mem_wdata,       // Write-through data to backing memory
    output wire [3:0]  mem_wstrb,       // Write-through byte strobes
    output wire        mem_we,          // Write-through enable to backing memory
    output wire        mem_req,         // Refill read strobe to backing memory

    // Diagnostic & Performance Monitoring Counters
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

    // Data array: 128 lines x 4 words = 512 words (4 BRAM banks with byte enables)
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

    wire hit_condition  = line_valid && (line_tag == curr_tag);
    wire load_miss      = cpu_re && !hit_condition;
    wire store_miss     = cpu_we && !hit_condition;

    // ------------------------------------------------------------------------
    // FSM States & Registers
    // ------------------------------------------------------------------------
    localparam STATE_IDLE   = 1'b0;
    localparam STATE_REFILL = 1'b1;

    reg        state;
    reg [3:0]  refill_cnt;
    reg [31:0] latched_addr;

    wire [INDEX_WIDTH-1:0] refill_index = latched_addr[10:4];
    wire [TAG_WIDTH-1:0]   refill_tag   = latched_addr[31:11];

    // Combinational hit/miss status
    assign cache_hit  = (state == STATE_IDLE) && ((cpu_re && hit_condition) || (cpu_we && hit_condition)) && reset_n;
    assign cache_miss = (state == STATE_REFILL) || ((state == STATE_IDLE) && (load_miss || store_miss) && reset_n);

    // Pipeline stall: ONLY asserts on Load Miss!
    // Store misses use No-Write-Allocate / Write-Around with 0 stall cycles.
    assign dcache_stall = (state == STATE_REFILL) || ((state == STATE_IDLE) && load_miss && reset_n);

    // ------------------------------------------------------------------------
    // Combinational Word Selection (Read Port)
    // ------------------------------------------------------------------------
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
            default: selected_word = 32'h0;
        endcase
    end

    // Raw read data to MEM stage load extender
    assign cpu_rdata = (hit_condition && cpu_re) ? selected_word : 32'h0;

    // ------------------------------------------------------------------------
    // Backing Memory Bus & Write Buffer Multiplexing
    // ------------------------------------------------------------------------
    // Burst word address during line refill
    reg [1:0] burst_word_sel;
    always @(*) begin
        case (refill_cnt)
            4'd2, 4'd3: burst_word_sel = 2'b00; // Word 0
            4'd4:       burst_word_sel = 2'b01; // Word 1
            4'd5:       burst_word_sel = 2'b10; // Word 2
            4'd6, 4'd7: burst_word_sel = 2'b11; // Word 3
            default:    burst_word_sel = 2'b00;
        endcase
    end

    wire [31:0] refill_mem_addr = {latched_addr[31:4], burst_word_sel, 2'b00};

    // Multiplex memory bus between Refill (read) and Write-Through (write)
    assign mem_addr  = (state == STATE_REFILL) ? refill_mem_addr : cpu_addr;
    assign mem_req   = (state == STATE_REFILL) && (refill_cnt >= 4'd2 && refill_cnt <= 4'd7);

    // Write-Through with Write Buffer:
    // When CPU issues a store (hit or miss), forward directly to backing memory
    assign mem_we    = (state == STATE_IDLE) && cpu_we;
    assign mem_wdata = cpu_wdata;
    assign mem_wstrb = cpu_wstrb;

    // ------------------------------------------------------------------------
    // Store Hit Byte-Level Cache Line Update Logic
    // ------------------------------------------------------------------------
    wire store_hit = (state == STATE_IDLE) && cpu_we && hit_condition;

    // Bank 0 (Word 0)
    always @(posedge clk) begin
        if (store_hit && (curr_offset == 2'b00)) begin
            if (cpu_wstrb[0]) data_mem0[curr_index][7:0]   <= cpu_wdata[7:0];
            if (cpu_wstrb[1]) data_mem0[curr_index][15:8]  <= cpu_wdata[15:8];
            if (cpu_wstrb[2]) data_mem0[curr_index][23:16] <= cpu_wdata[23:16];
            if (cpu_wstrb[3]) data_mem0[curr_index][31:24] <= cpu_wdata[31:24];
        end else if ((state == STATE_REFILL) && (refill_cnt == 4'd3)) begin
            data_mem0[refill_index] <= mem_rdata;
        end
    end

    // Bank 1 (Word 1)
    always @(posedge clk) begin
        if (store_hit && (curr_offset == 2'b01)) begin
            if (cpu_wstrb[0]) data_mem1[curr_index][7:0]   <= cpu_wdata[7:0];
            if (cpu_wstrb[1]) data_mem1[curr_index][15:8]  <= cpu_wdata[15:8];
            if (cpu_wstrb[2]) data_mem1[curr_index][23:16] <= cpu_wdata[23:16];
            if (cpu_wstrb[3]) data_mem1[curr_index][31:24] <= cpu_wdata[31:24];
        end else if ((state == STATE_REFILL) && (refill_cnt == 4'd4)) begin
            data_mem1[refill_index] <= mem_rdata;
        end
    end

    // Bank 2 (Word 2)
    always @(posedge clk) begin
        if (store_hit && (curr_offset == 2'b10)) begin
            if (cpu_wstrb[0]) data_mem2[curr_index][7:0]   <= cpu_wdata[7:0];
            if (cpu_wstrb[1]) data_mem2[curr_index][15:8]  <= cpu_wdata[15:8];
            if (cpu_wstrb[2]) data_mem2[curr_index][23:16] <= cpu_wdata[23:16];
            if (cpu_wstrb[3]) data_mem2[curr_index][31:24] <= cpu_wdata[31:24];
        end else if ((state == STATE_REFILL) && (refill_cnt == 4'd5)) begin
            data_mem2[refill_index] <= mem_rdata;
        end
    end

    // Bank 3 (Word 3)
    always @(posedge clk) begin
        if (store_hit && (curr_offset == 2'b11)) begin
            if (cpu_wstrb[0]) data_mem3[curr_index][7:0]   <= cpu_wdata[7:0];
            if (cpu_wstrb[1]) data_mem3[curr_index][15:8]  <= cpu_wdata[15:8];
            if (cpu_wstrb[2]) data_mem3[curr_index][23:16] <= cpu_wdata[23:16];
            if (cpu_wstrb[3]) data_mem3[curr_index][31:24] <= cpu_wdata[31:24];
        end else if ((state == STATE_REFILL) && (refill_cnt == 4'd6)) begin
            data_mem3[refill_index] <= mem_rdata;
        end
    end

    // ------------------------------------------------------------------------
    // FSM State Updates & Diagnostic Counters
    // ------------------------------------------------------------------------
    integer i;
    reg just_refilled;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state         <= STATE_IDLE;
            refill_cnt    <= 4'd0;
            latched_addr  <= 32'd0;
            hit_count     <= 32'd0;
            miss_count    <= 32'd0;
            just_refilled <= 1'b0;
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                valid_array[i] <= 1'b0;
                tag_array[i]   <= {TAG_WIDTH{1'b0}};
            end
        end else begin
            if (counter_reset_i === 1'b1) begin
                hit_count  <= 32'd0;
                miss_count <= 32'd0;
            end

            case (state)
                STATE_IDLE: begin
                    just_refilled <= 1'b0;
                    if (load_miss) begin
                        // Load miss triggers 10-cycle burst refill
                        state        <= STATE_REFILL;
                        refill_cnt   <= 4'd0;
                        latched_addr <= cpu_addr;
                        if (counter_reset_i !== 1'b1)
                            miss_count   <= miss_count + 32'd1;
                    end else if (store_miss) begin
                        // Store miss with No-Write-Allocate: bypass cache, no stall
                        if (counter_reset_i !== 1'b1)
                            miss_count   <= miss_count + 32'd1;
                    end else if ((cpu_re || cpu_we) && hit_condition && !just_refilled) begin
                        if (counter_reset_i !== 1'b1)
                            hit_count    <= hit_count + 32'd1;
                    end
                end

                STATE_REFILL: begin
                    refill_cnt <= refill_cnt + 4'd1;

                    if (refill_cnt == 4'd8) begin
                        // Finalize line: commit tag and set valid bit
                        tag_array[refill_index]   <= refill_tag;
                        valid_array[refill_index] <= 1'b1;
                        state                     <= STATE_IDLE;
                        refill_cnt                <= 4'd0;
                        just_refilled             <= 1'b1;
                    end
                end
            endcase
        end
    end

endmodule
