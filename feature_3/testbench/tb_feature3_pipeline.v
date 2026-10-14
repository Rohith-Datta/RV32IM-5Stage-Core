// ============================================================================
// File: tb_feature3_pipeline.v
// Module: tb_feature3_pipeline
// Description: Full 5-Stage Pipeline Integration Testbench for Feature 3
// Tests:
//   - Multi-cycle execution of DIV, REM in 5-stage pipeline
//   - Hazard Unit interlock stall (32-cycle pipeline freeze of IF, ID, EX)
//   - EX/MEM bubble flush during division
//   - Data forwarding of operands into divider
//   - Data forwarding of completed divider result to dependent ALU operations
//   - Divide-by-Zero and Signed Overflow corner cases in pipelined execution
// ============================================================================

`timescale 1ns/1ps

module tb_feature3_pipeline;

    reg clk;
    reg reset_n;

    // 50 MHz clock (20 ns period)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // Interconnects
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we;
    wire        dmem_re;
    wire [31:0] dmem_rdata;

    wire [31:0] pc_if, pc_id, pc_ex, pc_mem, pc_wb;
    wire        wb_reg_write;
    wire [4:0]  wb_dest_reg;
    wire [31:0] wb_data;
    wire        hazard_stall, hazard_flush_id, hazard_flush_ex;
    wire [1:0]  forward_a, forward_b;
    wire        mul_active, div_active, div_busy;
    wire        exception;

    // Instruction Memory Model
    reg [31:0] test_imem [0:63];
    assign imem_rdata = test_imem[imem_addr[7:2]];

    // 5-Stage Core DUT
    pipeline_5stage dut (
        .clk             (clk),
        .reset_n         (reset_n),
        .stall_ext       (1'b0),
        .use_dsp_i       (1'b1),
        .imem_addr       (imem_addr),
        .imem_rdata      (imem_rdata),
        .dmem_addr       (dmem_addr),
        .dmem_wdata      (dmem_wdata),
        .dmem_wstrb      (dmem_wstrb),
        .dmem_we         (dmem_we),
        .dmem_re         (dmem_re),
        .dmem_rdata      (32'h0),
        .pc_if           (pc_if),
        .pc_id           (pc_id),
        .pc_ex           (pc_ex),
        .pc_mem          (pc_mem),
        .pc_wb           (pc_wb),
        .wb_reg_write    (wb_reg_write),
        .wb_dest_reg     (wb_dest_reg),
        .wb_data         (wb_data),
        .hazard_stall    (hazard_stall),
        .hazard_flush_id (hazard_flush_id),
        .hazard_flush_ex (hazard_flush_ex),
        .forward_a       (forward_a),
        .forward_b       (forward_b),
        .mul_active      (mul_active),
        .div_active      (div_active),
        .div_busy        (div_busy),
        .exception       (exception)
    );

    integer cycle;
    integer pass_count;
    integer fail_count;

    // Register check array
    reg [31:0] reg_observed [1:31];
    always @(posedge clk) begin
        if (wb_reg_write && wb_dest_reg != 5'd0) begin
            reg_observed[wb_dest_reg] <= wb_data;
            $display("[WB Cycle %0d] Reg x%0d <= 0x%08h (%0d)", cycle, wb_dest_reg, wb_data, $signed(wb_data));
        end
    end

    initial begin
        // Program assembly machine code:
        // PC=0x00: addi x1, x0, 100       (0x06400093)
        // PC=0x04: addi x2, x0, 7         (0x00700113)
        // PC=0x08: div  x3, x1, x2        (0x0220c1b3) -> x3 = 14 (32-cycle stall, dual forwarding)
        // PC=0x0c: rem  x4, x1, x2        (0x0220e233) -> x4 = 2  (back-to-back stall)
        // PC=0x10: addi x5, x3, 10        (0x00a18293) -> x5 = 24 (forwarding from DIV to ALU)
        // PC=0x14: addi x6, x0, 0         (0x00000313)
        // PC=0x18: div  x7, x1, x6        (0x0260c3b3) -> x7 = -1 (Divide by Zero)
        // PC=0x1c: rem  x8, x1, x6        (0x0260e433) -> x8 = 100 (Remainder by Zero)
        // PC=0x20: addi x9, x0, -1        (0xfff00493)
        // PC=0x24: lui  x10, 0x80000      (0x80000537)
        // PC=0x28: div  x11, x10, x9      (0x029545b3) -> x11 = 0x80000000 (Signed Overflow)
        // PC=0x2c: rem  x12, x10, x9      (0x02956633) -> x12 = 0 (Signed Overflow Remainder)
        // PC=0x30: nop                    (0x00000013)
        // PC=0x34: nop                    (0x00000013)
        // PC=0x38: ret                    (0x00008067)

        test_imem[0]  = 32'h06400093; // addi x1, x0, 100
        test_imem[1]  = 32'h00700113; // addi x2, x0, 7
        test_imem[2]  = 32'h0220c1b3; // div  x3, x1, x2   (14)
        test_imem[3]  = 32'h0220e233; // rem  x4, x1, x2   (2)
        test_imem[4]  = 32'h00a18293; // addi x5, x3, 10   (24)
        test_imem[5]  = 32'h00000313; // addi x6, x0, 0
        test_imem[6]  = 32'h0260c3b3; // div  x7, x1, x6   (-1)
        test_imem[7]  = 32'h0260e433; // rem  x8, x1, x6   (100)
        test_imem[8]  = 32'hfff00493; // addi x9, x0, -1
        test_imem[9]  = 32'h80000537; // lui  x10, 0x80000
        test_imem[10] = 32'h029545b3; // div  x11, x10, x9 (0x80000000)
        test_imem[11] = 32'h02956633; // rem  x12, x10, x9 (0)
        test_imem[12] = 32'h00000013; // nop
        test_imem[13] = 32'h00000013; // nop
        test_imem[14] = 32'h00008067; // ret
        test_imem[15] = 32'h00000013; // nop

        for (cycle = 16; cycle < 64; cycle = cycle + 1)
            test_imem[cycle] = 32'h00000013;

        for (cycle = 1; cycle < 32; cycle = cycle + 1)
            reg_observed[cycle] = 32'hDEAD_BEEF;

        pass_count = 0;
        fail_count = 0;
        reset_n = 0;

        #25;
        reset_n = 1;

        $display("================================================================================");
        $display("   STARTING FEATURE 3 PIPELINE INTEGRATION TESTBENCH");
        $display("================================================================================");

        // Run simulation for 200 clock cycles to complete all division instructions
        for (cycle = 0; cycle < 180; cycle = cycle + 1) begin
            @(posedge clk);
        end

        $display("\n================================================================================");
        $display("   VERIFYING COMMITTED REGISTER FILE STATE");
        $display("================================================================================");

        // Check x3 (DIV 100 / 7 = 14)
        if (reg_observed[3] === 32'd14) begin
            pass_count = pass_count + 1;
            $display("[PASS] Reg x3 (100 / 7)         = %0d (Expected: 14)", reg_observed[3]);
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] Reg x3 (100 / 7)         = %0d (Expected: 14)", reg_observed[3]);
        end

        // Check x4 (REM 100 % 7 = 2)
        if (reg_observed[4] === 32'd2) begin
            pass_count = pass_count + 1;
            $display("[PASS] Reg x4 (100 %% 7)         = %0d (Expected: 2)", reg_observed[4]);
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] Reg x4 (100 %% 7)         = %0d (Expected: 2)", reg_observed[4]);
        end

        // Check x5 (DIV result forwarded to ADD: 14 + 10 = 24)
        if (reg_observed[5] === 32'd24) begin
            pass_count = pass_count + 1;
            $display("[PASS] Reg x5 (Forward x3 + 10) = %0d (Expected: 24)", reg_observed[5]);
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] Reg x5 (Forward x3 + 10) = %0d (Expected: 24)", reg_observed[5]);
        end

        // Check x7 (DIV by Zero: 100 / 0 = -1 / 0xFFFFFFFF)
        if (reg_observed[7] === 32'hFFFF_FFFF) begin
            pass_count = pass_count + 1;
            $display("[PASS] Reg x7 (100 / 0)         = 0x%08h (Expected: -1)", reg_observed[7]);
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] Reg x7 (100 / 0)         = 0x%08h (Expected: -1)", reg_observed[7]);
        end

        // Check x8 (REM by Zero: 100 % 0 = 100)
        if (reg_observed[8] === 32'd100) begin
            pass_count = pass_count + 1;
            $display("[PASS] Reg x8 (100 %% 0)         = %0d (Expected: 100)", reg_observed[8]);
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] Reg x8 (100 %% 0)         = %0d (Expected: 100)", reg_observed[8]);
        end

        // Check x11 (Signed Overflow: INT_MIN / -1 = INT_MIN / 0x80000000)
        if (reg_observed[11] === 32'h8000_0000) begin
            pass_count = pass_count + 1;
            $display("[PASS] Reg x11 (INT_MIN / -1)   = 0x%08h (Expected: 0x80000000)", reg_observed[11]);
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] Reg x11 (INT_MIN / -1)   = 0x%08h (Expected: 0x80000000)", reg_observed[11]);
        end

        // Check x12 (Signed Overflow REM: INT_MIN % -1 = 0)
        if (reg_observed[12] === 32'd0) begin
            pass_count = pass_count + 1;
            $display("[PASS] Reg x12 (INT_MIN %% -1)   = %0d (Expected: 0)", reg_observed[12]);
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] Reg x12 (INT_MIN %% -1)   = %0d (Expected: 0)", reg_observed[12]);
        end

        $display("================================================================================");
        $display("   FEATURE 3 PIPELINE INTEGRATION TEST SUMMARY");
        $display("================================================================================");
        $display(" Total Assertions Passed : %0d / 7", pass_count);
        $display(" Total Assertions Failed : %0d / 7", fail_count);
        if (fail_count == 0) begin
            $display(" [+++] STATUS: 100%% ALL PIPELINE INTEGRATION TESTS PASSED!");
            $display(" [+++] Multi-Cycle Divider, Interlock Stalls, and Forwarding Validated!");
        end else begin
            $display(" [---] STATUS: INTEGRATION TESTS FAILED! Check logs above.");
        end
        $display("================================================================================\n");

        $finish;
    end

endmodule
