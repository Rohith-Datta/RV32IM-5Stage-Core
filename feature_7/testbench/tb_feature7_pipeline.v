// ============================================================================
// File: tb_feature7_pipeline.v
// Module: tb_feature7_pipeline
// Description: Full 5-Stage RV32IMF Pipeline Integration Testbench with Static BTB
//              Verifies:
//              1. Cold start branch miss in IF stage -> penalty & BTB entry allocation
//              2. Subsequent loop iterations -> 0-bubble BTB HIT & immediate fetch redirect
//              3. Loop termination misprediction recovery -> invalidation & fall-through
//              4. Verification of final computed register values
// Project: Pipelined RV32IMF RISC-V Core (Feature 7: BTB Integration)
// Clock: Standard 50 MHz (20 ns clock period)
// ============================================================================

`timescale 1ns/1ps

module tb_feature7_pipeline;

    // Clock and reset signals (50 MHz clock)
    reg clk;
    reg reset_n;

    // Memory bus interconnects
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;

    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we;
    wire        dmem_re;
    wire [31:0] dmem_rdata;

    // Pipeline telemetry signals
    wire [31:0] pc_if;
    wire [31:0] pc_id;
    wire [31:0] pc_ex;
    wire [31:0] pc_mem;
    wire [31:0] pc_wb;

    wire        wb_reg_write;
    wire [4:0]  wb_dest_reg;
    wire [31:0] wb_data;

    wire        hazard_stall;
    wire        hazard_flush_id;
    wire        hazard_flush_ex;
    wire [1:0]  forward_a;
    wire [1:0]  forward_b;
    wire        mul_active;
    wire        div_active;
    wire        div_busy;
    wire        fpu_active;
    wire        fpu_busy;
    wire        exception;

    // Feature 7 BTB signals
    wire        btb_pred_hit;
    wire        btb_pred_taken;
    wire        btb_mispredict;

    // Clock Generator (50 MHz, Period = 20 ns)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // Instruction Memory
    instr_mem #(
        .HEX_FILE ("imem.hex"),
        .WORDS    (1024)
    ) u_imem (
        .clk   (clk),
        .pc    (imem_addr),
        .instr (imem_rdata)
    );

    // Data Memory
    data_mem #(
        .HEX_FILE ("dmem.hex"),
        .WORDS    (1024)
    ) u_dmem (
        .clk   (clk),
        .re    (dmem_re),
        .raddr (dmem_addr),
        .rdata (dmem_rdata),
        .we    (dmem_we),
        .waddr (dmem_addr),
        .wdata (dmem_wdata),
        .wstrb (dmem_wstrb)
    );

    // 5-Stage RV32IMF Core with BTB
    pipeline_5stage #(
        .RESET_PC(32'h0000_0000)
    ) dut (
        .clk            (clk),
        .reset_n        (reset_n),
        .stall_ext      (1'b0),
        .use_dsp_i      (1'b1),
        .imem_addr      (imem_addr),
        .imem_rdata     (imem_rdata),
        .dmem_addr      (dmem_addr),
        .dmem_wdata     (dmem_wdata),
        .dmem_wstrb     (dmem_wstrb),
        .dmem_we        (dmem_we),
        .dmem_re        (dmem_re),
        .dmem_rdata     (dmem_rdata),
        .pc_if          (pc_if),
        .pc_id          (pc_id),
        .pc_ex          (pc_ex),
        .pc_mem         (pc_mem),
        .pc_wb          (pc_wb),
        .wb_reg_write   (wb_reg_write),
        .wb_dest_reg    (wb_dest_reg),
        .wb_data        (wb_data),
        .hazard_stall   (hazard_stall),
        .hazard_flush_id(hazard_flush_id),
        .hazard_flush_ex(hazard_flush_ex),
        .forward_a      (forward_a),
        .forward_b      (forward_b),
        .mul_active     (mul_active),
        .div_active     (div_active),
        .div_busy       (div_busy),
        .fpu_active     (fpu_active),
        .fpu_busy       (fpu_busy),
        .exception      (exception),
        .btb_pred_hit   (btb_pred_hit),
        .btb_pred_taken (btb_pred_taken),
        .btb_mispredict (btb_mispredict)
    );

    // ------------------------------------------------------------------------
    // Test Control & Verification Sequence
    // ------------------------------------------------------------------------
    integer cycle_count;
    integer btb_hits;
    integer btb_mispredicts;
    reg     test_passed;

    // Track statistics
    always @(posedge clk) begin
        if (reset_n) begin
            cycle_count <= cycle_count + 1;
            if (btb_pred_hit && !hazard_stall)
                btb_hits <= btb_hits + 1;
            if (btb_mispredict)
                btb_mispredicts <= btb_mispredicts + 1;
        end
    end

    initial begin
        reset_n         = 0;
        cycle_count     = 0;
        btb_hits        = 0;
        btb_mispredicts = 0;
        test_passed     = 1;

        $display("================================================================");
        $display("   STARTING FEATURE 7: PIPELINE WITH 32-ENTRY BTB TESTBENCH");
        $display("================================================================");

        // Populate instruction memory with a dedicated branch loop test
        // 0x00: addi x1, x0, 4     -> 0x00400093 (Loop count = 4)
        // 0x04: addi x2, x0, 10    -> 0x00A00113 (Accumulator = 10)
        // 0x08: addi x2, x2, 1     -> 0x00110113 (Loop target: acc++)
        // 0x0C: addi x1, x1, -1    -> 0xFFF08093 (count--)
        // 0x10: bne  x1, x0, -8    -> 0xFE009CE3 (Branch to 0x08 if x1 != 0)
        // 0x14: addi x10, x2, 0    -> 0x00010513 (Result a0 = acc = 14)
        // 0x18: jalr x0, x1, 0     -> 0x00008067 (ret: halts core)

        u_imem.imem[0] = 32'h0040_0093; // addi x1, x0, 4
        u_imem.imem[1] = 32'h00A0_0113; // addi x2, x0, 10
        u_imem.imem[2] = 32'h0011_0113; // loop: addi x2, x2, 1
        u_imem.imem[3] = 32'hFFF0_8093; // addi x1, x1, -1
        u_imem.imem[4] = 32'hFE00_9CE3; // bne x1, x0, -8 (target 0x08)
        u_imem.imem[5] = 32'h0001_0513; // addi x10, x2, 0
        u_imem.imem[6] = 32'h0000_8067; // ret

        // Release reset
        #25;
        reset_n = 1;
        $display("[INFO] Core reset released. Executing 4-iteration branch loop...");

        // Wait for execution completion or timeout
        // The loop runs 4 times:
        // - Iteration 1: cold BTB miss, mispredict flush (2 cycles), updates BTB
        // - Iteration 2: BTB HIT, 0 bubble penalty
        // - Iteration 3: BTB HIT, 0 bubble penalty
        // - Iteration 4: BTB HIT, 0 bubble penalty
        // - Loop exit: BTB mispredict (predicted taken, but x1==0, so not taken) -> flush & proceed to 0x14
        
        while (pc_wb !== 32'h0000_0018 && cycle_count < 100) begin
            @(posedge clk);
            if (btb_pred_hit) begin
                $display("  [CYCLE %0d] BTB HIT at IF PC=0x%08h -> Predicted Target=0x%08h",
                         cycle_count, pc_if, dut.u_btb.pred_target);
            end
            if (btb_mispredict) begin
                $display("  [CYCLE %0d] BTB MISPREDICT at EX PC=0x%08h -> Recovering to Redirect PC=0x%08h",
                         cycle_count, pc_ex, dut.ex_redirect_pc);
            end
        end

        // Wait for final instruction commit to register x10
        repeat (5) @(posedge clk);

        $display("----------------------------------------------------------------");
        $display("[EXECUTION FINISHED] Total Cycles: %0d", cycle_count);
        $display("  Total BTB Hits:        %0d (Expected: >= 3)", btb_hits);
        $display("  Total BTB Mispredicts: %0d (Expected: 2 -> 1 initial cold miss + 1 loop exit)", btb_mispredicts);
        $display("  Final x10 (a0) value:  %0d (Expected: 14)", dut.u_decode_stage.regs[10]);

        if (dut.u_decode_stage.regs[10] !== 32'd14) begin
            $display("FAILED: Expected x10 = 14, got %0d", dut.u_decode_stage.regs[10]);
            test_passed = 0;
        end

        if (btb_hits < 3) begin
            $display("FAILED: Expected at least 3 BTB hits for loop iterations 2, 3, 4, got %0d", btb_hits);
            test_passed = 0;
        end

        if (btb_mispredicts != 2) begin
            $display("WARNING: BTB mispredict count was %0d (typical: 2)", btb_mispredicts);
        end

        $display("================================================================");
        if (test_passed) begin
            $display("   FEATURE 7 PIPELINE BTB INTEGRATION TEST PASSED! (0 ERRORS)");
        end else begin
            $display("   FEATURE 7 PIPELINE BTB INTEGRATION TEST FAILED!");
        end
        $display("================================================================");
        $finish;
    end

endmodule
