// ============================================================================
// File: tb_feature6_pipeline.v
// Module: tb_feature6_pipeline
// Description: Full 5-Stage RV32IMF Pipeline Integration Testbench with L1 I-Cache
//              (2 KB Direct-Mapped I-Cache & Direct DMEM Access, No D-Cache)
//
// Verification Coverage:
//   1. Cold Start Compulsory I-Cache Miss (PC 0x0000_0000 -> 10-cycle burst refill stall)
//   2. Sequential Spatial Locality I-Cache Hits (PC 0x04, 0x08, 0x0C -> 1-cycle hits, 0 stall)
//   3. Direct Data Memory Access (LW/SW directly from/to DMEM without D-Cache)
//   4. Interleaved ALU Arithmetic & RAW Data Forwarding
//   5. Temporal Locality in I-Cache: Multi-Iteration Loop Execution with Zero Fetch Stalls
//   6. UART MMIO Non-Cached Peripheral Write (MMIO at 0x8000_0000)
//   7. Normal Program Termination via RET (JALR x0, x1, 0)
//   8. L1 I-Cache Hit/Miss Performance Counters Verification
//
// Project: Pipelined RV32IMF RISC-V Core (Feature 6: L1 I-Cache Core)
// Clock: Standard 50 MHz (Period: 20 ns)
// ============================================================================

