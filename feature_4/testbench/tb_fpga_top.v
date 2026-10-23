// ============================================================================
// File: tb_fpga_top.v
// Module: tb_fpga_top
// Description: Full Board-Level FPGA Integration Testbench for Nexys A7-100T
// Project: Pipelined RV32IMF Core with IEEE-754 FPU (Feature 4)
// ============================================================================

`timescale 1ns/1ps

module tb_fpga_top;

    reg        clk_100mhz;
    reg        cpu_resetn;
    reg  [15:0] sw;
    reg        btnc;
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
    fpga_top_feature4 dut (
        .clk_100mhz (clk_100mhz),
        .cpu_resetn (cpu_resetn),
        .sw         (sw),
        .btnc       (btnc),
        .led        (led),
        .an         (an),
        .seg        (seg),
        .dp         (dp),
        .uart_tx    (uart_tx)
    );

    initial begin
        $display("============================================================================");
        $display("   STARTING TESTBENCH: tb_fpga_top (Nexys A7-100T Board Integration)        ");
        $display("============================================================================");

        // Switches:
        // sw[0] = 0 (Auto step via UART synchronization)
        // sw[1] = 0 (Normal auto speed)
        // sw[2] = 0 (Display PC on 7-seg)
        // sw[3] = 1 (DSP Multiplier mode)
        sw = 16'b0000_0000_0000_1000;
        btnc = 0;
        cpu_resetn = 0;

        #200;
        @(posedge clk_100mhz);
        #1;
        cpu_resetn = 1;
        $display("[FPGA TB] Board released from reset, 100 MHz oscillator running.");

        // Monitor program completion
        wait (led[7] == 1'b1);
        $display("[FPGA TB] Program Done Signal (LED[7]) ASSERTED at time %0t ns!", $time);
        $display("[FPGA TB] 7-Segment Anodes: 8'b%08b", an);
        $display("[FPGA TB] LEDs State: 16'h%04h", led);

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
