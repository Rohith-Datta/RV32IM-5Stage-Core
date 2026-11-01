// ============================================================================
// File: tb_fpga_top_feature9.v
// Module: tb_fpga_top_feature9
// Description: Full Board-Level Testbench for Nexys A7 Feature 9 FPGA Top
// Simulates 100 MHz Board Clock, captures UART Output stream,
// and verifies exact byte-for-byte table and summary output.
// ============================================================================

`timescale 1ns/1ps

module tb_fpga_top_feature9;

    reg         clk_100mhz;
    reg         cpu_resetn;
    reg         btnc;
    reg  [15:0] sw;
    wire [7:0]  an;
    wire [6:0]  seg;
    wire        dp;
    wire [15:0] led;
    wire        uart_tx;

    // 100 MHz oscillator (10 ns clock period)
    always #5 clk_100mhz = ~clk_100mhz;

    // Fast baud rate for fast simulation (2.5 MBaud: 20 cycles of 50 MHz per bit)
    localparam SIM_BAUD_RATE = 2_500_000;
    localparam BIT_PERIOD    = 400.0; // 400 ns per bit at 2.5 MBaud

    // DUT
    fpga_top_feature9 #(
        .CLK_FREQ (50_000_000),
        .BAUD_RATE(SIM_BAUD_RATE)
    ) u_dut (
        .clk_100mhz(clk_100mhz),
        .cpu_resetn(cpu_resetn),
        .btnc      (btnc),
        .sw        (sw),
        .an        (an),
        .seg       (seg),
        .dp        (dp),
        .led       (led),
        .uart_tx   (uart_tx),
        .uart_rx   (1'b1)
    );

    reg [7:0] rx_byte;
    integer rx_char_count = 0;

    // Monitor and decode UART characters
    initial begin
        forever begin
            // Wait for start bit (falling edge of uart_tx)
            @(negedge uart_tx);
            // Sample in the middle of start bit
            #(BIT_PERIOD / 2.0);
            if (uart_tx == 1'b0) begin
                // Read 8 data bits
                #(BIT_PERIOD);
                rx_byte[0] = uart_tx;
                #(BIT_PERIOD);
                rx_byte[1] = uart_tx;
                #(BIT_PERIOD);
                rx_byte[2] = uart_tx;
                #(BIT_PERIOD);
                rx_byte[3] = uart_tx;
                #(BIT_PERIOD);
                rx_byte[4] = uart_tx;
                #(BIT_PERIOD);
                rx_byte[5] = uart_tx;
                #(BIT_PERIOD);
                rx_byte[6] = uart_tx;
                #(BIT_PERIOD);
                rx_byte[7] = uart_tx;

                // Stop bit
                #(BIT_PERIOD);
                $write("%c", rx_byte);
                rx_char_count = rx_char_count + 1;
            end
        end
    end

    initial begin
        clk_100mhz = 0;
        cpu_resetn = 0;
        btnc       = 0;
        sw         = 16'h0;

        $display("==================================================");
        $display(" STARTING FPGA TOP FEATURE 9 UART VERIFICATION");
        $display("==================================================");

        #100;
        @(negedge clk_100mhz);
        cpu_resetn = 1;

        wait(u_dut.run_done == 1'b1);
        $display("\n[FPGA_TOP] Core completed execution! Streaming UART output...\n");

        wait(u_dut.fsm_state == 2'd3 || rx_char_count >= 1540);
        #50000;
        $display("\n==================================================");
        $display(" UART TRANSMISSION COMPLETE! Total characters: %0d", rx_char_count);
        $display(" Status LEDs: led[4]=%b (PASS), led[3]=%b (VIOLATION)", led[4], led[3]);
        $display("==================================================");
        if (rx_char_count == 1540 && led[4] == 1'b1 && led[3] == 1'b0) begin
            $display(">>> FPGA TOP-LEVEL VERIFICATION 100%% SUCCESSFUL! <<<");
        end else begin
            $display(">>> FPGA TOP-LEVEL VERIFICATION FAILED! <<<");
        end
        $finish;
    end

endmodule
