// ============================================================================
// File: tb_feature6_c_test.v
// Module: tb_feature6_c_test
// Description: Standalone Simulation Testbench to verify bare-metal C program
//              execution on Feature 6 (L1 I-Cache RV32IMF Pipeline).
// ============================================================================

`timescale 1ns/1ps

module tb_feature6_c_test;

    reg clk;
    reg reset_n;

    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;
    wire        imem_req;

    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we;
    wire        dmem_re;
    wire [31:0] dmem_rdata;

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

    wire        icache_stall;
    wire        icache_hit;
    wire        icache_miss;
    wire [31:0] icache_hit_count;
    wire [31:0] icache_miss_count;

    // 50 MHz Clock (20 ns period)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // Instruction Memory
    instr_mem #(
        .HEX_FILE ("imem.hex"),
        .WORDS    (1024)
    ) u_backing_imem (
        .clk   (clk),
        .pc    (imem_addr),
        .instr (imem_rdata)
    );

    // Data Memory
    data_mem #(
        .HEX_FILE ("dmem.hex"),
        .WORDS    (1024)
    ) u_backing_dmem (
        .clk   (clk),
        .re    (dmem_re),
        .raddr (dmem_addr),
        .rdata (dmem_rdata),
        .we    (dmem_we),
        .waddr (dmem_addr),
        .wdata (dmem_wdata),
        .wstrb (dmem_wstrb)
    );

    // Core
    pipeline_5stage #(
        .RESET_PC(32'h0000_0000)
    ) dut (
        .clk              (clk),
        .reset_n          (reset_n),
        .stall_ext        (1'b0),
        .use_dsp_i        (1'b1),
        .icache_bypass_i  (1'b0),
        .imem_addr        (imem_addr),
        .imem_rdata       (imem_rdata),
        .imem_req         (imem_req),
        .dmem_addr        (dmem_addr),
        .dmem_wdata       (dmem_wdata),
        .dmem_wstrb       (dmem_wstrb),
        .dmem_we          (dmem_we),
        .dmem_re          (dmem_re),
        .dmem_rdata       (dmem_rdata),
        .pc_if            (pc_if),
        .pc_id            (pc_id),
        .pc_ex            (pc_ex),
        .pc_mem           (pc_mem),
        .pc_wb            (pc_wb),
        .wb_reg_write     (wb_reg_write),
        .wb_dest_reg      (wb_dest_reg),
        .wb_data          (wb_data),
        .hazard_stall     (hazard_stall),
        .hazard_flush_id  (hazard_flush_id),
        .hazard_flush_ex  (hazard_flush_ex),
        .forward_a        (forward_a),
        .forward_b        (forward_b),
        .mul_active       (mul_active),
        .div_active       (div_active),
        .div_busy         (div_busy),
        .fpu_active       (fpu_active),
        .fpu_busy         (fpu_busy),
        .exception        (exception),
        .icache_stall     (icache_stall),
        .icache_hit       (icache_hit),
        .icache_miss      (icache_miss),
        .icache_hit_count (icache_hit_count),
        .icache_miss_count(icache_miss_count)
    );

    integer cycle = 0;
    integer insts_retired = 0;
    reg [31:0] last_a0 = 32'h0;
    reg saw_ret = 0;
    integer post_ret_cycles = 0;

    always @(posedge clk) begin
        if (reset_n) begin
            cycle <= cycle + 1;

            if (wb_reg_write && wb_dest_reg != 5'd0) begin
                insts_retired <= insts_retired + 1;
                if (wb_dest_reg == 5'd10) begin
                    last_a0 <= wb_data;
                end
                $display("[CYC %4d] WB Commit: PC=0x%08h | Reg x%2d <= 0x%08h (%0d)",
                         cycle, pc_wb, wb_dest_reg, wb_data, $signed(wb_data));
            end else if (pc_wb != 32'h0 && !hazard_stall) begin
                // Could be a branch or store instruction committing
            end

            // Check if instruction at pc_ex or pc_wb is ret (0x00008067)
            if (dut.if_id_inst == 32'h00008067 && !saw_ret) begin
                $display("[CYC %4d] RET detected in IF/ID!", cycle);
                saw_ret <= 1;
            end

            if (saw_ret) begin
                post_ret_cycles <= post_ret_cycles + 1;
                if (post_ret_cycles >= 6) begin
                    $display("\n============================================================");
                    $display("   BARE-METAL C TEST COMPLETE SUMMARY");
                    $display("============================================================");
                    $display("Total Clock Cycles : %0d", cycle);
                    $display("Instructions Retired: %0d", insts_retired);
                    $display("I-Cache Hits       : %0d", icache_hit_count);
                    $display("I-Cache Misses     : %0d", icache_miss_count);
                    $display("Final Return Value : 0x%08h (%0d)", last_a0, $signed(last_a0));
                    $display("============================================================\n");
                    $finish;
                end
            end

            if (cycle >= 200) begin
                $display("[TIMEOUT] Reached 200 cycles!");
                $finish;
            end
        end
    end

    initial begin
        reset_n = 0;
        #40;
        @(posedge clk);
        #1;
        reset_n = 1;
        $display("[TB] Reset released, starting execution...");
    end

endmodule
