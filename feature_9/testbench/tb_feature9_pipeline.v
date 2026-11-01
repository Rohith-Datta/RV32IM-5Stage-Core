// ============================================================================
// File: tb_feature9_pipeline.v
// Module: tb_feature9_pipeline
// Description: Pipeline-level verification for Feature 9: RV32 Zbb Extension
// Runs the deterministic 23-instruction sequence from PC 0x00 to 0x58
// Verifies all 22 calculated writeback values and ensures 0 pipeline stalls.
// ============================================================================

`timescale 1ns/1ps

module tb_feature9_pipeline;

    reg clk;
    reg reset_n;

    // Clock generation (50 MHz = 20 ns period)
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

    // Memories
    instr_mem #(
        .HEX_FILE("imem.hex"),
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

    // 5-Stage Core
    pipeline_5stage #(
        .RESET_PC(32'h0000_0000)
    ) u_dut (
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

    // Expected Values Table
    reg [31:0] expected_pc   [0:21];
    reg [4:0]  expected_rd   [0:21];
    reg [31:0] expected_val  [0:21];
    reg [127:0] expected_inst[0:21];

    initial begin
        expected_pc[0]  = 32'h00000000; expected_rd[0]  = 5'd1;  expected_val[0]  = 32'hFFFFFFFE; expected_inst[0]  = "addi x1, x0, -2";
        expected_pc[1]  = 32'h00000004; expected_rd[1]  = 5'd2;  expected_val[1]  = 32'h00000005; expected_inst[1]  = "addi x2, x0, 5";
        expected_pc[2]  = 32'h00000008; expected_rd[2]  = 5'd3;  expected_val[2]  = 32'h00000001; expected_inst[2]  = "andn x3, x2, x1";
        expected_pc[3]  = 32'h0000000C; expected_rd[3]  = 5'd4;  expected_val[3]  = 32'h00000005; expected_inst[3]  = "orn  x4, x2, x1";
        expected_pc[4]  = 32'h00000010; expected_rd[4]  = 5'd5;  expected_val[4]  = 32'h00000004; expected_inst[4]  = "xnor x5, x2, x1";
        expected_pc[5]  = 32'h00000014; expected_rd[5]  = 5'd6;  expected_val[5]  = 32'h00000005; expected_inst[5]  = "max  x6, x1, x2";
        expected_pc[6]  = 32'h00000018; expected_rd[6]  = 5'd7;  expected_val[6]  = 32'hFFFFFFFE; expected_inst[6]  = "maxu x7, x1, x2";
        expected_pc[7]  = 32'h0000001C; expected_rd[7]  = 5'd8;  expected_val[7]  = 32'hFFFFFFFE; expected_inst[7]  = "min  x8, x1, x2";
        expected_pc[8]  = 32'h00000020; expected_rd[8]  = 5'd9;  expected_val[8]  = 32'h00000005; expected_inst[8]  = "minu x9, x1, x2";
        expected_pc[9]  = 32'h00000024; expected_rd[9]  = 5'd10; expected_val[9]  = 32'hFFFFFFFF; expected_inst[9]  = "addi x10, x0, -1";
        expected_pc[10] = 32'h00000028; expected_rd[10] = 5'd11; expected_val[10] = 32'h0000FFFF; expected_inst[10] = "zext.h x11, x10";
        expected_pc[11] = 32'h0000002C; expected_rd[11] = 5'd12; expected_val[11] = 32'hFFFFFFFF; expected_inst[11] = "sext.h x12, x10";
        expected_pc[12] = 32'h00000030; expected_rd[12] = 5'd13; expected_val[12] = 32'hFFFFFFFF; expected_inst[12] = "sext.b x13, x10";
        expected_pc[13] = 32'h00000034; expected_rd[13] = 5'd14; expected_val[13] = 32'h000000F0; expected_inst[13] = "addi x14, x0, 0x0F0";
        expected_pc[14] = 32'h00000038; expected_rd[14] = 5'd15; expected_val[14] = 32'h00000018; expected_inst[14] = "clz  x15, x14";
        expected_pc[15] = 32'h0000003C; expected_rd[15] = 5'd16; expected_val[15] = 32'h00000004; expected_inst[15] = "ctz  x16, x14";
        expected_pc[16] = 32'h00000040; expected_rd[16] = 5'd17; expected_val[16] = 32'h00000004; expected_inst[16] = "cpop x17, x14";
        expected_pc[17] = 32'h00000044; expected_rd[17] = 5'd18; expected_val[17] = 32'h00001E00; expected_inst[17] = "rol  x18, x14, x2";
        expected_pc[18] = 32'h00000048; expected_rd[18] = 5'd19; expected_val[18] = 32'h80000007; expected_inst[18] = "ror  x19, x14, x2";
        expected_pc[19] = 32'h0000004C; expected_rd[19] = 5'd20; expected_val[19] = 32'h0000000F; expected_inst[19] = "rori x20, x14, 4";
        expected_pc[20] = 32'h00000050; expected_rd[20] = 5'd21; expected_val[20] = 32'hF0000000; expected_inst[20] = "rev8 x21, x14";
        expected_pc[21] = 32'h00000054; expected_rd[21] = 5'd22; expected_val[21] = 32'h000000FF; expected_inst[21] = "orc.b x22, x14";
    end

    integer retired_count = 0;
    integer pass_count    = 0;
    integer fail_count    = 0;
    integer stall_count   = 0;

    // Track writeback results
    always @(posedge clk) begin
        if (reset_n) begin
            if (hazard_stall && (pc_ex >= 32'h08 && pc_ex <= 32'h54)) begin
                $display("[WARNING] Hazard stall during Zbb execution at PC 0x%08X", pc_ex);
                stall_count = stall_count + 1;
            end

            if (wb_reg_write && (wb_dest_reg != 5'd0) && (pc_wb <= 32'h00000054)) begin
                if (retired_count < 22) begin
                    if (wb_data === expected_val[retired_count] &&
                        wb_dest_reg === expected_rd[retired_count] &&
                        pc_wb === expected_pc[retired_count]) begin
                        $display("[WB MATCH #%02d] PC=0x%08X %0s -> x%0d = 0x%08X (OK)",
                                 retired_count, pc_wb, expected_inst[retired_count], wb_dest_reg, wb_data);
                        pass_count = pass_count + 1;
                    end else begin
                        $display("[WB ERROR #%02d] PC=0x%08X %0s -> Got x%0d=0x%08X, Expected x%0d=0x%08X",
                                 retired_count, pc_wb, expected_inst[retired_count],
                                 wb_dest_reg, wb_data, expected_rd[retired_count], expected_val[retired_count]);
                        fail_count = fail_count + 1;
                    end
                    retired_count = retired_count + 1;
                end
            end

            if (pc_wb == 32'h00000058) begin
                $display("--------------------------------------------------");
                $display(" Reached NOP at 0x00000058 in WB stage! Run complete.");
                $display(" Summary: %0d / 22 Instructions Passed (%0d Failed)", pass_count, fail_count);
                $display(" Stall cycles during Zbb: %0d", stall_count);
                $display("--------------------------------------------------");
                if (fail_count == 0 && stall_count == 0 && retired_count == 22) begin
                    $display(">>> ALL 22 INSTRUCTIONS RETIRED WITH 100%% EXACT EXPECTED VALUES AND 0 STALLS! <<<");
                end else begin
                    $display(">>> PIPELINE VERIFICATION FAILED! <<<");
                end
                #40;
                $finish;
            end
        end
    end

    initial begin
        clk     = 0;
        reset_n = 0;
        #50;
        @(negedge clk);
        reset_n = 1;
        $display("==================================================");
        $display(" STARTING FEATURE 9 PIPELINE VERIFICATION RUN");
        $display("==================================================");

        // Safety timeout
        #10000;
        $display("[TIMEOUT] Simulation did not complete within 10,000 ns!");
        $finish;
    end

endmodule
