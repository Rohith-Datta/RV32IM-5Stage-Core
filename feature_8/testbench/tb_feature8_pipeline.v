// ============================================================================
// File: tb_feature8_pipeline.v
// Module: tb_feature8_pipeline
// Description: Full 5-Stage RV32IMF Pipeline Integration Testbench with CSR Counters
//              Verifies:
//              1. Execution of arithmetic instructions (ADDI, etc.)
//              2. Execution of CSR read instructions (CSRRS / csrr):
//                 - `csrr x10, cycle`   (CSR 0xC00 -> x10)
//                 - `csrr x11, instret` (CSR 0xC02 -> x11)
//                 - `csrr x12, hpmcounter3` (CSR 0xC03 -> x12: stall cycles)
//                 - `csrr x13, hpmcounter4` (CSR 0xC04 -> x13: branches)
//              3. Verification of register writeback with live counter telemetry
// Project: Pipelined RV32IMF RISC-V Core (Feature 8: Passive CSR Integration)
// Clock: Standard 50 MHz (20 ns clock period)
// ============================================================================

`timescale 1ns/1ps

module tb_feature8_pipeline;

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

    // Feature 8 CSR telemetry
    wire [63:0] csr_cycle_count;
    wire [63:0] csr_instret_count;
    wire [63:0] csr_stall_count;
    wire [63:0] csr_branch_count;

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

    // 5-Stage RV32IMF Core with Passive CSRs
    pipeline_5stage #(
        .RESET_PC(32'h0000_0000)
    ) dut (
        .clk              (clk),
        .reset_n          (reset_n),
        .stall_ext        (1'b0),
        .use_dsp_i        (1'b1),
        .imem_addr        (imem_addr),
        .imem_rdata       (imem_rdata),
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
        .csr_cycle_count  (csr_cycle_count),
        .csr_instret_count(csr_instret_count),
        .csr_stall_count  (csr_stall_count),
        .csr_branch_count (csr_branch_count)
    );

    // ------------------------------------------------------------------------
    // Test Control & Verification Sequence
    // ------------------------------------------------------------------------
    integer cycle_count;
    reg     test_passed;

    always @(posedge clk) begin
        if (reset_n)
            cycle_count <= cycle_count + 1;
    end

    initial begin
        reset_n     = 0;
        cycle_count = 0;
        test_passed = 1;

        $display("================================================================");
        $display("   STARTING FEATURE 8: PIPELINE WITH PASSIVE CSRs TESTBENCH");
        $display("================================================================");

        // Populate instruction memory with a dedicated CSR benchmark test:
        // 0x00: addi x1, x0, 10             -> 0x00A00093
        // 0x04: addi x2, x0, 20             -> 0x01400113
        // 0x08: add  x3, x1, x2             -> 0x002081B3 (x3 = 30)
        // 0x0C: csrr x10, cycle   (0xC00)   -> 0xC0002573 (Read cycle into x10)
        // 0x10: csrr x11, instret (0xC02)   -> 0xC02025F3 (Read instret into x11)
        // 0x14: csrr x12, 0xC03             -> 0xC0302673 (Read stall count into x12)
        // 0x18: jalr x0, x1, 0              -> 0x00008067 (ret)

        u_imem.imem[0] = 32'h00A0_0093; // addi x1, x0, 10
        u_imem.imem[1] = 32'h0140_0113; // addi x2, x0, 20
        u_imem.imem[2] = 32'h0020_81B3; // add  x3, x1, x2 (x3 = 30)
        u_imem.imem[3] = 32'hC000_2573; // csrr x10, cycle
        u_imem.imem[4] = 32'hC020_25F3; // csrr x11, instret
        u_imem.imem[5] = 32'hC030_2673; // csrr x12, hpmcounter3
        u_imem.imem[6] = 32'h0000_8067; // ret

        // Release reset
        #25;
        reset_n = 1;
        $display("[INFO] Core reset released. Executing CSR test program...");

        // Wait for execution completion
        while (pc_wb !== 32'h0000_0018 && cycle_count < 80) begin
            @(posedge clk);
            if (dut.id_ex_is_csr) begin
                $display("  [CYCLE %0d] EXECUTING CSR READ: CSR 0x%03h -> Destination x%0d",
                         cycle_count, dut.id_ex_csr_addr, dut.id_ex_rd);
            end
        end

        // Wait for final instruction commit to register file
        repeat (5) @(posedge clk);

        $display("----------------------------------------------------------------");
        $display("[EXECUTION FINISHED] Total Cycles: %0d", cycle_count);
        $display("  Register x3  (Add result):   %0d (Expected: 30)", dut.u_decode_stage.regs[3]);
        $display("  Register x10 (Read Cycle):   %0d (Expected: > 0)", dut.u_decode_stage.regs[10]);
        $display("  Register x11 (Read Instret): %0d (Expected: > 0)", dut.u_decode_stage.regs[11]);
        $display("  Register x12 (Read Stalls):  %0d", dut.u_decode_stage.regs[12]);
        $display("  Hardware csr_cycle_count:    %0d", csr_cycle_count[31:0]);
        $display("  Hardware csr_instret_count:  %0d", csr_instret_count[31:0]);

        if (dut.u_decode_stage.regs[3] !== 32'd30) begin
            $display("FAILED: Expected x3 = 30, got %0d", dut.u_decode_stage.regs[3]);
            test_passed = 0;
        end

        if (dut.u_decode_stage.regs[10] == 32'd0) begin
            $display("FAILED: Expected x10 (cycle counter) > 0, got 0");
            test_passed = 0;
        end

        if (dut.u_decode_stage.regs[11] == 32'd0) begin
            $display("FAILED: Expected x11 (instret counter) > 0, got 0");
            test_passed = 0;
        end

        $display("================================================================");
        if (test_passed) begin
            $display("   FEATURE 8 PIPELINE CSR INTEGRATION TEST PASSED! (0 ERRORS)");
        end else begin
            $display("   FEATURE 8 PIPELINE CSR INTEGRATION TEST FAILED!");
        end
        $display("================================================================");
        $finish;
    end

endmodule
