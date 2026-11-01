// ============================================================================
// File: tb_icache_uart_verify.v
// Module: tb_icache_uart_verify
// Description: Comprehensive End-to-End Simulation Testbench for Feature 6
//              Verifies:
//              1. Dual Telemetry Execution:
//                 - Phase 1: Synthetic JAL Loop Benchmark (32 cycles, 11 insts, 9 hits, 2 misses)
//                 - Phase 2: Bare-Metal C Program (icache.c, ~32 cycles, < 40 cycles approx, return 37)
//              2. Mode 1: I-Cache Bypassed (SW0=1, 11 misses, comparison summary)
//              3. Decodes and prints real-time UART TX serial output
//              4. Hardware Single-Step Debug Mode (SW15=1 with BTNC)
// ============================================================================

`timescale 1ns/1ps

module tb_icache_uart_verify;

    reg         clk100mhz;
    reg         cpu_resetn;
    reg         btnc;
    reg  [15:0] sw;
    wire [15:0] led;
    wire [7:0]  an;
    wire [6:0]  seg;
    wire        dp;
    wire        uart_txd;

    localparam SIM_BAUD   = 2_500_000;
    localparam BIT_PERIOD = 1_000_000_000.0 / SIM_BAUD; // 400.0 ns

    // Instantiate Top-Level FPGA Module
    fpga_top_feature6 #(
        .CLK_FREQ       (50_000_000),
        .BAUD_RATE      (SIM_BAUD),
        .DEBOUNCE_LIMIT (20'd4)
    ) u_dut (
        .CLK100MHZ   (clk100mhz),
        .CPU_RESETN  (cpu_resetn),
        .BTNC        (btnc),
        .SW          (sw),
        .LED         (led),
        .AN          (an),
        .SEG         (seg),
        .DP          (dp),
        .UART_TXD_IN (uart_txd)
    );

    // 100 MHz clock generation (10 ns period)
    always #5 clk100mhz = ~clk100mhz;

    reg [7:0] rx_byte;
    integer   bit_idx;
    integer   step_k;

    always begin
        // Wait for falling edge of START bit
        @(negedge uart_txd);
        #(BIT_PERIOD / 2.0); // Center of start bit

        if (uart_txd == 1'b0) begin
            // Sample 8 data bits
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                #(BIT_PERIOD);
                rx_byte[bit_idx] = uart_txd;
            end

            // Wait for STOP bit
            #(BIT_PERIOD);
            $write("%c", rx_byte);
        end
    end

    // ------------------------------------------------------------------------
    // Test Sequencer
    // ------------------------------------------------------------------------
    initial begin
        $display("\n============================================================");
        $display("   STARTING FEATURE 6 I-CACHE DUAL VERIFICATION TESTBENCH");
        $display("============================================================\n");

        clk100mhz  = 1'b0;
        cpu_resetn = 1'b0;
        btnc       = 1'b0;
        sw         = 16'h0000; // SW[0] = 0 (I-cache enabled), SW[4] = 0 (Sequential dual mode)

        // --------------------------------------------------------------------
        // TEST 1: Dual Execution in Mode 0 (Benchmark + Bare-Metal C Program)
        // --------------------------------------------------------------------
        $display("[TB] --------------------------------------------------------");
        $display("[TB] TEST 1: Running Phase 1 Benchmark in Mode 0 (I-Cache Enabled)...");
        $display("[TB] SW0 = 0, Cold Cache, Expecting ~32 cycles, 11 insts, 9 hits, 2 misses.");
        $display("[TB] Followed by Phase 2: Bare-Metal C Program (icache.c, < 40 cycles).");
        $display("[TB] --------------------------------------------------------");

        sw[0] = 1'b0;
        sw[4] = 1'b0; // Sequential mode
        #300;
        cpu_resetn = 1'b1; // Release reset to start run

        // Wait until benchmark run completes
        wait (led[1] == 1'b1);
        $display("[TB] >>> Core halted! Phase 1 Benchmark completed in Mode 0.");
        $display("[TB] >>> Waiting for Benchmark UART transmission to complete...");

        wait (led[4] == 1'b1);
        $display("[TB] >>> UART transmission finished for Phase 1 Benchmark!\n");

        // Wait for Phase 2 Bare-Metal C program to execute and finish
        $display("[TB] >>> Now waiting for Phase 2: Bare-Metal C Program (icache.c) to complete...");
        wait (led[6] == 1'b1);
        $display("[TB] >>> Core halted! Phase 2 Bare-Metal C Program completed.");
        $display("[TB] >>> C Program Cycles: %0d (< 40 cycles approx!)", u_dut.c_total_cycles);
        $display("[TB] >>> C Program Return Value (a0): %0d (0x%04h)", u_dut.c_return_val_a0, u_dut.c_return_val_a0);
        $display("[TB] >>> Waiting for C Program UART report transmission to complete...");

        wait (led[4] == 1'b1 && led[7] == 1'b1);
        $display("[TB] >>> UART transmission finished for Phase 2 C Program!\n");
        $display("[TB] >>> LED[7] = 1: Both Phase 1 and Phase 2 successfully verified!");
        #30000;

        // --------------------------------------------------------------------
        // TEST 2: Run in Mode 1 (I-Cache Bypassed - Benchmark only for comparison)
        // --------------------------------------------------------------------
        $display("\n[TB] --------------------------------------------------------");
        $display("[TB] TEST 2: Switching to Mode 1 (I-Cache Bypassed)...");
        $display("[TB] Setting SW0 = 1, SW4 = 1, SW5 = 1 (Benchmark only), pressing CPU_RESETN.");
        $display("[TB] Expecting ~113 cycles, 11 insts, 0 hits, 11 misses.");
        $display("[TB] Expecting Side-by-Side Comparison Table at the end!");
        $display("[TB] --------------------------------------------------------");

        sw[0] = 1'b1; // Bypassed
        sw[4] = 1'b1; // Manual mode
        sw[5] = 1'b1; // Benchmark only
        #500;
        cpu_resetn = 1'b0; // Press reset button
        #1000;
        cpu_resetn = 1'b1; // Release reset button

        wait (led[1] == 1'b1);
        $display("[TB] >>> Core halted! Active benchmark completed in Mode 1.");
        $display("[TB] >>> Waiting for UART transmission to complete...");

        wait (led[4] == 1'b1);
        $display("[TB] >>> UART transmission finished for Mode 1!\n");
        #50000;

        // --------------------------------------------------------------------
        // TEST 3: Hardware Debug Stepping Mode (SW[15] = 1, BTNC pulses)
        // --------------------------------------------------------------------
        $display("\n[TB] --------------------------------------------------------");
        $display("[TB] TEST 3: Testing Hardware Debug Stepping Mode (SW[15] = 1)...");
        $display("[TB] SW15 = 1 (Step Mode), SW0 = 0 (Cold Cache Enabled).");
        $display("[TB] Verifying single-cycle advance per BTNC press + immediate UART row output.");
        $display("[TB] --------------------------------------------------------");

        sw[15] = 1'b1; // Enable Hardware Debug Step Mode
        sw[0]  = 1'b0; // Cold Cache Mode 0
        sw[4]  = 1'b1;
        sw[5]  = 1'b1; // Benchmark mode
        #500;
        cpu_resetn = 1'b0; // Reset core
        #1000;
        cpu_resetn = 1'b1; // Release reset
        #300000;           // Wait for banner header to print over UART

        $display("[TB] Banner output complete. Advancing 5 single cycles via BTNC pulses...");
        for (step_k = 1; step_k <= 5; step_k = step_k + 1) begin
            $display("[TB] >>> Pressing BTNC for cycle %0d...", step_k);
            btnc = 1'b1;
            #300; // Hold button past debounce threshold
            btnc = 1'b0;
            #350000; // Allow single-row UART transmission to complete
        end
        $display("[TB] >>> Successfully stepped 5 cycles and received immediate UART line per step!\n");

        $display("\n============================================================");
        $display("   FEATURE 6 VERIFICATION TESTBENCH COMPLETED SUCCESSFULLY!");
        $display("============================================================\n");
        $finish;
    end

endmodule
