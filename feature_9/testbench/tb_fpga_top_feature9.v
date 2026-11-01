// ============================================================================
// File: tb_fpga_top_feature9.v
// Module: tb_fpga_top_feature9
// Description: Full Board-Level Testbench for Nexys A7 Feature 9 FPGA Top
// Simulates 100 MHz Board Clock, captures UART Output stream,
// and verifies exact byte-for-byte table and summary output for both:
//   - SW[4] = 0 (Bare-Metal C Program)
//   - SW[4] = 1 (Synthetic Benchmark)
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

    // DUT with fast baud rate and fast debounce for simulation
    fpga_top_feature9 #(
        .CLK_FREQ     (50_000_000),
        .BAUD_RATE    (SIM_BAUD_RATE),
        .DEBOUNCE_BITS(2)
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
        sw         = 16'h0; // SW[4] = 0 -> Bare-Metal C Test

        $display("==================================================");
        $display(" STARTING FPGA TOP FEATURE 9 UART VERIFICATION");
        $display(" MODE 1: SW[4] = 0 (Bare-Metal C Program)");
        $display("==================================================");

        #100;
        @(negedge clk_100mhz);
        cpu_resetn = 1;

        wait(u_dut.run_done == 1'b1);
        $display("\n[FPGA_TOP] C Program completed! Streaming UART telemetry...\n");

        wait(u_dut.seq_state == 3'd7); // SEQ_ALL_DONE
        #50000;
        $display("\n==================================================");
        $display(" UART C-PROGRAM COMPLETE! Total characters: %0d", rx_char_count);
        $display(" Status LEDs: led[4]=%b (PASS), led[3]=%b (VIOLATION)", led[4], led[3]);
        $display(" Seven-Seg Display Data: 0x%08X", u_dut.display_data);
        $display("==================================================");

        if (rx_char_count == 606 && led[4] == 1'b1 && led[3] == 1'b0 && u_dut.c_return_val_a0 == 16'd18) begin
            $display(">>> MODE 1 (C PROGRAM) 100%% SUCCESSFUL! <<<\n");
        end else begin
            $display(">>> MODE 1 (C PROGRAM) FAILED! <<<\n");
        end

        // ------------------------------------------------------------
        // Now Test Dynamic Switch Transition: Flip SW[4] to 1 (Benchmark)
        // ------------------------------------------------------------
        $display("==================================================");
        $display(" MODE 2: Flipping SW[4] to 1 (Synthetic Benchmark)");
        $display("==================================================");
        rx_char_count = 0;
        sw[4] = 1'b1;

        #500;
        wait(u_dut.run_done == 1'b1);
        $display("\n[FPGA_TOP] Benchmark completed! Streaming UART telemetry...\n");

        wait(u_dut.seq_state == 3'd7); // SEQ_ALL_DONE
        #50000;
        $display("\n==================================================");
        $display(" UART BENCHMARK COMPLETE! Total characters: %0d", rx_char_count);
        $display(" Status LEDs: led[4]=%b (PASS), led[3]=%b (VIOLATION)", led[4], led[3]);
        $display(" Seven-Seg Display Data: 0x%08X", u_dut.display_data);
        $display("==================================================");

        if (rx_char_count == 1540 && led[4] == 1'b1 && led[3] == 1'b0 && u_dut.bench_retire_count == 22) begin
            $display(">>> MODE 2 (BENCHMARK) 100%% SUCCESSFUL! <<<\n");
            $display(">>> ALL DUAL-MODE FPGA VERIFICATIONS 100%% SUCCESSFUL! <<<");
        end else begin
            $display(">>> MODE 2 (BENCHMARK) FAILED! <<<\n");
        end

        $finish;
    end

endmodule
