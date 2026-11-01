// ============================================================================
// File: tb_feature9_c_test.v
// Module: tb_feature9_c_test
// Description: Testbench for Feature 9 Bare-Metal C Program (zbb.c)
//              Verifies that the RV32 Core executes all 18 Zbb instructions
//              and returns 18 (0x12) in register a0 (x10) on 100% pass.
// ============================================================================

`timescale 1ns/1ps

module tb_feature9_c_test;

    reg clk;
    reg reset_n;

    // 50 MHz clock (20 ns period)
    always #10 clk = ~clk;

    // Memory wires
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we;
    wire        dmem_re;
    wire [31:0] dmem_rdata;

    // Pipeline monitoring wires
    wire [31:0] pc_if;
    wire [31:0] pc_id;
    wire [31:0] pc_ex;
    wire [31:0] pc_mem;
    wire [31:0] pc_wb;
    wire        wb_reg_write;
    wire [4:0]  wb_dest_reg;
    wire [31:0] wb_data;
    wire        hazard_stall;

    // Instruction memory loaded with compiled zbb.c
    instr_mem #(
        .HEX_FILE("imem_c.hex"),
        .WORDS(1024)
    ) u_imem (
        .clk   (clk),
        .pc    (imem_addr),
        .instr (imem_rdata)
    );

    data_mem #(
        .HEX_FILE("dmem.hex"),
        .WORDS(1024)
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

    // 5-Stage RV32 Core with Zbb
    pipeline_5stage #(
        .RESET_PC(32'h0000_0000)
    ) u_core (
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
        .hazard_flush_id(),
        .hazard_flush_ex(),
        .forward_a      (),
        .forward_b      (),
        .mul_active     (),
        .div_active     (),
        .div_busy       (),
        .fpu_active     (),
        .fpu_busy       (),
        .exception      (),
        .btb_pred_hit   (),
        .btb_pred_taken (),
        .btb_mispredict ()
    );

    reg [31:0] cycle_count;
    reg [31:0] inst_retired;
    reg [31:0] final_a0;

    // Dedicated Writeback Monitor
    always @(posedge clk) begin
        if (reset_n && wb_reg_write && !hazard_stall) begin
            inst_retired <= inst_retired + 1;
            if (wb_dest_reg == 5'd10) begin
                final_a0 <= wb_data;
            end
        end
    end

    initial begin
        clk = 0;
        reset_n = 0;
        cycle_count = 0;
        inst_retired = 0;
        final_a0 = 0;

        #40;
        @(negedge clk);
        reset_n = 1;

        // Monitor execution
        while (cycle_count < 2000) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;

            // Detect ret instruction (0x00008067)
            if (imem_rdata == 32'h0000_8067 && pc_if != 32'd0) begin
                // Wait for complete pipeline drain through Writeback stage
                repeat (15) @(posedge clk);
                $display("\n============================================================");
                $display(" FEATURE 9: BARE-METAL C BENCHMARK (zbb.c) EXECUTION");
                $display("============================================================");
                $display(" Total Cycles Elapsed       : %0d", cycle_count);
                $display(" Instructions Retired       : %0d", inst_retired);
                $display(" Final a0 Return Value (x10): %0d (Expected: 18)", final_a0);
                if (final_a0 == 32'd18) begin
                    $display(" STATUS                     : [PASS] All 18 Zbb Instructions Verified!");
                end else begin
                    $display(" STATUS                     : [FAIL] Expected 18, got %0d", final_a0);
                end
                $display("============================================================\n");
                $finish;
            end
        end

        $display("[TIMEOUT] Simulation reached cycle limit without completing.");
        $finish;
    end

endmodule
