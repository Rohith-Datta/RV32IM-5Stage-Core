// ============================================================================
// File: tb_fpga_top_feature8.v
// Module: tb_fpga_top_feature8
// Description: Verification testbench for fpga_top_feature8
//              Verifies BTB execution, trace capture, and UART transmission
// ============================================================================

`timescale 1ns/1ps

module tb_fpga_top_feature8;

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

    // Instantiate FPGA top with fast baud rate for instant simulation verification
    // (50 MHz / 2,500,000 = 20 clocks per bit)
    fpga_top_feature8 #(
        .CLK_FREQ (50_000_000),
        .BAUD_RATE(2_500_000)
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
    localparam BIT_PERIOD = (1_000_000_000 / 2_500_000); // 400 ns per bit
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
        $display("=== Reset deasserted, starting Feature 8 BTB execution ===");
    end

    // Monitor completion
    always @(posedge dut.clk_50mhz) begin
        if (dut.sys_reset_n) begin
            if (dut.run_done && dut.tx_fsm == 3'd4) begin
                $display("\n=== UART stream completed successfully! ===");
                #1000;
                $finish;
            end
        end
    end

    // UART RX decoding thread
    always begin
        @(negedge uart_tx);
        // Start bit detected: wait 1.5 bit periods to sample bit 0
        #(BIT_PERIOD * 1.5);
        for (b = 0; b < 8; b = b + 1) begin
            rx_byte[b] = uart_tx;
            #(BIT_PERIOD);
        end
        $write("%c", rx_byte);
        // Wait for stop bit
        #(BIT_PERIOD * 0.5);
    end

    initial begin
        // Timeout after 6 milliseconds of simulation time
        #6_000_000;
        $display("\n=== Simulation finished ===");
        $finish;
    end

endmodule
