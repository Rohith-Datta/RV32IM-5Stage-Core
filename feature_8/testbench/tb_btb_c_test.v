// ============================================================================
// File: tb_btb_c_test.v
// Module: tb_btb_c_test
// Description: Testbench for verifying bare-metal C program (btb.c) on
//              5-stage RV32IMF pipeline with Static 32-Entry BTB.
// ============================================================================

`timescale 1ns/1ps

module tb_btb_c_test;

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

    // Pipeline telemetry
    wire [31:0] pc_if, pc_id, pc_ex, pc_mem, pc_wb;
    wire        wb_reg_write;
    wire [4:0]  wb_dest_reg;
    wire [31:0] wb_data;

    wire        hazard_stall;
    wire        hazard_flush_id;
    wire        hazard_flush_ex;
    wire [1:0]  forward_a, forward_b;
    wire        mul_active, div_active, div_busy, fpu_active, fpu_busy, exception;

    wire        btb_pred_hit;
    wire        btb_pred_taken;
    wire        btb_mispredict;

    reg [31:0] return_val_a0;
    reg        saw_ret;
    integer    drain_cnt;

    // IMEM and DMEM instances
    instr_mem #(
        .HEX_FILE("imem.hex"),
        .WORDS(1024)
    ) u_imem (
        .clk  (clk),
        .pc   (imem_addr),
        .instr(imem_rdata)
    );

    data_mem #(
        .HEX_FILE("dmem.hex"),
        .WORDS(1024)
    ) u_dmem (
        .clk  (clk),
        .re   (dmem_re),
        .raddr(dmem_addr),
        .rdata(dmem_rdata),
        .we   (dmem_we),
        .waddr(dmem_addr),
        .wdata(dmem_wdata),
        .wstrb(dmem_wstrb)
    );

    // Feed NOP once RET is fetched to drain pipeline
    wire [31:0] imem_rdata_core = saw_ret ? 32'h0000_0013 : imem_rdata;

    pipeline_5stage #(
        .RESET_PC(32'h0000_0000)
    ) dut (
        .clk            (clk),
        .reset_n        (reset_n),
        .stall_ext      (1'b0),
        .use_dsp_i      (1'b1),
        .imem_addr      (imem_addr),
        .imem_rdata     (imem_rdata_core),
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

    integer cycle = 0;
    integer branches = 0;
    integer hits = 0;
    integer misses = 0;

    initial begin
        clk = 0;
        reset_n = 0;
        saw_ret = 0;
        drain_cnt = 0;
        return_val_a0 = 0;
        #25;
        reset_n = 1;
        $display("=== Reset deasserted: starting btb.c test ===");
    end

    always @(posedge clk) begin
        if (reset_n) begin
            cycle <= cycle + 1;

            if (wb_reg_write && wb_dest_reg == 5'd10) begin
                return_val_a0 <= wb_data;
            end

            // Track branches in EX stage
            if (dut.id_ex_branch || dut.id_ex_jal || dut.id_ex_jalr) begin
                if (dut.id_ex_branch) begin
                    branches <= branches + 1;
                    if (btb_mispredict) begin
                        misses <= misses + 1;
                        $display("[CC=%3d] EX Branch PC=0x%08h -> MISPREDICT (taken=%b, pred=%b)",
                                 cycle, pc_ex, dut.ex_branch_taken, dut.id_ex_pred_taken);
                    end else begin
                        hits <= hits + 1;
                        $display("[CC=%3d] EX Branch PC=0x%08h -> HIT / CORRECT (taken=%b)",
                                 cycle, pc_ex, dut.ex_branch_taken);
                    end
                end
            end

            // Detect ret (0x00008067)
            if (imem_rdata == 32'h0000_8067 && pc_if != 32'h0 && !saw_ret) begin
                saw_ret <= 1'b1;
                $display("[CC=%3d] Detected RET instruction at PC=0x%08h! Draining pipeline...", cycle, pc_if);
            end

            if (saw_ret) begin
                drain_cnt <= drain_cnt + 1;
                if (drain_cnt >= 4) begin
                    $display("\n========================================================");
                    $display(" BARE-METAL C PROGRAM (btb.c) VERIFICATION COMPLETE");
                    $display("========================================================");
                    $display(" Total Clock Cycles : %0d", cycle);
                    $display(" Final Return (a0)  : %0d (0x%08h) (Expected: 6)", return_val_a0, return_val_a0);
                    $display(" Total Branches     : %0d", branches);
                    $display(" BTB Hits           : %0d", hits);
                    $display(" BTB Mispredicts    : %0d", misses);
                    $display("========================================================\n");
                    if (return_val_a0 === 32'd6 && cycle <= 80) begin
                        $display("[TEST PASS] return value matches 6 and cycles <= 80!");
                    end else begin
                        $display("[TEST FAIL] return_val=%0d, cycles=%0d", return_val_a0, cycle);
                    end
                    $finish;
                end
            end

            if (cycle >= 150) begin
                $display("[TIMEOUT] Reached cycle 150!");
                $finish;
            end
        end
    end

endmodule
