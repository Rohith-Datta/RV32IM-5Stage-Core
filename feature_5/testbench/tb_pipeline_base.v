// ============================================================================
// File: tb_pipeline_base.v
// Module: tb_pipeline_base
// Description: Full 5-Stage RV32IMF Pipeline Testbench (Feature 5 Core with L1 D-Cache)
// Project: Pipelined RV32IMF RISC-V Core (Feature 5: L1 D-Cache Verification)
// Runs: Compiled C Programs (Addition, Sort, Fibonacci, Multiplication, Division, etc.)
// Features: L1 D-Cache Hit/Miss telemetry, UART MMIO output, cycle trace, IPC throughput
// Clock: Standard 50 MHz (Period: 20 ns)
// ============================================================================

`timescale 1ns/1ps

module tb_pipeline_base #(
    parameter RUN_BASE_SANITY = 0 // 0 = Run compiled C/Assembly from imem.hex, 1 = Fixed 5-inst sanity test
);

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

    // Data Memory Bus (to Backing Memory)
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we;
    wire        dmem_req;
    wire [31:0] dmem_rdata;

    // MMIO wires
    wire [31:0] mmio_addr;
    wire [31:0] mmio_wdata;
    wire        mmio_we;
    wire        mmio_re;
    wire        uart_mmio_match = (mmio_addr[31:16] == 16'h8000);

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

    wire        dcache_stall;
    wire        dcache_hit;
    wire        dcache_miss;
    wire [31:0] dcache_hit_count;
    wire [31:0] dcache_miss_count;

    // ------------------------------------------------------------------------
    // DUT: 5-Stage Pipelined RV32IMF Core with L1 D-Cache
    // ------------------------------------------------------------------------
    pipeline_5stage #(
        .RESET_PC(32'h0000_0000)
    ) u_core (
        .clk               (clk),
        .reset_n           (reset_n),
        .stall_ext         (1'b0),
        .use_dsp_i         (1'b1),
        .imem_addr         (imem_addr),
        .imem_rdata        (imem_rdata),
        .dmem_addr         (dmem_addr),
        .dmem_wdata        (dmem_wdata),
        .dmem_wstrb        (dmem_wstrb),
        .dmem_we           (dmem_we),
        .dmem_req          (dmem_req),
        .dmem_rdata        (dmem_rdata),
        .mmio_addr_o       (mmio_addr),
        .mmio_wdata_o      (mmio_wdata),
        .mmio_we_o         (mmio_we),
        .mmio_re_o         (mmio_re),
        .mmio_rdata_i      (32'h0),
        .mmio_match_i      (uart_mmio_match),
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
        .dcache_stall      (dcache_stall),
        .dcache_hit        (dcache_hit),
        .dcache_miss       (dcache_miss),
        .dcache_hit_count  (dcache_hit_count),
        .dcache_miss_count (dcache_miss_count)
    );

    // ------------------------------------------------------------------------
    // Memories (BRAM Models for 4 KB IMEM & 4 KB DMEM)
    // ------------------------------------------------------------------------
    instr_mem #(
        .HEX_FILE("C:/CS2202L/RISCV/feature_5/mem/imem.hex"),
        .WORDS(1024)
    ) u_instr_mem (
        .clk   (clk),
        .pc    (imem_addr),
        .instr (imem_rdata)
    );

    data_mem #(
        .HEX_FILE("C:/CS2202L/RISCV/feature_5/mem/dmem.hex"),
        .WORDS(1024)
    ) u_data_mem (
        .clk   (clk),
        .re    (dmem_req),
        .raddr (dmem_addr),
        .rdata (dmem_rdata),
        .we    (dmem_we),
        .waddr (dmem_addr),
        .wdata (dmem_wdata),
        .wstrb (dmem_wstrb)
    );

    // ------------------------------------------------------------------------
    // UART MMIO Terminal Display Simulation
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (mmio_we && uart_mmio_match && (mmio_addr[3:0] == 4'h0)) begin
            $write("%c", mmio_wdata[7:0]);
            $fflush();
        end
    end

    // ------------------------------------------------------------------------
    // Execution Monitoring & Program Termination Logic
    // ------------------------------------------------------------------------
    integer pass_count = 0;
    integer fail_count = 0;
    integer cycle_count = 0;
    integer inst_retired = 0;
    integer stall_cycles = 0;
    integer flush_cycles = 0;
    integer ret_drain_cycles = 0;

    reg [31:0] prev_result;

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
        prev_result = 32'hffffffff;
        reset_n = 0;
        #100;
        @(posedge clk);
        #1;
        reset_n = 1;

        if (RUN_BASE_SANITY) begin
            $display("==================================================================");
            $display("   TESTBENCH: Feature 5 Base Sanity Test (RUN_BASE_SANITY = 1)   ");
            $display("   Clock: 50 MHz (Period: 20 ns)                                ");
            $display("==================================================================");
            u_instr_mem.imem[0] = 32'h00A00093; // addi x1, x0, 10
            u_instr_mem.imem[1] = 32'h01400113; // addi x2, x0, 20
            u_instr_mem.imem[2] = 32'h002081B3; // add  x3, x1, x2
            u_instr_mem.imem[3] = 32'h40118233; // sub  x4, x3, x1
            u_instr_mem.imem[4] = 32'h00008067; // ret

            wait(wb_reg_write == 1'b1 && wb_dest_reg == 5'd1);
            check(wb_data == 32'd10, "Instruction 1: ADDI x1, x0, 10 committed x1=10");

            wait(wb_reg_write == 1'b1 && wb_dest_reg == 5'd2);
            check(wb_data == 32'd20, "Instruction 2: ADDI x2, x0, 20 committed x2=20");

            wait(wb_reg_write == 1'b1 && wb_dest_reg == 5'd3);
            check(wb_data == 32'd30, "Instruction 3: ADD x3, x1, x2 committed x3=30");

            wait(wb_reg_write == 1'b1 && wb_dest_reg == 5'd4);
            check(wb_data == 32'd20, "Instruction 4: SUB x4, x3, x1 committed x4=20");

            wait(pc_wb == 32'h0000_0010);
            check(pc_wb == 32'h0000_0010, "Instruction 5: Program reached RET at 0x0010");
            #40;

            $display("==================================================================");
            $display("   BASE SANITY VERIFICATION: %0d / %0d PASSED", pass_count, (pass_count + fail_count));
            $display("==================================================================");
            $finish;
        end else begin
            $display("==================================================================");
            $display("   TESTBENCH: Feature 5 Full-System Pipeline (tb_pipeline_base)   ");
            $display("   5-Stage RV32IMF Core with Direct-Mapped L1 D-Cache (50 MHz)   ");
            $display("==================================================================");
        end
    end

    // Cycle Monitor & Logging for Compiled C Program Mode
    always @(posedge clk) begin
        if (reset_n && !RUN_BASE_SANITY) begin
            cycle_count <= cycle_count + 1;

            if (hazard_stall || dcache_stall)
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

            // Trace PC progression
            $display("next_pc = %08x", pc_if);
            $display("[TRACE] CC=%0d | IF_PC=%08h | IF_INST=%08h | ID_PC=%08h | EX_PC=%08h | MEM_PC=%08h | WB_PC=%08h | FWD_A=%0d | FWD_B=%0d | STALL=%0d | FLUSH=%0d | WB_WE=%0d | WB_RD=%0d | WB_DATA=%08h",
                     cycle_count, pc_if, imem_rdata, pc_id, pc_ex, pc_mem, pc_wb, forward_a, forward_b, (hazard_stall || dcache_stall), hazard_flush_id, wb_reg_write, wb_dest_reg, wb_data);

            // Program Termination condition (ret = 32'h00008067)
            if (imem_rdata == 32'h00008067 && !hazard_stall && !dcache_stall && cycle_count > 5) begin
                if (ret_drain_cycles == 0)
                    ret_drain_cycles <= cycle_count + 6;
            end

            if (ret_drain_cycles != 0 && cycle_count >= ret_drain_cycles && !hazard_stall && !dcache_stall) begin
                $display("All instructions are Fetched");
                $display("next_pc = 00000000");
                $display("\n=================================================================");
                $display("           PROGRAM EXECUTION COMPLETED SUCCESSFULLY!             ");
                $display("=================================================================");
                $display("Total Elapsed Cycles           : %0d", cycle_count);
                $display("Instructions Retired           : %0d", inst_retired);
                $display("Stall Cycles (D-Cache/Hazards) : %0d", stall_cycles);
                $display("Branch Flush Cycles            : %0d", flush_cycles);
                $display("Calculated IPC                 : %0.2f", $itor(inst_retired) / $itor(cycle_count));
                $display("L1 D-Cache Hits                : %0d", dcache_hit_count);
                $display("L1 D-Cache Misses              : %0d", dcache_miss_count);
                $display("FINAL RETURN VALUE a0 (x10)    = %0d (0x%08h)", $signed(u_core.u_decode_stage.regs[10]), u_core.u_decode_stage.regs[10]);
                $display("FINAL TEMP RESULT  a5 (x15)    = %0d (0x%08h)", $signed(u_core.u_decode_stage.regs[15]), u_core.u_decode_stage.regs[15]);
                $display("=================================================================\n");
                $finish;
            end
        end
    end

    // Watchdog timeout
    initial begin
        if (!RUN_BASE_SANITY) begin
            #100000;
            $display("\n[WATCHDOG TIMEOUT] Simulation reached 100000 ns limit.");
            $display("Total Cycles: %0d, Instructions Retired: %0d", cycle_count, inst_retired);
            $display("L1 D-Cache Hits: %0d, Misses: %0d", dcache_hit_count, dcache_miss_count);
            $display("FINAL RETURN VALUE a0 (x10) = %0d (0x%08h)", $signed(u_core.u_decode_stage.regs[10]), u_core.u_decode_stage.regs[10]);
            $finish;
        end
    end

endmodule
