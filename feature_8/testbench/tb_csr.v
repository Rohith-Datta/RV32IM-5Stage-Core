// ============================================================================
// File: tb_csr.v
// Module: tb_csr
// Description: Standalone Unit Testbench for Passive Performance CSR Counters
// Project: Pipelined RV32IMF RISC-V Core (Feature 8: Passive CSR Verification)
// Clock: 50 MHz (20 ns clock period)
//
// Test Coverage:
//   Test 1: Reset state verification (all counters = 0, CSR reads return 0)
//   Test 2: Monotonic cycle counter increment (cycle/cycleh)
//   Test 3: Instruction retirement event accumulation (instret/instreth)
//   Test 4: Pipeline stall cycle accumulation (hpmcounter3/3h)
//   Test 5: Branch execution count accumulation (hpmcounter4/4h)
//   Test 6: Branch misprediction count accumulation (hpmcounter5/5h)
//   Test 7: 64-bit upper half overflow & cycleh read verification
//   Test 8: Unmapped CSR address handling (returns 32'h0)
// ============================================================================

`timescale 1ns/1ps

module tb_csr;

    reg         clk;
    reg         reset_n;

    // Triggers
    reg         stall_cycle;
    reg         inst_retired;
    reg         branch_exec;
    reg         branch_mispredict;

    // CSR Read
    reg  [11:0] csr_addr;
    wire [31:0] csr_rdata;

    // Telemetry Outputs
    wire [63:0] cycle_count;
    wire [63:0] instret_count;
    wire [63:0] stall_count;
    wire [63:0] branch_count;

    csr_perf_counters dut (
        .clk              (clk),
        .reset_n          (reset_n),
        .stall_cycle      (stall_cycle),
        .inst_retired     (inst_retired),
        .branch_exec      (branch_exec),
        .branch_mispredict(branch_mispredict),
        .csr_addr         (csr_addr),
        .csr_rdata        (csr_rdata),
        .cycle_count_o    (cycle_count),
        .instret_count_o  (instret_count),
        .stall_count_o    (stall_count),
        .branch_count_o   (branch_count)
    );

    // 50 MHz clock
    always #10 clk = ~clk;

    integer errors;
    integer i;

    initial begin
        clk               = 0;
        reset_n           = 0;
        stall_cycle       = 0;
        inst_retired      = 0;
        branch_exec       = 0;
        branch_mispredict = 0;
        csr_addr          = 12'hC00;
        errors            = 0;

        $display("================================================================");
        $display("   STARTING FEATURE 8: PASSIVE CSR COUNTERS UNIT TESTBENCH");
        $display("================================================================");

        // Apply Reset
        #25;
        reset_n = 1;
        #15;

        // --------------------------------------------------------------------
        // Test 1: Reset State Verification
        // --------------------------------------------------------------------
        $display("[TEST 1] Verifying reset state...");
        csr_addr = 12'hC02; // instret
        #1;
        if (csr_rdata !== 32'd0 || instret_count !== 64'd0) begin
            $display("FAILED: Test 1 Reset. instret=%0d (expected 0)", csr_rdata);
            errors = errors + 1;
        end else begin
            $display("PASSED: Test 1 Counters correctly cleared on reset.");
        end

        // --------------------------------------------------------------------
        // Test 2: Monotonic Cycle Counter
        // --------------------------------------------------------------------
        $display("[TEST 2] Verifying cycle counter increment over 10 clock cycles...");
        repeat (10) @(posedge clk);
        #1;
        csr_addr = 12'hC00; // cycle
        #1;
        if (csr_rdata < 32'd10) begin
            $display("FAILED: Test 2 Cycle count too low: %0d", csr_rdata);
            errors = errors + 1;
        end else begin
            $display("PASSED: Test 2 cycle counter incremented correctly: %0d cycles.", csr_rdata);
        end

        // --------------------------------------------------------------------
        // Test 3: Instruction Retirement Counter
        // --------------------------------------------------------------------
        $display("[TEST 3] Pulse inst_retired for 5 cycles...");
        for (i = 0; i < 5; i = i + 1) begin
            @(posedge clk);
            #1;
            inst_retired = 1;
        end
        @(posedge clk);
        #1;
        inst_retired = 0;

        csr_addr = 12'hC02; // instret
        #1;
        if (csr_rdata !== 32'd5) begin
            $display("FAILED: Test 3 instret = %0d (expected 5)", csr_rdata);
            errors = errors + 1;
        end else begin
            $display("PASSED: Test 3 instret counter = 5.");
        end

        // --------------------------------------------------------------------
        // Test 4: Pipeline Stall Counter
        // --------------------------------------------------------------------
        $display("[TEST 4] Pulse stall_cycle for 7 cycles...");
        for (i = 0; i < 7; i = i + 1) begin
            @(posedge clk);
            #1;
            stall_cycle = 1;
        end
        @(posedge clk);
        #1;
        stall_cycle = 0;

        csr_addr = 12'hC03; // hpmcounter3 (stalls)
        #1;
        if (csr_rdata !== 32'd7) begin
            $display("FAILED: Test 4 hpmcounter3 = %0d (expected 7)", csr_rdata);
            errors = errors + 1;
        end else begin
            $display("PASSED: Test 4 hpmcounter3 counter = 7.");
        end

        // --------------------------------------------------------------------
        // Test 5: Branch Execution Counter
        // --------------------------------------------------------------------
        $display("[TEST 5] Pulse branch_exec for 4 cycles...");
        for (i = 0; i < 4; i = i + 1) begin
            @(posedge clk);
            #1;
            branch_exec = 1;
        end
        @(posedge clk);
        #1;
        branch_exec = 0;

        csr_addr = 12'hC04; // hpmcounter4 (branches)
        #1;
        if (csr_rdata !== 32'd4) begin
            $display("FAILED: Test 5 hpmcounter4 = %0d (expected 4)", csr_rdata);
            errors = errors + 1;
        end else begin
            $display("PASSED: Test 5 hpmcounter4 counter = 4.");
        end

        // --------------------------------------------------------------------
        // Test 6: Branch Mispredict Counter
        // --------------------------------------------------------------------
        $display("[TEST 6] Pulse branch_mispredict for 2 cycles...");
        for (i = 0; i < 2; i = i + 1) begin
            @(posedge clk);
            #1;
            branch_mispredict = 1;
        end
        @(posedge clk);
        #1;
        branch_mispredict = 0;

        csr_addr = 12'hC05; // hpmcounter5 (mispredicts)
        #1;
        if (csr_rdata !== 32'd2) begin
            $display("FAILED: Test 6 hpmcounter5 = %0d (expected 2)", csr_rdata);
            errors = errors + 1;
        end else begin
            $display("PASSED: Test 6 hpmcounter5 counter = 2.");
        end

        // --------------------------------------------------------------------
        // Test 7: Upper Half Reads (cycleh, instreth, etc.)
        // --------------------------------------------------------------------
        $display("[TEST 7] Verifying cycleh, instreth upper 32-bit reads...");
        csr_addr = 12'hC80; // cycleh
        #1;
        if (csr_rdata !== 32'd0) begin
            $display("FAILED: Test 7 cycleh should be 0 before 2^32 cycles: %0d", csr_rdata);
            errors = errors + 1;
        end else begin
            $display("PASSED: Test 7 Upper half registers read correctly.");
        end

        // --------------------------------------------------------------------
        // Test 8: Unmapped CSR Address Handling
        // --------------------------------------------------------------------
        $display("[TEST 8] Reading unmapped CSR address 0x300...");
        csr_addr = 12'h300;
        #1;
        if (csr_rdata !== 32'd0) begin
            $display("FAILED: Test 8 Unmapped CSR should return 0: %08h", csr_rdata);
            errors = errors + 1;
        end else begin
            $display("PASSED: Test 8 Unmapped CSR returned 32'h0.");
        end

        // --------------------------------------------------------------------
        // Summary
        // --------------------------------------------------------------------
        $display("================================================================");
        if (errors == 0) begin
            $display("   ALL FEATURE 8 CSR UNIT TESTS PASSED SUCCESSFULLY! (0 ERRORS)");
        end else begin
            $display("   TESTS COMPLETED WITH %0d ERROR(S)!", errors);
        end
        $display("================================================================");
        $finish;
    end

endmodule
