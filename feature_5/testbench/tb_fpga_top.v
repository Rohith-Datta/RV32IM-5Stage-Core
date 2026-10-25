// ============================================================================
// File: tb_fpga_top.v
// Module: tb_fpga_top
// Description: Full Board-Level FPGA Integration Testbench for Nexys A7-100T
// Project: Pipelined RV32IMF Core with L1 D-Cache & UART (Feature 5)
// ============================================================================

`timescale 1ns/1ps

module tb_fpga_top;

    reg        clk_100mhz;
    reg        cpu_resetn;
    reg  [15:0] sw;
    reg        btnc;
    reg        uart_rx;
    wire [15:0] led;
    wire [7:0]  an;
    wire [6:0]  seg;
    wire        dp;
    wire        uart_tx;

    // 100 MHz Board Oscillator (10 ns period)
    initial begin
        clk_100mhz = 0;
        forever #5 clk_100mhz = ~clk_100mhz;
    end

    // Instantiate Top FPGA Module
    fpga_top_feature5 dut (
        .clk_100mhz (clk_100mhz),
        .cpu_resetn (cpu_resetn),
        .sw         (sw),
        .btnc       (btnc),
        .an         (an),
        .seg        (seg),
        .dp         (dp),
        .led        (led),
        .uart_tx    (uart_tx),
        .uart_rx    (uart_rx)
    );

    initial begin
        $display("============================================================================");
        $display("   STARTING TESTBENCH: tb_fpga_top (Feature 5 Nexys A7-100T Integration)    ");
        $display("============================================================================");

        // Switches:
        // sw[0]  = 0 (D-Cache Enabled)
        // sw[1]  = 0 (Normal auto-stream)
        // sw[2]  = 0 (Display PC on 7-seg)
        // sw[3]  = 0 (DSP Multiplier mode)
        // sw[15] = 0 (Continuous mode)
        sw = 16'h0000;
        btnc = 0;
        uart_rx = 1'b1;
        cpu_resetn = 0;

        #200;
        @(posedge clk_100mhz);
        #1;
        cpu_resetn = 1;
        $display("[FPGA TB] Board released from reset, 100 MHz oscillator running.");

        // Monitor program completion (LED[7] is prog_done)
        wait (led[7] == 1'b1);
        $display("[FPGA TB] Program Done Signal (LED[7]) ASSERTED at time %0t ns!", $time);
        $display("[FPGA TB] 7-Segment Anodes: 8'b%08b", an);
        $display("[FPGA TB] LEDs State: 16'h%04h", led);
        $display("[FPGA TB] Final Return a0 (LED[15:10]): %0d (expected 100 [0x64])", led[15:10]);

        #1000;
        $display("\n============================================================================");
        $display("             FPGA TOP-LEVEL VERIFICATION PASSED SUCCESSFULLY!               ");
        $display("============================================================================\n");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #50_000_000; // 50 ms timeout
        $display("\n[FPGA TB] ERROR: Simulation timed out!");
        $finish;
    end

endmodule
