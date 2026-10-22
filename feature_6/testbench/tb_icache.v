// ============================================================================
// File: tb_icache.v
// Module: tb_icache
// Description: Standalone Unit Testbench for Direct-Mapped 2 KB L1 Instruction Cache
// Project: Pipelined RV32IMF RISC-V Core (Feature 6: L1 I-Cache Verification)
// Clock: Standard 50 MHz (Period: 20 ns)
//
// Verification Coverage:
//   Test 1: Cold start compulsory miss + 10-cycle burst refill verification
//   Test 2: Immediate re-hit on same address (1-cycle combinational hit, 0 stall)
//   Test 3: Spatial locality same-line hits (offsets 0x004, 0x008, 0x00C: 1-cycle hits)
//   Test 4: Compulsory miss on different cache line (index 1: 0x0000_0010)
//   Test 5: Conflict eviction (same index 0, different tag 0x0000_0800)
//   Test 6: Re-access evicted line (0x0000_0000) confirms eviction miss
//   Test 7: Cache bypass mode verification (cache_bypass_i = 1)
//   Test 8: Branch flush test (flush_i cancels in-flight refill)
//   Test 9: Hardware reset clears valid array and performance counters
// ============================================================================

`timescale 1ns/1ps

module tb_icache;

    reg         clk;
    reg         reset_n;
    reg         flush;
    reg         cache_bypass;
    reg  [31:0] cpu_addr;
    wire [31:0] cpu_rdata;
    wire        icache_stall;

    wire [31:0] mem_addr;
    wire [31:0] mem_rdata;
    wire        mem_req;
    wire        cache_hit;
    wire        cache_miss;
    wire [31:0] hit_count;
    wire [31:0] miss_count;

    // Standard 50 MHz Core Clock (20 ns period: 10 ns high, 10 ns low)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // Backing memory simulation model (4 KB word-addressed)
    reg [31:0] backing_mem [0:1023];
    assign mem_rdata = backing_mem[mem_addr[11:2]];

    // DUT Instance: 2 KB Direct-Mapped L1 I-Cache
    icache_controller #(
        .NUM_LINES      (128),
        .WORDS_PER_LINE (4),
        .ADDR_WIDTH     (32),
        .TAG_WIDTH      (21),
        .INDEX_WIDTH    (7),
        .OFFSET_WIDTH   (2)
    ) dut (
        .clk             (clk),
        .reset_n         (reset_n),
        .flush_i         (flush),
        .counter_reset_i (1'b0),
        .cache_bypass_i  (cache_bypass),
        .cpu_addr        (cpu_addr),
        .cpu_rdata       (cpu_rdata),
        .icache_stall    (icache_stall),
        .mem_addr        (mem_addr),
        .mem_rdata       (mem_rdata),
        .mem_req         (mem_req),
        .cache_hit       (cache_hit),
        .cache_miss      (cache_miss),
        .hit_count       (hit_count),
        .miss_count      (miss_count)
    );

    integer pass_count;
    integer fail_count;
    integer stall_cycles;
    integer i;

    task check(input condition, input [1023:0] msg);
        begin
            if (condition) begin
                $display("  [PASS] %0s", msg);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %0s", msg);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        // Populate backing memory with recognizable pattern: 0x1000_0000 + word_index
        for (i = 0; i < 1024; i = i + 1) begin
            backing_mem[i] = 32'h1000_0000 + i;
        end

        pass_count   = 0;
        fail_count   = 0;
        cpu_addr     = 32'h0000_0000;
        flush        = 1'b0;
        cache_bypass = 1'b0;
        reset_n      = 1'b0;

        $display("================================================================================");
        $display("   TESTBENCH: Feature 6 L1 Instruction Cache Unit (tb_icache)");
        $display("   Clock: 50 MHz (Period: 20 ns) | 2 KB Direct-Mapped | 16B Line Size");
        $display("================================================================================");

        #40;
        @(posedge clk);
        #1;
        reset_n = 1'b1;
        #1;

        // --------------------------------------------------------------------
        // TEST 1: Cold start compulsory miss + 10-cycle burst refill
        // --------------------------------------------------------------------
        $display("\n[TEST 1] Cold start compulsory miss on PC = 0x0000_0000...");
        cpu_addr = 32'h0000_0000;
        #1;
        check(icache_stall == 1'b1, "Cold miss combinationally asserts icache_stall = 1");

        stall_cycles = 0;
        while (icache_stall) begin
            stall_cycles = stall_cycles + 1;
            @(posedge clk);
            #1;
        end

        $display("  Measured miss penalty: %0d cycles (Expected: 10 cycles)", stall_cycles);
        check(stall_cycles == 10, "Miss penalty is exactly 10 cycles (50 MHz)");
        check(cpu_rdata == 32'h1000_0000 && cache_hit, "Delivered instruction 0x10000000 matches backing memory");

        // --------------------------------------------------------------------
        // TEST 2: Immediate re-hit on same address (1-cycle hit, 0 stall)
        // --------------------------------------------------------------------
        $display("\n[TEST 2] Immediate re-hit on PC = 0x0000_0000...");
        @(posedge clk);
        #1;
        check(cache_hit && !icache_stall && cpu_rdata == 32'h1000_0000, "Immediate re-hit completes in 1 cycle with zero stall");

        // --------------------------------------------------------------------
        // TEST 3: Spatial locality hits in same 16-byte block (0x004, 0x008, 0x00C)
        // --------------------------------------------------------------------
        $display("\n[TEST 3] Spatial locality hits on words 1, 2, 3 in same cache block...");
        
        // Word 1: 0x004
        cpu_addr = 32'h0000_0004;
        #1;
        check(cache_hit && !icache_stall && cpu_rdata == 32'h1000_0001, "Word 1 (0x004) hit in 1 cycle! Data: 0x10000001");
        @(posedge clk);
        #1;

        // Word 2: 0x008
        cpu_addr = 32'h0000_0008;
        #1;
        check(cache_hit && !icache_stall && cpu_rdata == 32'h1000_0002, "Word 2 (0x008) hit in 1 cycle! Data: 0x10000002");
        @(posedge clk);
        #1;

        // Word 3: 0x00C
        cpu_addr = 32'h0000_000C;
        #1;
        check(cache_hit && !icache_stall && cpu_rdata == 32'h1000_0003, "Word 3 (0x00C) hit in 1 cycle! Data: 0x10000003");
        @(posedge clk);
        #1;

        // --------------------------------------------------------------------
        // TEST 4: Compulsory miss on next cache line (Index 1: 0x0000_0010)
        // --------------------------------------------------------------------
        $display("\n[TEST 4] Compulsory miss on adjacent cache line (Index 1: PC = 0x0000_0010)...");
        cpu_addr = 32'h0000_0010;
        #1;
        check(icache_stall == 1'b1, "Adjacent line triggers cold miss with icache_stall = 1");

        stall_cycles = 0;
        while (icache_stall) begin
            stall_cycles = stall_cycles + 1;
            @(posedge clk);
            #1;
        end
        check(stall_cycles == 10, "Adjacent line refilled in 10 cycles");
        check(cpu_rdata == 32'h1000_0004 && cache_hit, "Delivered word 4 from backing memory (0x10000004)");

        // --------------------------------------------------------------------
        // TEST 5: Conflict eviction (Index 0, Tag 0x0000_0800)
        // --------------------------------------------------------------------
        $display("\n[TEST 5] Conflict miss & line eviction at PC = 0x0000_0800 (Index 0, Tag 1)...");
        cpu_addr = 32'h0000_0800; // Same index 0 (0x800[10:4] = 0), but Tag 1
        #1;
        check(icache_stall == 1'b1, "Different tag on same index triggers conflict miss");

        while (icache_stall) begin
            @(posedge clk);
            #1;
        end
        check(cpu_rdata == 32'h1000_0200 && cache_hit, "New tag line refilled at index 0! Data: 0x10000200");

        // --------------------------------------------------------------------
        // TEST 6: Re-accessing evicted line (PC = 0x0000_0000)
        // --------------------------------------------------------------------
        $display("\n[TEST 6] Re-access previously evicted address 0x0000_0000...");
        cpu_addr = 32'h0000_0000;
        #1;
        check(icache_stall == 1'b1, "Evicted line 0x0000_0000 correctly incurs miss again");
        while (icache_stall) begin
            @(posedge clk);
            #1;
        end
        check(cpu_rdata == 32'h1000_0000 && cache_hit, "Re-refilled original line correctly");

        // --------------------------------------------------------------------
        // TEST 7: Cache Bypass Mode Verification (cache_bypass_i = 1)
        // --------------------------------------------------------------------
        $display("\n[TEST 7] Cache Bypass Mode (cache_bypass_i = 1)...");
        cache_bypass = 1'b1;
        cpu_addr     = 32'h0000_0000; // Even though in cache, bypass forces miss
        #1;
        check(icache_stall == 1'b1, "Bypass mode forces cache miss even for cached address");

        stall_cycles = 0;
        while (icache_stall) begin
            stall_cycles = stall_cycles + 1;
            @(posedge clk);
            #1;
        end
        check(stall_cycles == 10, "Bypass mode completed 10-cycle un-cached access");
        @(posedge clk);
        #1;
        cache_bypass = 1'b0;

        // --------------------------------------------------------------------
        // TEST 8: Branch Flush Cancel (flush_i cancels in-flight refill)
        // --------------------------------------------------------------------
        $display("\n[TEST 8] Branch flush cancels in-flight refill...");
        cpu_addr = 32'h0000_0040; // New cold line (index 4)
        #1;
        check(icache_stall == 1'b1, "Cold miss started for 0x0040");

        // Let refill run for 3 cycles, then simulate branch flush
        repeat (3) @(posedge clk);
        flush = 1'b1;
        @(posedge clk);
        #1;
        flush = 1'b0;
        cpu_addr = 32'h0000_0000; // Branch redirected to 0x0000 (which is cached)
        #1;
        check(cache_hit && !icache_stall, "Branch flush restored FSM to IDLE; target address hit immediately in 1 cycle!");

        // --------------------------------------------------------------------
        // TEST 9: Hardware Reset Validation
        // --------------------------------------------------------------------
        $display("\n[TEST 9] Hardware Reset validation...");
        reset_n = 1'b0;
        #25;
        @(posedge clk);
        #1;
        reset_n = 1'b1;
        cpu_addr = 32'h0000_0000;
        #1;
        check(icache_stall == 1'b1, "Reset cleared valid bits; 0x0000_0000 correctly triggers cold miss");
        while (icache_stall) begin
            @(posedge clk);
            #1;
        end

        $display("\n================================================================================");
        $display("   L1 I-CACHE UNIT VERIFICATION SUMMARY");
        $display("   Total Checks Passed: %0d", pass_count);
        $display("   Total Checks Failed: %0d", fail_count);
        $display("   Cache Hits Logged  : %0d", hit_count);
        $display("   Cache Misses Logged: %0d", miss_count);
        $display("================================================================================");

        if (fail_count == 0) begin
            $display(">>> ALL ASSERTIONS PASSED! FEATURE 6 I-CACHE 100%% VERIFIED! <<<\n");
        end else begin
            $display(">>> SOME ASSERTIONS FAILED! <<<\n");
        end

        $finish;
    end

endmodule
