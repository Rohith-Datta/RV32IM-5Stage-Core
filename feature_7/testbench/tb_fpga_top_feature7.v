// ============================================================================
// File: tb_fpga_top_feature7.v
// Module: tb_fpga_top_feature7
// Description: Verification testbench for fpga_top_feature7
//              Verifies both Phase 1 (BTB Benchmark) and Phase 2 (Bare-Metal C Program btb.c)
//              with UART streaming of both traces and summaries.
// ============================================================================

`timescale 1ns/1ps

module tb_fpga_top_feature7;

    reg         clk_100mhz;
    reg         cpu_resetn;
    reg         btnc;
    reg  [15:0] sw;
    wire [7:0]  an;
    wire [6:0]  seg;
    wire        dp;
    wire [15:0] led;
    wire        uart_tx;
    reg         uart_rx;

    // 100 MHz clock = 10 ns period
    always #5 clk_100mhz = ~clk_100mhz;

    // Fast baud rate for instant simulation verification (50 MHz / 5,000,000 = 10 clocks per bit)
    fpga_top_feature7 #(
        .CLK_FREQ (50_000_000),
        .BAUD_RATE(5_000_000)
    ) dut (
        .clk_100mhz(clk_100mhz),
        .cpu_resetn(cpu_resetn),
        .btnc      (btnc),
        .sw        (sw),
        .an        (an),
        .seg       (seg),
        .dp        (dp),
        .led       (led),
        .uart_tx   (uart_tx),
        .uart_rx   (uart_rx)
    );

    // UART receiver to capture streamed characters in testbench
    localparam BIT_PERIOD = (1_000_000_000 / 5_000_000); // 200 ns per bit
    reg [7:0] rx_byte;
    integer b;

    initial begin
        clk_100mhz = 0;
        cpu_resetn = 0;
        btnc       = 0;
        sw         = 16'd0;
        uart_rx    = 1;

        #100;
        cpu_resetn = 1;
        $display("=== Reset deasserted, starting Feature 7 Dual BTB Verification ===");
    end

    // Monitor completion of both phases
    always @(posedge dut.clk_50mhz) begin
        if (dut.sys_reset_n) begin
            if (dut.seq_state == 3'd6) begin
                $display("\n=== Both Phase 1 & Phase 2 UART streams completed successfully! ===");
                #2000;
                $finish;
            end
        end
    end

    // UART RX decoding thread
    always begin
        @(negedge uart_tx);
        #(BIT_PERIOD * 1.5);
        for (b = 0; b < 8; b = b + 1) begin
            rx_byte[b] = uart_tx;
            #(BIT_PERIOD);
        end
        $write("%c", rx_byte);
        #(BIT_PERIOD * 0.5);
    end

    initial begin
        // Timeout after 6 milliseconds of simulation time
        #6_000_000;
        $display("\n=== Simulation finished / timeout ===");
        $finish;
    end

endmodule
