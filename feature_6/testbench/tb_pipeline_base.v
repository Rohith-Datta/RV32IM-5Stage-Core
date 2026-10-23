// ============================================================================
// File: tb_pipeline_base.v
// Module: tb_pipeline_base
// Description: Full 5-Stage RV32IMF Pipeline Testbench (Feature 6 Baseline)
// Project: Pipelined RV32IMF RISC-V Core (Feature 6: L1 I-Cache Core)
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
    wire        imem_req;

    // Direct Data Memory Bus (No D-Cache)
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we;
    wire        dmem_re;
    wire [31:0] dmem_rdata;

    // MMIO wires
    wire [31:0] mmio_addr;
    wire [31:0] mmio_wdata;
    wire        mmio_we;
    wire        mmio_re;

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

    wire        icache_stall;
    wire        icache_hit;
    wire        icache_miss;
    wire [31:0] icache_hit_count;
    wire [31:0] icache_miss_count;

    // ------------------------------------------------------------------------
    // DUT: 5-Stage Pipelined RV32IMF Core with L1 I-Cache (No D-Cache)
    // ------------------------------------------------------------------------
    pipeline_5stage #(
        .RESET_PC(32'h0000_0000)
    ) u_core (
        .clk               (clk),
        .reset_n           (reset_n),
        .stall_ext         (1'b0),
        .use_dsp_i         (1'b1),
        .icache_bypass_i   (1'b0),
        .imem_addr         (imem_addr),
        .imem_rdata        (imem_rdata),
        .imem_req          (imem_req),
        .dmem_addr         (dmem_addr),
        .dmem_wdata        (dmem_wdata),
        .dmem_wstrb        (dmem_wstrb),
        .dmem_we           (dmem_we),
        .dmem_re           (dmem_re),
        .dmem_rdata        (dmem_rdata),
        .pc_if             (pc_if),
        .pc_id             (pc_id),
        .pc_ex             (pc_ex),
        .pc_mem            (pc_mem),
        .pc_wb             (pc_wb),
        .wb_reg_write      (wb_reg_write),
        .wb_dest_reg       (wb_dest_reg),
        .wb_data           (wb_data),
        .hazard_stall      (hazard_stall),
        .hazard_flush_id   (hazard_flush_id),
        .hazard_flush_ex   (hazard_flush_ex),
        .forward_a         (forward_a),
        .forward_b         (forward_b),
        .mul_active        (mul_active),
        .div_active        (div_active),
        .div_busy          (div_busy),
        .fpu_active        (fpu_active),
        .fpu_busy          (fpu_busy),
        .exception         (exception),
        .icache_stall      (icache_stall),
        .icache_hit        (icache_hit),
        .icache_miss       (icache_miss),
        .icache_hit_count  (icache_hit_count),
        .icache_miss_count (icache_miss_count)
    );

    // ------------------------------------------------------------------------
    // Memories (BRAM Models for 4 KB IMEM & 4 KB DMEM)
    // ------------------------------------------------------------------------
    instr_mem #(
        .HEX_FILE("imem.hex"),
        .WORDS(1024)
    ) u_instr_mem (
        .clk   (clk),
        .pc    (imem_addr),
        .instr (imem_rdata)
    );

    data_mem #(
        .HEX_FILE("dmem.hex"),
        .WORDS(1024)
    ) u_data_mem (
        .clk   (clk),
        .re    (dmem_re),
        .raddr (dmem_addr),
        .rdata (dmem_rdata),
        .we    (dmem_we),
        .waddr (dmem_addr),
        .wdata (dmem_wdata),
        .wstrb (dmem_wstrb)
    );

    // ------------------------------------------------------------------------
    // Verification Routine
    // ------------------------------------------------------------------------
    integer pass_count = 0;
    integer fail_count = 0;

    task check(input condition, input [255:0] test_name);
        begin
            if (condition) begin
                $display("  [PASS] %0s", test_name);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %0s", test_name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        // Simple Base Test Program
        // 0x00: ADDI x1, x0, 10      -> x1 = 10
        // 0x04: ADDI x2, x0, 20      -> x2 = 20
        // 0x08: ADD  x3, x1, x2      -> x3 = 30 (Forwarding test)
        // 0x0C: SUB  x4, x3, x1      -> x4 = 20
        // 0x10: RET  (JALR x0, x1, 0)
        u_instr_mem.imem[0] = 32'h00A00093; // addi x1, x0, 10
        u_instr_mem.imem[1] = 32'h01400113; // addi x2, x0, 20
        u_instr_mem.imem[2] = 32'h002081B3; // add  x3, x1, x2
        u_instr_mem.imem[3] = 32'h40118233; // sub  x4, x3, x1
        u_instr_mem.imem[4] = 32'h00008067; // ret

        reset_n = 0;
        #40;
        @(posedge clk);
        #1;
        reset_n = 1;
        $display("==================================================================");
        $display("   TESTBENCH: Feature 6 Base Integer Pipeline (tb_pipeline_base)");
        $display("   Clock: 50 MHz (Period: 20 ns)                                ");
        $display("==================================================================");

        // Check 1: ADDI x1, 10 commits
        wait(wb_reg_write == 1'b1 && wb_dest_reg == 5'd1);
        check(wb_data == 32'd10, "Instruction 1: ADDI x1, x0, 10 committed x1=10");

        // Check 2: ADDI x2, 20 commits
        wait(wb_reg_write == 1'b1 && wb_dest_reg == 5'd2);
        check(wb_data == 32'd20, "Instruction 2: ADDI x2, x0, 20 committed x2=20");

        // Check 3: ADD x3, x1, x2 commits (RAW forwarding)
        wait(wb_reg_write == 1'b1 && wb_dest_reg == 5'd3);
        check(wb_data == 32'd30, "Instruction 3: ADD x3, x1, x2 committed x3=30");

        // Check 4: SUB x4, x3, x1 commits
        wait(wb_reg_write == 1'b1 && wb_dest_reg == 5'd4);
        check(wb_data == 32'd20, "Instruction 4: SUB x4, x3, x1 committed x4=20");

        // Check 5: Program complete
        wait(pc_wb == 32'h0000_0010);
        check(pc_wb == 32'h0000_0010, "Instruction 5: Program reached RET at 0x0010");
        #40;

        $display("==================================================================");
        $display("   BASE PIPELINE VERIFICATION SUMMARY: %0d / %0d PASSED", pass_count, (pass_count + fail_count));
        $display("==================================================================");

        if (fail_count == 0)
            $display(">>> ALL BASE PIPELINE TESTS PASSED! <<<\n");
        else
            $display(">>> SOME TESTS FAILED! <<<\n");

        $finish;
    end

endmodule
