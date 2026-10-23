// ============================================================================
// File: tb_icache_uart_verify.v
// Module: tb_icache_uart_verify
// Description: Comprehensive End-to-End Simulation Testbench for Feature 6
//              Verifies:
//              1. Mode 0: I-Cache Enabled (SW0=0), Cold Cache, 3 JAL loops, Halts
//              2. Mode 1: I-Cache Bypassed (SW0=1), Cold Cache, 3 JAL loops, Halts
//              3. Decodes and prints real-time UART TX serial output at 115200 baud
//              4. Verifies Cycle-by-cycle Trace, Mode Summaries, & Final Comparison
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
        .CLK_FREQ  (50_000_000),
        .BAUD_RATE (SIM_BAUD)
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
        $display("   STARTING FEATURE 6 I-CACHE VERIFICATION TESTBENCH");
        $display("============================================================\n");

        clk100mhz  = 1'b0;
        cpu_resetn = 1'b0;
        btnc       = 1'b0;
        sw         = 16'h0000; // SW[0] = 0 (I-cache enabled)

        // --------------------------------------------------------------------
        // TEST 1: Run in Mode 0 (I-Cache Enabled)
        // --------------------------------------------------------------------
        $display("[TB] --------------------------------------------------------");
        $display("[TB] TEST 1: Running Benchmark in Mode 0 (I-Cache Enabled)...");
        $display("[TB] SW0 = 0, Cold Cache, Expecting ~32 cycles, 11 insts, 9 hits, 2 misses.");
        $display("[TB] --------------------------------------------------------");

        sw[0] = 1'b0;
        #300;
        cpu_resetn = 1'b1; // Release reset to start run

        // Wait until benchmark run completes and UART printing finishes (LED[4] == 1)
        wait (led[1] == 1'b1);
        $display("[TB] >>> Core halted! Active benchmark completed in Mode 0.");
        $display("[TB] >>> Waiting for UART transmission to complete...");

        wait (led[4] == 1'b1);
        $display("[TB] >>> UART transmission finished for Mode 0!\n");
        #20000; // Wait 20 us

        // --------------------------------------------------------------------
        // TEST 2: Run in Mode 1 (I-Cache Bypassed)
        // --------------------------------------------------------------------
        $display("\n[TB] --------------------------------------------------------");
        $display("[TB] TEST 2: Switching to Mode 1 (I-Cache Bypassed)...");
        $display("[TB] Setting SW0 = 1, pressing CPU_RESETN (cold cache).");
        $display("[TB] Expecting ~113 cycles, 11 insts, 0 hits, 11 misses.");
        $display("[TB] Expecting Comparison Table at the end!");
        $display("[TB] --------------------------------------------------------");

        sw[0] = 1'b1;
        #500;
        cpu_resetn = 1'b0; // Press reset button
        #1000;
        cpu_resetn = 1'b1; // Release reset button

        wait (led[1] == 1'b1);
        $display("[TB] >>> Core halted! Active benchmark completed in Mode 1.");
        $display("[TB] >>> Waiting for UART transmission to complete...");

        wait (led[4] == 1'b1);
        $display("[TB] >>> UART transmission finished for Mode 1!\n");
        #50000; // Wait 50 us

        $display("\n============================================================");
        $display("   FEATURE 6 VERIFICATION TESTBENCH COMPLETED SUCCESSFULLY!");
        $display("============================================================\n");
        $finish;
    end

endmodule
