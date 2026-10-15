// ============================================================================
// File: uart_tx.v
// Description: Synthesizable 8-N-1 UART Serial Transmitter
// Project: Pipelined RV32I Processor (Feature 1)
// Target Device: Digilent Nexys A7-100T FPGA (Artix-7 XC7A100T)
// Default Parameters: 100 MHz Clock, 115200 Baud Rate
// ============================================================================

`timescale 1ns/1ps

module uart_tx #(
    parameter CLK_FREQ  = 100_000_000, // 100 MHz primary oscillator
    parameter BAUD_RATE = 115_200      // Standard serial baud rate
)(
    input  wire       clk,             // 100 MHz board clock
    input  wire       reset_n,         // Active-low synchronous reset
    input  wire       tx_start,        // 1-cycle strobe to initiate transmit
    input  wire [7:0] tx_data,         // 8-bit data byte to transmit
    output reg        tx,              // Serial TX line (idle HIGH)
    output reg        tx_busy          // HIGH while frame is transmitting
);

    // Number of clock cycles per serial bit
    // At 100 MHz and 115200 baud: 100,000,000 / 115,200 = 868 cycles
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    // FSM States
    localparam STATE_IDLE  = 2'b00;
    localparam STATE_START = 2'b01;
    localparam STATE_DATA  = 2'b10;
    localparam STATE_STOP  = 2'b11;

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  data_buf;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state    <= STATE_IDLE;
            tx       <= 1'b1; // UART idle state is logic HIGH
            tx_busy  <= 1'b0;
            clk_cnt  <= 16'd0;
            bit_idx  <= 3'd0;
            data_buf <= 8'd0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    tx      <= 1'b1;
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (tx_start) begin
                        data_buf <= tx_data;
                        tx_busy  <= 1'b1;
                        state    <= STATE_START;
                    end else begin
                        tx_busy  <= 1'b0;
                    end
                end

                // Start Bit: Driven LOW (0) for 1 bit period
                STATE_START: begin
                    tx <= 1'b0;
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end else begin
                        clk_cnt <= 16'd0;
                        state   <= STATE_DATA;
                    end
                end

                // Data Bits: 8 bits shifted out LSB first
                STATE_DATA: begin
                    tx <= data_buf[bit_idx];
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end else begin
                        clk_cnt <= 16'd0;
                        if (bit_idx < 3'd7) begin
                            bit_idx <= bit_idx + 3'd1;
                        end else begin
                            bit_idx <= 3'd0;
                            state   <= STATE_STOP;
                        end
                    end
                end

                // Stop Bit: Driven HIGH (1) for 1 bit period
                STATE_STOP: begin
                    tx <= 1'b1;
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end else begin
                        clk_cnt <= 16'd0;
                        state   <= STATE_IDLE;
                        tx_busy <= 1'b0;
                    end
                end

                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
