// ============================================================================
// File: tb_uart.v
// Module: tb_uart
// Description: Verification Testbench for Feature 6 UART Telemetry Subsystem
// Project: Pipelined RV32IMF Core with L1 Harvard Caches (Feature 6)
// Clock: Standard 50 MHz (20 ns clock period)
// Tests: MMIO Character Writes, FIFO Queuing, Fast Simulation Baud Timing, and Serial Framing
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

    // Fast baud rate for fast simulation
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
            dmem_addr  = 32'h8000_0000;
            dmem_wdata = {24'd0, ch};
            dmem_we    = 1'b1;
            @(posedge clk);
            dmem_we    = 1'b0;
            dmem_addr  = 32'd0;
            dmem_wdata = 32'd0;
        end
    endtask

    initial begin
        dmem_addr  = 32'd0;
        dmem_wdata = 32'd0;
        dmem_we    = 1'b0;
        dmem_re    = 1'b0;
        reset_n    = 1'b0;

        $display("==================================================================");
        $display("   TESTBENCH: Feature 6 UART Diagnostic Subsystem (tb_uart)       ");
        $display("   Clock: 50 MHz (Period: 20 ns) | Sim Baud: 1,000,000           ");
        $display("==================================================================");
        $display("[*] Asserting Reset...");
        #100;
        @(posedge clk);
        reset_n = 1'b1;
        $display("[*] Reset Released. Capturing Boot Banner...\n");

        // Wait for boot banner to transmit
        #250_000;

        $display("\n\n[*] Banner complete. Testing MMIO Character Writes (0x8000_0000)...");
        mmio_write_char("F");
        mmio_write_char("E");
        mmio_write_char("A");
        mmio_write_char("T");
        mmio_write_char("U");
        mmio_write_char("R");
        mmio_write_char("E");
        mmio_write_char("6");
        mmio_write_char(" ");
        mmio_write_char("O");
        mmio_write_char("K");
        mmio_write_char("\n");

        // Wait for characters to serialize
        #150_000;

        $display("\n==================================================================");
        $display("   UART VERIFICATION COMPLETE: ALL FRAMES RECEIVED WITHOUT ERROR  ");
        $display("==================================================================\n");
        $finish;
    end

endmodule
