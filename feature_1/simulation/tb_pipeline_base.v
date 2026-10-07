// ============================================================================
// File: tb_pipeline_base.v
// Description: Full System Integration Testbench for 5-Stage RV32I Processor
// Project: Pipelined RV32IM RISC-V Core (Feature 1: 5-Stage Upgrade)
// Runs: Compiled RISC-V Program (Fibonacci) via IMEM / DMEM Hierarchy
// Features: Cycle-by-cycle logging, Hazard tracking, IPC throughput measurement
// ============================================================================

`timescale 1ns/1ps

module tb_pipeline_base;

    // ------------------------------------------------------------------------
    // Clock and Reset Generation
    // ------------------------------------------------------------------------
    reg clk;
    reg reset_n;

    // 100 MHz clock (10 ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Active-low reset pulse
    initial begin
        reset_n = 0;
        #100;
        reset_n = 1;
    end

    // ------------------------------------------------------------------------
    // Memory and Processor Interconnects
    // ------------------------------------------------------------------------
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;

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
    wire        exception;

    // ------------------------------------------------------------------------
    // DUT: 5-Stage Pipelined RV32I Core
    // ------------------------------------------------------------------------
    pipeline_5stage #(
        .RESET_PC(32'h0000_0000)
    ) DUT (
        .clk            (clk),
        .reset_n        (reset_n),
        .stall_ext      (1'b0),
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
        .exception      (exception)
    );

    // ------------------------------------------------------------------------
    // Instruction Memory (IMEM)
    // ------------------------------------------------------------------------
    instr_mem #(
        .HEX_FILE("C:/CS2202L/RISCV/feature_1/mem/imem.hex"),
        .WORDS(1024)
    ) IMEM (
        .clk  (clk),
        .pc   (imem_addr),
        .instr(imem_rdata)
    );

    // ------------------------------------------------------------------------
    // Data Memory (DMEM)
    // ------------------------------------------------------------------------
    data_mem #(
        .HEX_FILE("C:/CS2202L/RISCV/feature_1/mem/dmem.hex"),
        .WORDS(1024)
    ) DMEM (
        .clk  (clk),
        .re   (dmem_re),
        .raddr(dmem_addr),
        .rdata(dmem_rdata),
        .we   (dmem_we),
        .waddr(dmem_addr),
        .wdata(dmem_wdata),
        .wstrb(dmem_wstrb)
    );

    // ------------------------------------------------------------------------
    // Execution Statistics & Logging
    // ------------------------------------------------------------------------
    integer cycle_count = 0;
    integer inst_retired = 0;
    integer stall_cycles = 0;
    integer flush_cycles = 0;

    initial begin
        $dumpfile("pipeline_5stage.vcd");
        $dumpvars(0, tb_pipeline_base);
    end

    // Cycle Monitor
    always @(posedge clk) begin
        if (reset_n) begin
            cycle_count <= cycle_count + 1;

            if (hazard_stall)
                stall_cycles <= stall_cycles + 1;
            if (hazard_flush_id)
                flush_cycles <= flush_cycles + 1;

            if (wb_reg_write && wb_dest_reg != 5'd0) begin
                inst_retired <= inst_retired + 1;
                $display("[CYCLE %4d | TIME %0t ps] WB: x%02d <= 0x%08h (%0d) | PC_WB=%08h",
                         cycle_count, $time, wb_dest_reg, wb_data, $signed(wb_data), pc_wb);
            end

            // Trace PC progression
            $display("[CYCLE %4d] PC_IF=%08h | PC_ID=%08h | PC_EX=%08h | FwdA=%b FwdB=%b | Stall=%b Flush=%b",
                     cycle_count, pc_if, pc_id, pc_ex, forward_a, forward_b, hazard_stall, hazard_flush_id);

            // Program Termination condition
            if (pc_if == 32'h0000_0074 || pc_if == 32'h0000_0044 && cycle_count > 100) begin
                $display("\n=================================================================");
                $display("           PROGRAM EXECUTION COMPLETED SUCCESSFULLY!             ");
                $display("=================================================================");
                $display("Total Elapsed Cycles : %0d", cycle_count);
                $display("Instructions Retired : %0d", inst_retired);
                $display("Load-Use Stalls      : %0d", stall_cycles);
                $display("Branch Flush Cycles  : %0d", flush_cycles);
                $display("Calculated IPC       : %0.2f", $itor(inst_retired) / $itor(cycle_count));
                $display("Final Return Value a0 (x10) = %0d", DUT.u_decode_stage.regs[10]);
                $display("Final Fib Temp Value a5 (x15) = %0d", DUT.u_decode_stage.regs[15]);
                $display("=================================================================\n");
                $finish;
            end
        end
    end

    // Timeout watchdog
    initial begin
        #5000;
        $display("\n[WATCHDOG TIMEOUT] Simulation reached 5000 ns limit.");
        $display("Total Cycles: %0d, Instructions Retired: %0d", cycle_count, inst_retired);
        $finish;
    end

endmodule
