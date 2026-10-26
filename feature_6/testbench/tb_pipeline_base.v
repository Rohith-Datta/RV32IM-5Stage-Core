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

    reg icache_bypass_tb = 1'b0;
    initial begin
        if ($test$plusargs("icache_bypass")) begin
            icache_bypass_tb = 1'b1;
            $display("[TB] I-Cache BYPASS mode selected (+icache_bypass)");
        end else begin
            $display("[TB] I-Cache ENABLED mode selected");
        end
    end

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
        .icache_bypass_i   (icache_bypass_tb),
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

    integer cycle_count = 0;
    integer inst_retired = 0;
    integer stall_cycles = 0;
    integer flush_cycles = 0;
    integer ret_drain_cycles = 0;
    reg [31:0] prev_result = 32'hDEAD_BEEF;

    initial begin
        reset_n = 0;
        #100;
        reset_n = 1;
        $display("==================================================================");
        $display("   TESTBENCH: Feature 6 Base Pipeline with L1 I-Cache (imem.hex)");
        $display("   Clock: 50 MHz (Period: 20 ns)                                ");
        $display("==================================================================");
    end

    always @(posedge clk) begin
        if (reset_n) begin
            cycle_count <= cycle_count + 1;
            if (hazard_stall || icache_stall)
                stall_cycles <= stall_cycles + 1;
            if (hazard_flush_id)
                flush_cycles <= flush_cycles + 1;

            if (wb_reg_write && wb_dest_reg != 5'd0) begin
                inst_retired <= inst_retired + 1;
                if (wb_data !== prev_result) begin
                    if (wb_data < 32'h0000FFFF || wb_data == 32'hFFFFFFFF) begin
                        $display("time: %16d ,result = %10d", $time, $signed(wb_data));
                    end
                    prev_result <= wb_data;
                end
            end

            $display("next_pc = %08x", pc_if);
            $display("[TRACE] CC=%0d | IF_PC=%08h | IF_INST=%08h | ID_PC=%08h | EX_PC=%08h | MEM_PC=%08h | WB_PC=%08h | FWD_A=%0d | FWD_B=%0d | STALL=%0d | FLUSH=%0d | WB_WE=%0d | WB_RD=%0d | WB_DATA=%08h",
                     cycle_count, pc_if, u_core.icache_cpu_rdata, pc_id, pc_ex, pc_mem, pc_wb, forward_a, forward_b, (hazard_stall || icache_stall), hazard_flush_id, wb_reg_write, wb_dest_reg, wb_data);

            // Program Termination condition (ret = 32'h00008067)
            if (u_core.icache_cpu_rdata == 32'h00008067 && !hazard_stall && !icache_stall && cycle_count > 5) begin
                if (ret_drain_cycles == 0)
                    ret_drain_cycles <= cycle_count + 6;
            end

            if (ret_drain_cycles != 0 && cycle_count >= ret_drain_cycles && !hazard_stall && !icache_stall) begin
                $display("All instructions are Fetched");
                $display("next_pc = 00000000");
                $display("\n=================================================================");
                $display("           PROGRAM EXECUTION COMPLETED SUCCESSFULLY!             ");
                $display("=================================================================");
                $display("Total Elapsed Cycles           : %0d", cycle_count);
                $display("Instructions Retired           : %0d", inst_retired);
                $display("Stall Cycles (I-Cache/Hazards) : %0d", stall_cycles);
                $display("Branch Flush Cycles            : %0d", flush_cycles);
                $display("Calculated IPC                 : %0.2f", $itor(inst_retired) / $itor(cycle_count));
                $display("L1 I-Cache Hits                : %0d", icache_hit_count);
                $display("L1 I-Cache Misses              : %0d", icache_miss_count);
                $display("FINAL RETURN VALUE a0 (x10)    = %0d (0x%08h)", $signed(u_core.u_decode_stage.regs[10]), u_core.u_decode_stage.regs[10]);
                $display("FINAL TEMP RESULT  a5 (x15)    = %0d (0x%08h)", $signed(u_core.u_decode_stage.regs[15]), u_core.u_decode_stage.regs[15]);
                $display("=================================================================\n");
                $finish;
            end
        end
    end

    // Watchdog timeout
    initial begin
        #500000;
        $display("\n[WATCHDOG TIMEOUT] Simulation reached limit.");
        $display("Total Cycles: %0d, Instructions Retired: %0d", cycle_count, inst_retired);
        $display("L1 I-Cache Hits: %0d, Misses: %0d", icache_hit_count, icache_miss_count);
        $display("FINAL RETURN VALUE a0 (x10) = %0d (0x%08h)", $signed(u_core.u_decode_stage.regs[10]), u_core.u_decode_stage.regs[10]);
        $finish;
    end

endmodule
