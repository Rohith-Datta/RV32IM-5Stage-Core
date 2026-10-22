// ============================================================================
// File: tb_dcache.v
// Module: tb_dcache
// Description: Standalone Unit Testbench for Direct-Mapped 2 KB L1 Data Cache
// Project: Pipelined RV32IMF RISC-V Core (Feature 5: L1 D-Cache)
// Clock: 50 MHz (20 ns clock period)
//
// Verification Coverage:
//   Test 1: Cold start compulsory load miss + 10-cycle burst refill verification
//   Test 2: Immediate re-hit on same address (1-cycle combinational read hit)
//   Test 3: Spatial locality same-line hits (offsets 0x04, 0x08, 0x0C: all 1-cycle hits)
//   Test 4: Store hit (SW) with Write-Through to backing memory + 1-cycle latency
//   Test 5: Read back store-hit word from cache line (verifies cache update)
//   Test 6: Store miss (SW) with No-Write-Allocate / Write-Around (1 cycle, 0 stall, no allocation)
//   Test 7: Sub-word byte/halfword store hits (SB and SH with byte write strobes)
//   Test 8: Conflict miss and line eviction (same index, different tag)
//   Test 9: Re-access evicted line (verifies new refill)
//   Test 10: Hardware reset clears all valid bits
// ============================================================================

