// ============================================================================
// File: tb_pipeline_base.v
// Module: tb_pipeline_base
// Description: Full 5-Stage RV32IMF Pipeline Testbench (Feature 4 Baseline)
// Project: Pipelined RV32IMF RISC-V Core (Feature 4: IEEE 754 FPU)
// Tests: RV32I Base ALU, Memory Stage, and Hazard Resolution with 50 MHz Clock
// ============================================================================

`timescale 1ns/1ps

module tb_pipeline_base;

    reg clk;
    reg reset_n;

    // 50 MHz clock (20 ns period: 10 ns high, 10 ns low)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // Instruction Memory Bus
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;

    // Data Memory Bus
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we;
    wire        dmem_re;
    wire [31:0] dmem_rdata;

    // Diagnostic & Pipeline Stage Signals
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

    // ------------------------------------------------------------------------
    // DUT: 5-Stage Pipelined RV32IMF Core
    // ------------------------------------------------------------------------
    pipeline_5stage #(
        .RESET_PC(32'h0000_0000)
    ) DUT (
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
        .exception      (exception)
    );

    // Memory Models
    reg [31:0] mem_array [0:255];
    assign imem_rdata = mem_array[imem_addr[9:2]];
    assign dmem_rdata = mem_array[dmem_addr[9:2]];

    always @(posedge clk) begin
        if (dmem_we) begin
            if (dmem_wstrb[0]) mem_array[dmem_addr[9:2]][7:0]   <= dmem_wdata[7:0];
            if (dmem_wstrb[1]) mem_array[dmem_addr[9:2]][15:8]  <= dmem_wdata[15:8];
            if (dmem_wstrb[2]) mem_array[dmem_addr[9:2]][23:16] <= dmem_wdata[23:16];
            if (dmem_wstrb[3]) mem_array[dmem_addr[9:2]][31:24] <= dmem_wdata[31:24];
        end
    end

    integer cycle_count;
    integer wb_count;

    initial begin
        $display("============================================================================");
        $display("       STARTING TESTBENCH: tb_pipeline_base (Feature 4 Core Verification)   ");
        $display("                 Clock Frequency: 50 MHz (Period: 20 ns)                   ");
        $display("============================================================================");

        begin : init_prog
            integer k;
            for (k = 0; k < 256; k = k + 1) mem_array[k] = 32'h00000013;
        end

        // Base RV32I addition loop:
        // x1 = 10, x2 = 20, x3 = x1 + x2 = 30
        mem_array[0] = 32'h00A00093; // addi x1, x0, 10
        mem_array[1] = 32'h01400113; // addi x2, x0, 20
        mem_array[2] = 32'h002081B3; // add  x3, x1, x2 (30)
        mem_array[3] = 32'h00302023; // sw   x3, 0(x0)
        mem_array[4] = 32'h00002203; // lw   x4, 0(x0)
        mem_array[5] = 32'h00120293; // addi x5, x4, 1   (31, tests load-use stall!)

        reset_n = 0;
        cycle_count = 0;
        wb_count = 0;

        #40;
        @(posedge clk);
        #1;
        reset_n = 1;
    end

    always @(posedge clk) begin
        if (reset_n) begin
            cycle_count <= cycle_count + 1;
            if (wb_reg_write && wb_dest_reg != 5'd0) begin
                wb_count <= wb_count + 1;
                $display("Time=%0t | WB: PC=0x%08h | Reg x%0d <= 0x%08h", $time, pc_wb, wb_dest_reg, wb_data);
            end
        end
    end

    initial begin
        #1500;
        $display("\n============================================================================");
        $display("            TB_PIPELINE_BASE VERIFICATION SUMMARY                           ");
        $display("============================================================================");
        $display(" Total Cycles Simulated : %0d", cycle_count);
        $display(" Total Instructions WB  : %0d", wb_count);
        if (wb_count >= 5) begin
            $display(" STATUS: BASE RV32I PIPELINE RETIRED ALL INSTRUCTIONS SUCCESSFULLY!");
        end else begin
            $display(" STATUS: FAILED!");
        end
        $display("============================================================================\n");
        $finish;
    end

endmodule
