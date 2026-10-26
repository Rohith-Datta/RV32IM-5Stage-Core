// ============================================================================
// File: tb_btb.v
// Module: tb_btb
// Description: Standalone Unit Testbench for Static 32-Entry Branch Target Buffer
// Project: Pipelined RV32IMF RISC-V Core (Feature 7: Static BTB Verification)
// Clock: 50 MHz (20 ns clock period)
//
// Test Coverage:
//   Test 1: Cold start verification (all valid bits zero, miss on arbitrary PC)
//   Test 2: Entry allocation on taken branch (PC=0x00000020 -> Target=0x00000080)
//   Test 3: Hit verification on next fetch cycle of PC=0x00000020
//   Test 4: Invalidation on branch not-taken (PC=0x00000020, taken=0)
//   Test 5: Miss verification after invalidation
//   Test 6: Full table allocation (all 32 entries with distinct indices)
//   Test 7: Direct-mapped tag conflict and replacement (same index, different tag)
//   Test 8: Synchronous reset verification (clears all 32 entries)
// ============================================================================

`timescale 1ns/1ps

module tb_btb;

    reg         clk;
    reg         reset_n;

    // IF Query Interface
    reg  [31:0] fetch_pc;
    wire        pred_hit;
    wire        pred_taken;
    wire [31:0] pred_target;

    // EX Update Interface
    reg         update_en;
    reg  [31:0] update_pc;
    reg  [31:0] update_target;
    reg         update_taken;

    // Instantiate BTB
    btb_branch_pred #(
        .ENTRIES   (32),
        .TAG_WIDTH (25)
    ) dut (
        .clk          (clk),
        .reset_n      (reset_n),
        .fetch_pc     (fetch_pc),
        .pred_hit     (pred_hit),
        .pred_taken   (pred_taken),
        .pred_target  (pred_target),
        .update_en    (update_en),
        .update_pc    (update_pc),
        .update_target(update_target),
        .update_taken (update_taken)
    );

    // 50 MHz clock generator
    always #10 clk = ~clk;

    integer errors;
    integer i;

    initial begin
        clk           = 0;
        reset_n       = 0;
        fetch_pc      = 32'd0;
        update_en     = 0;
        update_pc     = 32'd0;
        update_target = 32'd0;
        update_taken  = 0;
        errors        = 0;

        $display("================================================================");
        $display("   STARTING FEATURE 7: 32-ENTRY BTB UNIT TESTBENCH");
        $display("================================================================");

        // Apply Reset
        #25;
        reset_n = 1;
        #15;

        // --------------------------------------------------------------------
        // Test 1: Cold start verification
        // --------------------------------------------------------------------
        $display("[TEST 1] Checking cold start - should miss on arbitrary PC");
        fetch_pc = 32'h0000_0020;
        #1;
        if (pred_hit !== 1'b0 || pred_taken !== 1'b0 || pred_target !== 32'h0000_0024) begin
            $display("FAILED: Test 1 Cold start. hit=%b, taken=%b, target=0x%08h",
                     pred_hit, pred_taken, pred_target);
            errors = errors + 1;
        end else begin
            $display("PASSED: Test 1 Cold start correctly missed.");
        end

        // --------------------------------------------------------------------
        // Test 2: Entry allocation on taken branch
        // --------------------------------------------------------------------
        $display("[TEST 2] Allocating entry: PC=0x00000020 -> Target=0x00000080 (taken=1)");
        @(posedge clk);
        #1;
        update_en     = 1;
        update_pc     = 32'h0000_0020;
        update_target = 32'h0000_0080;
        update_taken  = 1;
        @(posedge clk);
        #1;
        update_en     = 0;

        // --------------------------------------------------------------------
        // Test 3: Hit verification on next fetch cycle of PC=0x00000020
        // --------------------------------------------------------------------
        $display("[TEST 3] Querying PC=0x00000020");
        fetch_pc = 32'h0000_0020;
        #1;
        if (pred_hit !== 1'b1 || pred_taken !== 1'b1 || pred_target !== 32'h0000_0080) begin
            $display("FAILED: Test 3 Hit verification. hit=%b, taken=%b, target=0x%08h",
                     pred_hit, pred_taken, pred_target);
            errors = errors + 1;
        end else begin
            $display("PASSED: Test 3 BTB Hit correctly predicted taken with target 0x%08h", pred_target);
        end

        // --------------------------------------------------------------------
        // Test 4 & 5: Invalidation on branch not-taken
        // --------------------------------------------------------------------
        $display("[TEST 4 & 5] Invalidation on not-taken branch (PC=0x00000020, taken=0)");
        @(posedge clk);
        #1;
        update_en     = 1;
        update_pc     = 32'h0000_0020;
        update_target = 32'h0000_0080;
        update_taken  = 0;
        @(posedge clk);
        #1;
        update_en     = 0;

        fetch_pc = 32'h0000_0020;
        #1;
        if (pred_hit !== 1'b0 || pred_taken !== 1'b0 || pred_target !== 32'h0000_0024) begin
            $display("FAILED: Test 5 Invalidation. hit=%b, taken=%b, target=0x%08h",
                     pred_hit, pred_taken, pred_target);
            errors = errors + 1;
        end else begin
            $display("PASSED: Test 5 Correctly invalidated; subsequent query missed.");
        end

        // --------------------------------------------------------------------
        // Test 6: Full table allocation (all 32 entries)
        // --------------------------------------------------------------------
        $display("[TEST 6] Allocating all 32 direct-mapped BTB entries...");
        for (i = 0; i < 32; i = i + 1) begin
            @(posedge clk);
            #1;
            update_en     = 1;
            update_pc     = 32'h0000_1000 + (i << 2);
            update_target = 32'h0000_2000 + (i << 2);
            update_taken  = 1;
        end
        @(posedge clk);
        #1;
        update_en = 0;

        // Verify all 32 entries hit
        for (i = 0; i < 32; i = i + 1) begin
            fetch_pc = 32'h0000_1000 + (i << 2);
            #1;
            if (pred_hit !== 1'b1 || pred_target !== (32'h0000_2000 + (i << 2))) begin
                $display("FAILED: Test 6 Entry %0d hit=%b, target=0x%08h (expected 0x%08h)",
                         i, pred_hit, pred_target, 32'h0000_2000 + (i << 2));
                errors = errors + 1;
            end
        end
        if (errors == 0) $display("PASSED: Test 6 All 32 entries allocated and hit successfully.");

        // --------------------------------------------------------------------
        // Test 7: Direct-mapped tag conflict and replacement
        // --------------------------------------------------------------------
        $display("[TEST 7] Tag conflict: replacing entry at index 5 with new tag");
        // Index 5: PC was 0x0000_1014 (Index = 5). Now replace with PC 0x0001_1014 (Same index 5, new tag)
        @(posedge clk);
        #1;
        update_en     = 1;
        update_pc     = 32'h0001_1014;
        update_target = 32'h0009_9990;
        update_taken  = 1;
        @(posedge clk);
        #1;
        update_en = 0;

        // Old PC should now MISS (different tag)
        fetch_pc = 32'h0000_1014;
        #1;
        if (pred_hit !== 1'b0) begin
            $display("FAILED: Test 7 Old PC should have missed due to tag replacement! hit=%b", pred_hit);
            errors = errors + 1;
        end else begin
            $display("PASSED: Test 7 Old tag evicted correctly.");
        end

        // New PC should HIT
        fetch_pc = 32'h0001_1014;
        #1;
        if (pred_hit !== 1'b1 || pred_target !== 32'h0009_9990) begin
            $display("FAILED: Test 7 New PC should have hit! hit=%b, target=0x%08h", pred_hit, pred_target);
            errors = errors + 1;
        end else begin
            $display("PASSED: Test 7 New tag hits with updated target 0x%08h.", pred_target);
        end

        // --------------------------------------------------------------------
        // Test 8: Synchronous Reset Verification
        // --------------------------------------------------------------------
        $display("[TEST 8] Asserting reset - verifying all entries are cleared");
        @(posedge clk);
        #1;
        reset_n = 0;
        @(posedge clk);
        #1;
        reset_n = 1;
        #1;

        for (i = 0; i < 32; i = i + 1) begin
            fetch_pc = 32'h0000_1000 + (i << 2);
            #1;
            if (pred_hit !== 1'b0) begin
                $display("FAILED: Test 8 Entry %0d not cleared after reset! hit=%b", i, pred_hit);
                errors = errors + 1;
            end
        end
        if (errors == 0) $display("PASSED: Test 8 Reset cleared all 32 entries successfully.");

        // --------------------------------------------------------------------
        // Summary
        // --------------------------------------------------------------------
        $display("================================================================");
        if (errors == 0) begin
            $display("   ALL FEATURE 7 BTB UNIT TESTS PASSED SUCCESSFULLY! (0 ERRORS)");
        end else begin
            $display("   TESTS COMPLETED WITH %0d ERROR(S)!", errors);
        end
        $display("================================================================");
        $finish;
    end

endmodule