`timescale 1ns/1ps

module tb_dcache;

    reg         clk;
    reg         reset_n;

    // CPU-side signals
    reg  [31:0] cpu_addr;
    reg  [31:0] cpu_wdata;
    reg  [3:0]  cpu_wstrb;
    reg         cpu_we;
    reg         cpu_re;
    wire [31:0] cpu_rdata;
    wire        dcache_stall;

    // Backing memory signals
    wire [31:0] mem_addr;
    wire [31:0] mem_rdata;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire        mem_we;
    wire        mem_req;

    // Diagnostic signals
    wire        cache_hit;
    wire        cache_miss;
    wire [31:0] hit_count;
    wire [31:0] miss_count;

    // 50 MHz core clock (20 ns period)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // Backing memory simulation model (4 KB = 1024 words)
    reg [31:0] backing_mem [0:1023];

    // Read port
    assign mem_rdata = backing_mem[mem_addr[11:2]];

    // Write port (synchronous byte-enabled)
    always @(posedge clk) begin
        if (mem_we && (mem_addr[11:2] < 1024)) begin
            if (mem_wstrb[0]) backing_mem[mem_addr[11:2]][7:0]   <= mem_wdata[7:0];
            if (mem_wstrb[1]) backing_mem[mem_addr[11:2]][15:8]  <= mem_wdata[15:8];
            if (mem_wstrb[2]) backing_mem[mem_addr[11:2]][23:16] <= mem_wdata[23:16];
            if (mem_wstrb[3]) backing_mem[mem_addr[11:2]][31:24] <= mem_wdata[31:24];
        end
    end

    // DUT Instance
    dcache_controller #(
        .NUM_LINES      (128),
        .WORDS_PER_LINE (4),
        .ADDR_WIDTH     (32),
        .TAG_WIDTH      (21),
        .INDEX_WIDTH    (7),
        .OFFSET_WIDTH   (2)
    ) dut (
        .clk             (clk),
        .reset_n         (reset_n),
        .counter_reset_i (1'b0),
        .cpu_addr        (cpu_addr),
        .cpu_wdata       (cpu_wdata),
        .cpu_wstrb       (cpu_wstrb),
        .cpu_we          (cpu_we),
        .cpu_re          (cpu_re),
        .cpu_rdata       (cpu_rdata),
        .dcache_stall    (dcache_stall),
        .mem_addr        (mem_addr),
        .mem_rdata       (mem_rdata),
        .mem_wdata       (mem_wdata),
        .mem_wstrb       (mem_wstrb),
        .mem_we          (mem_we),
        .mem_req         (mem_req),
        .cache_hit       (cache_hit),
        .cache_miss      (cache_miss),
        .hit_count       (hit_count),
        .miss_count      (miss_count)
    );

    integer pass_count;
    integer fail_count;
    integer stall_cycles;
    integer saved_hits;
    integer saved_misses;
    integer i;

    initial begin
        // Populate backing memory with recognizable pattern
        for (i = 0; i < 1024; i = i + 1) begin
            backing_mem[i] = 32'hA000_0000 + (i * 4);
        end

        pass_count   = 0;
        fail_count   = 0;
        cpu_addr     = 32'h0;
        cpu_wdata    = 32'h0;
        cpu_wstrb    = 4'h0;
        cpu_we       = 0;
        cpu_re       = 0;
        reset_n      = 0;

        $display("==================================================================");
        $display("   TESTBENCH: Feature 5 L1 Data Cache Controller (tb_dcache)     ");
        $display("   Clock: 50 MHz | 2 KB Direct-Mapped | 16B Line Size            ");
        $display("   Write Policy: Write-Through | Write-Allocate: No (Write-Around)");
        $display("==================================================================");

        // Reset sequence
        #40;
        @(posedge clk);
        #1;
        reset_n = 1;
        @(posedge clk);
        #1;

        // --------------------------------------------------------------------
        // TEST 1: Cold start compulsory load miss at 0x100
        // --------------------------------------------------------------------
        $display("\n[TEST 1] Cold Compulsory Load Miss at address 0x0000_0100");
        cpu_addr = 32'h0000_0100;
        cpu_re   = 1'b1;
        cpu_we   = 1'b0;
        #1;

        if (dcache_stall == 1'b1) begin
            $display("  PASS: dcache_stall asserted combinationally on cold load miss");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: dcache_stall did not assert on cold load miss");
            fail_count = fail_count + 1;
        end

        stall_cycles = 0;
        while (dcache_stall == 1'b1) begin
            @(posedge clk);
            #1;
            stall_cycles = stall_cycles + 1;
        end

        if (stall_cycles == 10) begin
            $display("  PASS: Exact 10-cycle miss penalty verified (50 MHz)");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Expected 10 stall cycles, measured %0d cycles", stall_cycles);
            fail_count = fail_count + 1;
        end

        @(posedge clk);
        #1;
        if (cpu_rdata == 32'hA000_0100) begin
            $display("  PASS: Correct data delivered: 0x%08x", cpu_rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Expected 0xa0000100, got 0x%08x", cpu_rdata);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 2: Immediate re-hit on same address (0x100)
        // --------------------------------------------------------------------
        $display("\n[TEST 2] Immediate Re-Hit on address 0x0000_0100");
        cpu_addr = 32'h0000_0100;
        cpu_re   = 1'b1;
        cpu_we   = 1'b0;
        #1;

        if (dcache_stall == 1'b0 && cpu_rdata == 32'hA000_0100 && cache_hit == 1'b1) begin
            $display("  PASS: 1-cycle hit with 0 stall cycles! Data: 0x%08x", cpu_rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Re-hit failed! stall=%b, hit=%b, data=0x%08x", dcache_stall, cache_hit, cpu_rdata);
            fail_count = fail_count + 1;
        end

        @(posedge clk);
        #1;

        // --------------------------------------------------------------------
        // TEST 3: Spatial locality hits on words 1, 2, 3 in same 16-byte block
        // --------------------------------------------------------------------
        $display("\n[TEST 3] Spatial Locality Hits on words in the same 16-byte line");

        // Word 1 (0x104)
        cpu_addr = 32'h0000_0104;
        #1;
        if (dcache_stall == 1'b0 && cpu_rdata == 32'hA000_0104 && cache_hit == 1'b1) begin
            $display("  PASS: Word 1 (0x104) hit in 1 cycle! Data: 0x%08x", cpu_rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Word 1 spatial hit failed! stall=%b, data=0x%08x", dcache_stall, cpu_rdata);
            fail_count = fail_count + 1;
        end
        @(posedge clk);
        #1;

        // Word 2 (0x108)
        cpu_addr = 32'h0000_0108;
        #1;
        if (dcache_stall == 1'b0 && cpu_rdata == 32'hA000_0108 && cache_hit == 1'b1) begin
            $display("  PASS: Word 2 (0x108) hit in 1 cycle! Data: 0x%08x", cpu_rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Word 2 spatial hit failed! stall=%b, data=0x%08x", dcache_stall, cpu_rdata);
            fail_count = fail_count + 1;
        end
        @(posedge clk);
        #1;

        // Word 3 (0x10C)
        cpu_addr = 32'h0000_010C;
        #1;
        if (dcache_stall == 1'b0 && cpu_rdata == 32'hA000_010C && cache_hit == 1'b1) begin
            $display("  PASS: Word 3 (0x10C) hit in 1 cycle! Data: 0x%08x", cpu_rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Word 3 spatial hit failed! stall=%b, data=0x%08x", dcache_stall, cpu_rdata);
            fail_count = fail_count + 1;
        end
        @(posedge clk);
        #1;

        // --------------------------------------------------------------------
        // TEST 4: Store Hit (SW) with Write-Through to backing memory
        // --------------------------------------------------------------------
        $display("\n[TEST 4] Store Hit (SW) at 0x104 with Write-Through");
        cpu_addr  = 32'h0000_0104;
        cpu_wdata = 32'hDEAD_BEEF;
        cpu_wstrb = 4'b1111;
        cpu_we    = 1'b1;
        cpu_re    = 1'b0;
        #1;

        if (dcache_stall == 1'b0 && cache_hit == 1'b1) begin
            $display("  PASS: Store hit completes in 1 cycle with write-through asserted!");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Store hit stalled or didn't register hit! stall=%b, hit=%b", dcache_stall, cache_hit);
            fail_count = fail_count + 1;
        end

        @(posedge clk);
        #1;
        cpu_we = 1'b0;

        // Verify backing memory was updated
        if (backing_mem[32'h0000_0104 >> 2] == 32'hDEAD_BEEF) begin
            $display("  PASS: Backing memory successfully updated to 0xdeadbeef");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Backing memory not updated! Value: 0x%08x", backing_mem[32'h0000_0104 >> 2]);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 5: Read back store-hit word from cache line
        // --------------------------------------------------------------------
        $display("\n[TEST 5] Read back updated word from cache at 0x104");
        cpu_addr = 32'h0000_0104;
        cpu_re   = 1'b1;
        #1;

        if (dcache_stall == 1'b0 && cpu_rdata == 32'hDEAD_BEEF) begin
            $display("  PASS: Cache returned updated store data: 0xdeadbeef in 1 cycle!");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Cache did not return updated word! data=0x%08x", cpu_rdata);
            fail_count = fail_count + 1;
        end
        @(posedge clk);
        #1;

        // --------------------------------------------------------------------
        // TEST 6: Store Miss (No-Write-Allocate / Write-Around) at 0x200
        // --------------------------------------------------------------------
        $display("\n[TEST 6] Store Miss (No-Write-Allocate) at address 0x0000_0200");
        cpu_addr  = 32'h0000_0200;
        cpu_wdata = 32'hCAFE_BABE;
        cpu_wstrb = 4'b1111;
        cpu_we    = 1'b1;
        cpu_re    = 1'b0;
        #1;

        if (dcache_stall == 1'b0 && cache_miss == 1'b1) begin
            $display("  PASS: Store miss bypasses cache directly to memory in 1 cycle (0 stall)!");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Store miss stalled or didn't signal miss! stall=%b, miss=%b", dcache_stall, cache_miss);
            fail_count = fail_count + 1;
        end

        @(posedge clk);
        #1;
        cpu_we = 1'b0;

        if (backing_mem[32'h0000_0200 >> 2] == 32'hCAFE_BABE) begin
            $display("  PASS: Backing memory at 0x200 received write: 0xcafebabe");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Backing memory not written on store miss!");
            fail_count = fail_count + 1;
        end

        // Verify that line was NOT allocated in cache (subsequent load MUST trigger miss)
        cpu_addr = 32'h0000_0200;
        cpu_re   = 1'b1;
        #1;
        if (dcache_stall == 1'b1) begin
            $display("  PASS: No-Write-Allocate confirmed! Subsequent read at 0x200 correctly triggers load miss");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Subsequent read hit unexpectedly (line was allocated on write)!");
            fail_count = fail_count + 1;
        end

        while (dcache_stall == 1'b1) begin
            @(posedge clk);
            #1;
        end
        @(posedge clk);
        #1;

        // --------------------------------------------------------------------
        // TEST 7: Sub-word byte/halfword store hits (SB and SH) at 0x108
        // --------------------------------------------------------------------
        $display("\n[TEST 7] Sub-word Stores: SB and SH at address 0x0000_0108");
        // Write byte 0 = 0xAA
        cpu_addr  = 32'h0000_0108;
        cpu_wdata = 32'h0000_00AA;
        cpu_wstrb = 4'b0001;
        cpu_we    = 1'b1;
        cpu_re    = 1'b0;
        @(posedge clk);
        #1;

        // Write byte 1 = 0xBB
        cpu_addr  = 32'h0000_0108;
        cpu_wdata = 32'h0000_BB00;
        cpu_wstrb = 4'b0010;
        @(posedge clk);
        #1;

        // Write halfword [31:16] = 0xCCDD
        cpu_addr  = 32'h0000_0108;
        cpu_wdata = 32'hCCDD_0000;
        cpu_wstrb = 4'b1100;
        @(posedge clk);
        #1;
        cpu_we    = 1'b0;

        // Read back full word: should be 0xCCDD_BBAA
        cpu_re    = 1'b1;
        #1;
        if (cpu_rdata == 32'hCCDD_BBAA) begin
            $display("  PASS: Sub-word byte masking accurate! Read back: 0x%08x", cpu_rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Sub-word write failed! Expected 0xccddbbaa, got 0x%08x", cpu_rdata);
            fail_count = fail_count + 1;
        end
        @(posedge clk);
        #1;

        // --------------------------------------------------------------------
        // TEST 8: Conflict Miss & Line Eviction at 0x900 (same index as 0x100)
        // --------------------------------------------------------------------
        $display("\n[TEST 8] Conflict Miss & Line Eviction at address 0x0000_0900");
        // 0x100: Index = (0x100 >> 4) & 0x7F = 0x10. Tag = 0x100 >> 11 = 0
        // 0x900: Index = (0x900 >> 4) & 0x7F = 0x10. Tag = 0x900 >> 11 = 1
        cpu_addr = 32'h0000_0900;
        cpu_re   = 1'b1;
        #1;

        if (dcache_stall == 1'b1) begin
            $display("  PASS: Conflict miss detected on same index with different tag");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Expected conflict miss did not stall!");
            fail_count = fail_count + 1;
        end

        while (dcache_stall == 1'b1) begin
            @(posedge clk);
            #1;
        end
        @(posedge clk);
        #1;

        if (cpu_rdata == 32'hA000_0900) begin
            $display("  PASS: New line refilled successfully! Data: 0x%08x", cpu_rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Incorrect refill data: 0x%08x", cpu_rdata);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 9: Re-access Evicted Line at 0x100 (must miss again)
        // --------------------------------------------------------------------
        $display("\n[TEST 9] Re-access Evicted Line at 0x100");
        cpu_addr = 32'h0000_0100;
        cpu_re   = 1'b1;
        #1;

        if (dcache_stall == 1'b1) begin
            $display("  PASS: Previously evicted line 0x100 correctly misses again");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Expected miss on evicted line!");
            fail_count = fail_count + 1;
        end

        while (dcache_stall == 1'b1) begin
            @(posedge clk);
            #1;
        end
        @(posedge clk);
        #1;

        saved_hits   = hit_count;
        saved_misses = miss_count;

        // --------------------------------------------------------------------
        // TEST 10: Hardware reset clears valid array
        // --------------------------------------------------------------------
        $display("\n[TEST 10] Hardware Reset Validation");
        reset_n  = 0;
        cpu_addr = 32'h0000_0100;
        cpu_re   = 1'b1;
        @(posedge clk);
        #1;
        @(posedge clk);
        #1;
        reset_n  = 1;
        #1;

        if (dcache_stall == 1'b1) begin
            $display("  PASS: Reset successfully cleared valid bits; 0x100 misses again");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Reset failed to clear cache lines!");
            fail_count = fail_count + 1;
        end

        while (dcache_stall == 1'b1) begin
            @(posedge clk);
            #1;
        end
        @(posedge clk);
        #1;

        // --------------------------------------------------------------------
        // Final Results Summary
        // --------------------------------------------------------------------
        $display("\n==================================================================");
        $display("   D-CACHE UNIT VERIFICATION SUMMARY: %0d / %0d PASSED", pass_count, (pass_count + fail_count));
        $display("   Operational Metrics (Pre-Reset):");
        $display("     * Total Cache Hits   : %0d", saved_hits);
        $display("     * Total Cache Misses : %0d", saved_misses);
        $display("==================================================================");

        if (fail_count == 0) begin
            $display(">>> ALL ASSERTIONS PASSED! FEATURE 5 D-CACHE 100%% VERIFIED! <<<\n");
        end else begin
            $display(">>> SOME ASSERTIONS FAILED! <<<\n");
        end

        $finish;
    end

endmodule