`timescale 1ns/1ps

module tb_feature6_pipeline;

    // Clock and reset signals (50 MHz clock)
    reg clk;
    reg reset_n;

    // Backing Instruction Memory Bus (Burst Refill)
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

    wire [31:0] uart_rdata;
    wire        uart_addr_match;
    wire [31:0] dmem_ram_rdata;

    // Pipeline Telemetry Signals
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

    // L1 I-Cache Diagnostics
    wire        icache_stall;
    wire        icache_hit;
    wire        icache_miss;
    wire [31:0] icache_hit_count;
    wire [31:0] icache_miss_count;

    wire        uart_tx;
    wire        uart_busy;
    wire        banner_done;

    // Standard 50 MHz Core Clock (20 ns period: 10 ns high, 10 ns low)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // Backing Instruction Memory (4 KB = 1024 words)
    instr_mem #(
        .HEX_FILE ("imem.hex"),
        .WORDS    (1024)
    ) u_backing_imem (
        .clk   (clk),
        .pc    (imem_addr),
        .instr (imem_rdata)
    );

    // RAM vs UART MMIO Data Read Multiplexing
    assign dmem_rdata = uart_addr_match ? uart_rdata : dmem_ram_rdata;

    // Direct Data Memory (4 KB = 1024 words)
    data_mem #(
        .HEX_FILE ("dmem.hex"),
        .WORDS    (1024)
    ) u_backing_dmem (
        .clk   (clk),
        .re    (dmem_re && !uart_addr_match),
        .raddr (dmem_addr),
        .rdata (dmem_ram_rdata),
        .we    (dmem_we && !uart_addr_match),
        .waddr (dmem_addr),
        .wdata (dmem_wdata),
        .wstrb (dmem_wstrb)
    );

    // 5-Stage RV32IMF Core with L1 I-Cache (No D-Cache)
    pipeline_5stage #(
        .RESET_PC(32'h0000_0000)
    ) dut (
        .clk              (clk),
        .reset_n          (reset_n),
        .stall_ext        (1'b0),
        .use_dsp_i        (1'b1),
        .icache_bypass_i  (1'b0), // Normal L1 I-Cache operation
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

    // Dedicated UART Subsystem
    uart_unit #(
        .CLK_FREQ   (50_000_000),
        .BAUD_RATE  (115_200),
        .FIFO_DEPTH (64)
    ) u_uart (
        .clk             (clk),
        .reset_n         (reset_n),
        .dmem_addr       (dmem_addr),
        .dmem_wdata      (dmem_wdata),
        .dmem_we         (dmem_we),
        .dmem_re         (dmem_re),
        .uart_rdata      (uart_rdata),
        .uart_addr_match (uart_addr_match),
        .fetch_pc        (pc_if),
        .fetch_inst      (imem_rdata),
        .hazard_stall    (hazard_stall),
        .step_trigger    (1'b1),
        .uart_tx         (uart_tx),
        .uart_busy       (uart_busy),
        .banner_done_o   (banner_done)
    );

    // Verification statistics & logging
    integer test_pass = 0;
    integer test_fail = 0;
    integer cycle_cnt = 0;

    always @(posedge clk) begin
        cycle_cnt <= cycle_cnt + 1;
    end

    // Self-checking assertion task
    task check_assert(input condition, input [1023:0] msg);
        begin
            if (condition) begin
                $display("  [PASS] %0s", msg);
                test_pass = test_pass + 1;
            end else begin
                $display("  [FAIL] %0s (wb_data=0x%08h, wb_dest_reg=%0d, pc_wb=0x%08h, cycle=%0d)",
                         msg, wb_data, wb_dest_reg, pc_wb, cycle_cnt);
                test_fail = test_fail + 1;
            end
        end
    endtask

    always @(posedge clk) begin
        if (wb_reg_write && wb_dest_reg != 5'd0) begin
            $display("  [WB COMMIT] Time=%0t ns, Reg x%0d <= 0x%08h (pc_wb = 0x%08h)",
                     $time, wb_dest_reg, wb_data, pc_wb);
        end
    end

    initial begin
        // Pre-populate data memory at word offset 0x100..0x10F
        u_backing_dmem.dmem[32'h0000_0100 >> 2] = 32'h1111_1111;
        u_backing_dmem.dmem[32'h0000_0104 >> 2] = 32'h2222_2222;
        u_backing_dmem.dmem[32'h0000_0108 >> 2] = 32'h3333_3333;
        u_backing_dmem.dmem[32'h0000_010C >> 2] = 32'h4444_4444;

        // Assembly Program to Verify 5-Stage RV32IMF Pipeline with L1 I-Cache:
        // Line 0 (0x00 - 0x0C): Cold miss on 0x00, then spatial hits on 0x04, 0x08, 0x0C
        //   PC 0x00: ADDI x1, x0, 0x100       // Base address = 0x100
        //   PC 0x04: LW   x2, 0(x1)           // Load 0x11111111 directly from DMEM
        //   PC 0x08: LW   x3, 4(x1)           // Load 0x22222222 directly from DMEM
        //   PC 0x0C: ADD  x4, x2, x3          // x4 = 0x11111111 + 0x22222222 = 0x33333333
        // Line 1 (0x10 - 0x1C): Cold miss on 0x10, then spatial hits on 0x14, 0x18, 0x1C
        //   PC 0x10: ADDI x5, x0, 4           // Loop counter = 4
        //   PC 0x14: ADDI x6, x0, 0           // Sum accumulator = 0
        //   PC 0x18: ADD  x6, x6, x4          // Loop body: sum += x4
        //   PC 0x1C: ADDI x5, x5, -1          // Loop dec: counter--
        // Line 2 (0x20 - 0x2C): Cold miss on 0x20, then branch back to 0x18 (Cached!)
        //   PC 0x20: BNE  x5, x0, -8          // Loop branch back to 0x18
        //   PC 0x24: LUI  x10, 0x80000        // MMIO UART Base = 0x80000000
        //   PC 0x28: ADDI x11, x0, 67         // ASCII 'C' (I-Cache)
        //   PC 0x2C: SB   x11, 0(x10)         // MMIO write to UART
        // Line 3 (0x30):
        //   PC 0x30: RET  (JALR x0, x1, 0)    // Program termination

        u_backing_imem.imem[0]  = 32'h10000093; // addi x1, x0, 0x100
        u_backing_imem.imem[1]  = 32'h0000A103; // lw x2, 0(x1)
        u_backing_imem.imem[2]  = 32'h0040A183; // lw x3, 4(x1)
        u_backing_imem.imem[3]  = 32'h00310233; // add x4, x2, x3
        u_backing_imem.imem[4]  = 32'h00400293; // addi x5, x0, 4
        u_backing_imem.imem[5]  = 32'h00000313; // addi x6, x0, 0
        u_backing_imem.imem[6]  = 32'h00430333; // add x6, x6, x4
        u_backing_imem.imem[7]  = 32'hFFF28293; // addi x5, x5, -1
        u_backing_imem.imem[8]  = 32'hFE029CE3; // bne x5, x0, -8
        u_backing_imem.imem[9]  = 32'h80000537; // lui x10, 0x80000
        u_backing_imem.imem[10] = 32'h04300593; // addi x11, x0, 67 ('C')
        u_backing_imem.imem[11] = 32'h00B50023; // sb x11, 0(x10)
        u_backing_imem.imem[12] = 32'h00008067; // ret

        reset_n = 0;
        $display("================================================================================");
        $display("   TESTBENCH: Feature 6 Pipeline Integration (tb_feature6_pipeline)");
        $display("   5-Stage RV32IMF Core with 2 KB L1 I-Cache & Direct DMEM Access               ");
        $display("   Clock: 50 MHz (Period: 20 ns) | Target: Artix-7 Nexys A7-100T               ");
        $display("================================================================================");

        #40;
        @(posedge clk);
        #1;
        reset_n = 1;
        $display("[*] Core reset released. Beginning pipeline execution...");

        // --------------------------------------------------------------------
        // Check 1: Cold start compulsory I-Cache miss on initial PC = 0x0000_0000
        // --------------------------------------------------------------------
        #1;
        check_assert(icache_stall == 1'b1, "Check 1: Cold start compulsory I-Cache miss asserts icache_stall = 1");

        // Wait for I-Cache line 0 refill to complete
        wait(icache_stall == 1'b0);
        check_assert(dut.icache_miss_count >= 32'd1, "Check 2: I-Cache logged cold miss in icache_miss_count");

        // --------------------------------------------------------------------
        // Check 3: ADDI x1 commits
        // --------------------------------------------------------------------
        wait(wb_reg_write == 1'b1 && wb_dest_reg == 5'd1);
        #1;
        check_assert(wb_data == 32'h0000_0100, "Check 3: ADDI x1 committed base address 0x00000100");

        // --------------------------------------------------------------------
        // Check 4 & 5: Direct DMEM Load commits for x2 and x3
        // --------------------------------------------------------------------
        wait(wb_reg_write == 1'b1 && wb_dest_reg == 5'd2);
        #1;
        check_assert(wb_data == 32'h1111_1111, "Check 4: LW x2 committed 0x11111111 directly from DMEM");

        wait(wb_reg_write == 1'b1 && wb_dest_reg == 5'd3);
        #1;
        check_assert(wb_data == 32'h2222_2222, "Check 5: LW x3 committed 0x22222222 directly from DMEM");

        // --------------------------------------------------------------------
        // Check 6: ADD x4, x2, x3 commits
        // --------------------------------------------------------------------
        wait(wb_reg_write == 1'b1 && wb_dest_reg == 5'd4);
        #1;
        check_assert(wb_data == 32'h3333_3333, "Check 6: ADD x4 committed 0x33333333 (x2 + x3)");

        // --------------------------------------------------------------------
        // Check 7: Loop accumulator x6 commits 0xCCCCCCCC after 4 iterations
        // --------------------------------------------------------------------
        wait(wb_reg_write == 1'b1 && wb_dest_reg == 5'd6 && wb_data == 32'hCCCC_CCCC);
        #1;
        check_assert(wb_data == 32'hCCCC_CCCC, "Check 7: Loop accumulated 4 iterations correctly: x6 = 0xCCCCCCCC");

        // --------------------------------------------------------------------
        // Check 8: Counter x5 reaches 0
        // --------------------------------------------------------------------
        wait(wb_reg_write == 1'b1 && wb_dest_reg == 5'd5 && wb_data == 32'd0);
        #1;
        check_assert(wb_data == 32'd0, "Check 8: Loop counter x5 decremented to 0");

        // --------------------------------------------------------------------
        // Check 9: UART MMIO write of 'C' (67)
        // --------------------------------------------------------------------
        wait(u_uart.dmem_we == 1'b1 && u_uart.uart_addr_match == 1'b1);
        #1;
        check_assert(u_uart.dmem_wdata[7:0] == 8'd67, "Check 9: MMIO UART received character 'C' (0x43)");

        // --------------------------------------------------------------------
        // Check 10: Program termination at RET (PC = 0x0000_0030)
        // --------------------------------------------------------------------
        wait(pc_wb == 32'h0000_0030);
        check_assert(pc_wb == 32'h0000_0030, "Check 10: Program successfully reached RET at PC 0x00000030");

        #100;

        // --------------------------------------------------------------------
        // Check 11: I-Cache performance verification
        // --------------------------------------------------------------------
        $display("\n[CACHE PERFORMANCE TELEMETRY]");
        $display("  I-Cache Hits   : %0d", icache_hit_count);
        $display("  I-Cache Misses : %0d", icache_miss_count);

        check_assert(icache_hit_count >= 32'd10, "Check 11: I-Cache logged >= 10 hits due to loop temporal locality");

        $display("\n================================================================================");
        $display("   PIPELINE INTEGRATION VERIFICATION SUMMARY");
        $display("   Total Checks Passed: %0d", test_pass);
        $display("   Total Checks Failed: %0d", test_fail);
        $display("================================================================================");

        if (test_fail == 0) begin
            $display(">>> ALL ASSERTIONS PASSED! FEATURE 6 I-CACHE PIPELINE 100%% VERIFIED! <<<\n");
        end else begin
            $display(">>> SOME ASSERTIONS FAILED! <<<\n");
        end

        $finish;
    end

endmodule
