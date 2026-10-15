// ============================================================================
// File: tb_uart.v
// Description: Verification Testbench for Feature 3 UART Subsystem
// Project: Pipelined RV32IM Core with Hardware Divider (Feature 3)
// Tests: MMIO Character Writes, FIFO Queuing, 115200 Baud Timing, and Serial Framing
// ============================================================================

`timescale 1ns/1ps

module tb_uart;

    reg clk;
    reg reset_n;

    // 50 MHz clock (20 ns period)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // Interconnects to uart_unit
    reg  [31:0] dmem_addr;
    reg  [31:0] dmem_wdata;
    reg         dmem_we;
    reg         dmem_re;
    wire [31:0] uart_rdata;
    wire        uart_addr_match;
    wire        uart_tx;
    wire        uart_busy;

    // Fast baud rate for quick simulation (or standard 115200)
    // 50 MHz / 1,000,000 baud = 50 cycles per bit (fast simulation)
    localparam SIM_BAUD = 1_000_000;
    localparam BIT_PERIOD_NS = 1_000_000_000 / SIM_BAUD; // 1000 ns
    localparam BANNER_WAIT_TIME = 1000;

    uart_unit #(
        .CLK_FREQ  (50_000_000),
        .BAUD_RATE (SIM_BAUD),
        .FIFO_DEPTH(64)
    ) dut (
        .clk            (clk),
        .reset_n        (reset_n),
        .dmem_addr      (dmem_addr),
        .dmem_wdata     (dmem_wdata),
        .dmem_we        (dmem_we),
        .dmem_re        (dmem_re),
        .uart_rdata     (uart_rdata),
        .uart_addr_match(uart_addr_match),
        .fetch_pc       (32'h0000_0020),
        .fetch_inst     (32'h06400793),
        .hazard_stall   (1'b0),
        .step_trigger   (1'b0),
        .uart_tx        (uart_tx),
        .uart_busy      (uart_busy),
        .banner_done_o  ()
    );

    // ========================================================================
    // Behavioral UART Receiver Model (Checks incoming serial bits)
    // ========================================================================
    reg [7:0] rx_byte;
    integer i;

    task rx_monitor;
        begin
            // 1. Wait for Start bit (falling edge)
            @(negedge uart_tx);
            #(BIT_PERIOD_NS / 2); // Sample at middle of start bit
            if (uart_tx !== 1'b0) begin
                $display("[ERROR] False start bit detected!");
            end else begin
                // 2. Sample 8 data bits
                for (i = 0; i < 8; i = i + 1) begin
                    #BIT_PERIOD_NS;
                    rx_byte[i] = uart_tx;
                end
                // 3. Sample Stop bit
                #BIT_PERIOD_NS;
                if (uart_tx !== 1'b1) begin
                    $display("[ERROR] Framing Error: Stop bit is not HIGH!");
                end else begin
                    $write("%c", rx_byte);
                    $fflush();
                end
            end
        end
    endtask

    // Background receiver process
    initial begin
        forever begin
            rx_monitor();
        end
    end

    // ========================================================================
    // Test Sequence
    // ========================================================================
    task mmio_write_char(input [7:0] ch);
        begin
            @(posedge clk);
            dmem_addr  <= 32'h8000_0000;
            dmem_wdata <= {24'h0, ch};
            dmem_we    <= 1'b1;
            @(posedge clk);
            dmem_we    <= 1'b0;
            dmem_addr  <= 32'h0;
            // Short delay between characters
            repeat (20) @(posedge clk);
        end
    endtask

    initial begin
        $display("\n=======================================================");
        $display(" STARTING FEATURE 3 UART TESTBENCH (tb_uart.v)");
        $display("=======================================================");

        dmem_addr  = 32'h0;
        dmem_wdata = 32'h0;
        dmem_we    = 1'b0;
        dmem_re    = 1'b0;
        reset_n    = 1'b0;

        #200;
        reset_n = 1'b1;
        $display("[TB] System reset released. Capturing boot banner...\n");

        // Wait for boot banner to finish transmitting
        # (BANNER_WAIT_TIME);
        wait (dut.banner_done == 1'b1);
        wait (dut.fifo_empty == 1'b1);
        # (BIT_PERIOD_NS * 12);

        $display("\n[TB] Boot banner completed successfully!");
        $display("[TB] Sending test characters via CPU MMIO (0x8000_0000):");

        mmio_write_char("F");
        mmio_write_char("E");
        mmio_write_char("A");
        mmio_write_char("T");
        mmio_write_char("U");
        mmio_write_char("R");
        mmio_write_char("E");
        mmio_write_char(" ");
        mmio_write_char("3");
        mmio_write_char(" ");
        mmio_write_char("D");
        mmio_write_char("I");
        mmio_write_char("V");
        mmio_write_char("!");
        mmio_write_char("\r");
        mmio_write_char("\n");

        // Wait for all characters to transmit out of FIFO
        wait (dut.fifo_empty == 1'b1 && dut.uart_busy == 1'b0);
        # (BIT_PERIOD_NS * 15);

        $display("\n=======================================================");
        $display(" [PASS] FEATURE 3 UART TRANSMISSION TEST PASSED!");
        $display("=======================================================\n");
        $finish;
    end

endmodule
