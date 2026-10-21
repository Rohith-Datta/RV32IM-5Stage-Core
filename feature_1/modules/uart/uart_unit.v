// ============================================================================
// File: uart_unit.v
// Description: Full Memory-Mapped I/O (MMIO) UART Subsystem with FIFO, 
//              Boot Banner Generator, and Real-Time Fetch & Hazard Telemetry
// Project: Pipelined RV32I Processor (Feature 1)
// Target Device: Digilent Nexys A7-100T (FTDI FT2232HQ USB-UART on Pin D4)
// Baud Rate: 115,200 Baud (Clocked from 100 MHz oscillator)
// ============================================================================

`timescale 1ns/1ps

module uart_unit #(
    parameter CLK_FREQ   = 100_000_000,
    parameter BAUD_RATE  = 115_200,
    parameter FIFO_DEPTH = 64
)(
    input  wire        clk,             // 100 MHz board oscillator
    input  wire        reset_n,         // Active-low synchronous reset

    // CPU Memory-Mapped I/O Interface (from MEM Stage)
    input  wire [31:0] dmem_addr,       // Access address
    input  wire [31:0] dmem_wdata,      // Store data
    input  wire        dmem_we,         // Store write enable
    input  wire        dmem_re,         // Load read enable
    output reg  [31:0] uart_rdata,      // Status/read data back to CPU
    output wire        uart_addr_match, // 1 when address is in UART MMIO space

    // Real-Time Fetch & Hazard Telemetry Interface (from IF Stage & Hazard Unit)
    input  wire [31:0] fetch_pc,        // Instruction Fetch Address (imem_addr)
    input  wire [31:0] fetch_inst,      // Instruction Machine Code (imem_rdata)
    input  wire        hazard_stall,    // Hazard detection stall flag (stall_if)
    input  wire        step_trigger,    // 1-cycle pulse when a step occurs

    // Physical Serial Output
    output wire        uart_tx,         // UART TX pin (Nexys A7 Pin D4)
    output wire        uart_busy,       // Global busy indicator
    output wire        banner_done_o    // Banner complete status
);

    // ========================================================================
    // 1. Address Decoding
    // MMIO Range: 0x8000_0000 - 0x8000_0007
    //   0x8000_0000 : UART_TX_DATA   (Write: char byte, Read: 0)
    //   0x8000_0004 : UART_STATUS    (Read: [0]=tx_busy, [1]=fifo_full, [2]=fifo_empty)
    // ========================================================================
    assign uart_addr_match = (dmem_addr[31:16] == 16'h8000);
    wire is_tx_data_reg    = uart_addr_match && (dmem_addr[3:0] == 4'h0);
    wire is_status_reg     = uart_addr_match && (dmem_addr[3:0] == 4'h4);

    // Synchronize and detect 1-cycle CPU write pulse
    reg dmem_we_d1;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) dmem_we_d1 <= 1'b0;
        else          dmem_we_d1 <= dmem_we && is_tx_data_reg;
    end
    wire mmio_push = (dmem_we && is_tx_data_reg) && !dmem_we_d1;

    // ========================================================================
    // 2. 64-Byte Circular FIFO Buffer
    // ========================================================================
    reg [7:0] fifo_mem [0:FIFO_DEPTH-1];
    reg [5:0] wr_ptr;
    reg [5:0] rd_ptr;
    reg [6:0] fifo_count;

    wire fifo_full  = (fifo_count == FIFO_DEPTH);
    wire fifo_empty = (fifo_count == 7'd0);
    reg  telem_active;

    // Arbiter inputs into FIFO (MMIO has priority, then Banner, then Telemetry)
    wire       arb_wr_en;
    wire [7:0] arb_wdata;

    wire banner_wr_en;
    wire [7:0] banner_wdata;
    wire telem_wr_en;
    wire [7:0] telem_wdata;

    assign arb_wr_en = mmio_push ? 1'b1 :
                       banner_wr_en ? 1'b1 :
                       telem_wr_en ? 1'b1 : 1'b0;

    assign arb_wdata = mmio_push ? dmem_wdata[7:0] :
                       banner_wr_en ? banner_wdata :
                       telem_wdata;

    // FIFO Pop interface to physical UART TX
    wire tx_busy;
    reg  tx_start;
    reg  [7:0] tx_data_reg;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            wr_ptr      <= 6'd0;
            rd_ptr      <= 6'd0;
            fifo_count  <= 7'd0;
            tx_start    <= 1'b0;
            tx_data_reg <= 8'd0;
        end else begin
            // Write into FIFO
            if (arb_wr_en && !fifo_full) begin
                fifo_mem[wr_ptr] <= arb_wdata;
                wr_ptr <= wr_ptr + 6'd1;
            end

            // Pop from FIFO into UART TX
            if (!tx_busy && !tx_start && !fifo_empty) begin
                tx_data_reg <= fifo_mem[rd_ptr];
                tx_start    <= 1'b1;
                rd_ptr      <= rd_ptr + 6'd1;
                if (arb_wr_en && !fifo_full) begin
                    fifo_count <= fifo_count; // Simultaneous push and pop
                end else begin
                    fifo_count <= fifo_count - 7'd1;
                end
            end else if (arb_wr_en && !fifo_full) begin
                fifo_count <= fifo_count + 7'd1;
                tx_start   <= 1'b0;
            end else begin
                tx_start   <= 1'b0;
            end
        end
    end

    // Read status register
    always @(*) begin
        if (is_status_reg) begin
            uart_rdata = {29'b0, fifo_empty, fifo_full, (tx_busy || !fifo_empty)};
        end else begin
            uart_rdata = 32'h0;
        end
    end

    assign uart_busy = tx_busy || !fifo_empty || telem_active;

    // ========================================================================
    // 3. Physical UART Transmitter (8-N-1 at 115200 baud)
    // ========================================================================
    uart_tx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_tx (
        .clk     (clk),
        .reset_n (reset_n),
        .tx_start(tx_start),
        .tx_data (tx_data_reg),
        .tx      (uart_tx),
        .tx_busy (tx_busy)
    );

    // ========================================================================
    // 4. Power-on Startup Banner Streamer
    // ========================================================================
    localparam BANNER_LEN = 52;
    wire [7:0] banner_rom [0:BANNER_LEN-1];
    assign banner_rom[ 0] = 8'h0D; assign banner_rom[ 1] = 8'h0A;
    assign banner_rom[ 2] = "=";  assign banner_rom[ 3] = "=";  assign banner_rom[ 4] = "=";
    assign banner_rom[ 5] = " ";  assign banner_rom[ 6] = "R";  assign banner_rom[ 7] = "V";
    assign banner_rom[ 8] = "3";  assign banner_rom[ 9] = "2";  assign banner_rom[10] = "I";
    assign banner_rom[11] = " ";  assign banner_rom[12] = "C";  assign banner_rom[13] = "o";
    assign banner_rom[14] = "r";  assign banner_rom[15] = "e";  assign banner_rom[16] = " ";
    assign banner_rom[17] = "(";  assign banner_rom[18] = "G";  assign banner_rom[19] = "r";
    assign banner_rom[20] = "o";  assign banner_rom[21] = "u";  assign banner_rom[22] = "p";
    assign banner_rom[23] = "1";  assign banner_rom[24] = "3";  assign banner_rom[25] = ")";
    assign banner_rom[26] = " ";  assign banner_rom[27] = "A";  assign banner_rom[28] = "c";
    assign banner_rom[29] = "t";  assign banner_rom[30] = "i";  assign banner_rom[31] = "v";
    assign banner_rom[32] = "e";  assign banner_rom[33] = " ";  assign banner_rom[34] = "@";
    assign banner_rom[35] = "1";  assign banner_rom[36] = "1";  assign banner_rom[37] = "5";
    assign banner_rom[38] = "2";  assign banner_rom[39] = "0";  assign banner_rom[40] = "0";
    assign banner_rom[41] = " ";  assign banner_rom[42] = "=";  assign banner_rom[43] = "=";
    assign banner_rom[44] = "=";  assign banner_rom[45] = 8'h0D; assign banner_rom[46] = 8'h0A;
    assign banner_rom[47] = "-";  assign banner_rom[48] = "-";  assign banner_rom[49] = 8'h0D;
    assign banner_rom[50] = 8'h0A; assign banner_rom[51] = 8'h00;

    reg [5:0] banner_idx;
    reg       banner_done;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            banner_idx  <= 6'd0;
            banner_done <= 1'b0;
        end else if (!banner_done && (fifo_count < FIFO_DEPTH - 2)) begin
            if (banner_idx < BANNER_LEN - 1) begin
                banner_idx <= banner_idx + 6'd1;
            end else begin
                banner_done <= 1'b1;
            end
        end
    end

    assign banner_wr_en  = (!banner_done && (fifo_count < FIFO_DEPTH - 2));
    assign banner_wdata  = banner_rom[banner_idx];
    assign banner_done_o = banner_done;

    // ========================================================================
    // 5. Real-Time Fetch & Hazard Telemetry Serializer
    // Formats:
    //   - Normal Fetch : "PC: 0x00000000 | INST: 0xFE010113\r\n" (35 bytes)
    //   - Hazard Stall : "---------stall---------\r\n"          (25 bytes)
    // Zero-lag synchronization with Nexys A7 7-segment display!
    // ========================================================================
    reg [5:0]  telem_idx;
    reg        snap_is_stall;
    reg [31:0] snap_pc;
    reg [31:0] snap_inst;

    // Hex to ASCII converter
    function [7:0] to_hex(input [3:0] nibble);
        to_hex = (nibble < 4'd10) ? (8'h30 + {4'b0, nibble}) : (8'h41 + {4'b0, nibble} - 8'd10);
    endfunction

    // Capture registers for step trigger & hazard detection
    reg init_pc_sent;
    reg step_trigger_d1;
    reg is_stall_sample;

    // Pending buffer so no step pulse is ever lost
    reg        step_pending;
    reg        pending_is_stall;
    reg [31:0] pending_pc;
    reg [31:0] pending_inst;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            step_trigger_d1  <= 1'b0;
            is_stall_sample  <= 1'b0;
            step_pending     <= 1'b0;
            pending_is_stall <= 1'b0;
            pending_pc       <= 32'd0;
            pending_inst     <= 32'd0;
        end else begin
            step_trigger_d1 <= step_trigger;
            if (step_trigger) begin
                is_stall_sample <= hazard_stall;
            end

            // When a step occurs, latch the event
            if (step_trigger_d1 && banner_done && init_pc_sent) begin
                if (telem_active) begin
                    step_pending     <= 1'b1;
                    pending_is_stall <= is_stall_sample;
                    pending_pc       <= fetch_pc;
                    pending_inst     <= fetch_inst;
                end
            end else if (!telem_active && step_pending) begin
                step_pending <= 1'b0;
            end
        end
    end

    // Telemetry trigger condition
    wire init_trigger = banner_done && !init_pc_sent && !telem_active && (fifo_count < FIFO_DEPTH - 2);
    wire direct_step  = step_trigger_d1 && banner_done && init_pc_sent && !telem_active;
    wire queued_step  = !telem_active && step_pending && banner_done && init_pc_sent && (fifo_count < FIFO_DEPTH - 2);

    wire [5:0] telem_max_idx = (snap_is_stall) ? 6'd24 : 6'd34;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            telem_active  <= 1'b0;
            telem_idx     <= 6'd0;
            snap_is_stall <= 1'b0;
            snap_pc       <= 32'd0;
            snap_inst     <= 32'd0;
            init_pc_sent  <= 1'b0;
        end else begin
            if (init_trigger) begin
                // Stream initial PC 0x00000000 right after boot banner
                telem_active  <= 1'b1;
                telem_idx     <= 6'd0;
                snap_is_stall <= 1'b0;
                snap_pc       <= fetch_pc;
                snap_inst     <= fetch_inst;
                init_pc_sent  <= 1'b1;
            end else if (direct_step) begin
                // Stream on immediate step trigger
                telem_active  <= 1'b1;
                telem_idx     <= 6'd0;
                snap_is_stall <= is_stall_sample;
                snap_pc       <= fetch_pc;
                snap_inst     <= fetch_inst;
            end else if (queued_step) begin
                // Stream queued step if previous line was still serializing
                telem_active  <= 1'b1;
                telem_idx     <= 6'd0;
                snap_is_stall <= pending_is_stall;
                snap_pc       <= pending_pc;
                snap_inst     <= pending_inst;
            end else if (telem_active && (fifo_count < FIFO_DEPTH - 2)) begin
                if (telem_idx < telem_max_idx) begin
                    telem_idx <= telem_idx + 6'd1;
                end else begin
                    telem_active <= 1'b0;
                    telem_idx    <= 6'd0;
                end
            end
        end
    end

    reg [7:0] telem_char;
    always @(*) begin
        if (snap_is_stall) begin
            // Output: "---------stall---------\r\n" (25 bytes)
            case (telem_idx)
                6'd0, 6'd1, 6'd2, 6'd3, 6'd4, 6'd5, 6'd6, 6'd7, 6'd8:
                       telem_char = "-";
                6'd9:  telem_char = "s";
                6'd10: telem_char = "t";
                6'd11: telem_char = "a";
                6'd12: telem_char = "l";
                6'd13: telem_char = "l";
                6'd14, 6'd15, 6'd16, 6'd17, 6'd18, 6'd19, 6'd20, 6'd21, 6'd22:
                       telem_char = "-";
                6'd23: telem_char = 8'h0D; // \r
                6'd24: telem_char = 8'h0A; // \n
                default: telem_char = " ";
            endcase
        end else begin
            // Output: "PC: 0x00000000 | INST: 0xFE010113\r\n" (35 bytes)
            case (telem_idx)
                6'd0:  telem_char = "P";
                6'd1:  telem_char = "C";
                6'd2:  telem_char = ":";
                6'd3:  telem_char = " ";
                6'd4:  telem_char = "0";
                6'd5:  telem_char = "x";
                6'd6:  telem_char = to_hex(snap_pc[31:28]);
                6'd7:  telem_char = to_hex(snap_pc[27:24]);
                6'd8:  telem_char = to_hex(snap_pc[23:20]);
                6'd9:  telem_char = to_hex(snap_pc[19:16]);
                6'd10: telem_char = to_hex(snap_pc[15:12]);
                6'd11: telem_char = to_hex(snap_pc[11:8]);
                6'd12: telem_char = to_hex(snap_pc[7:4]);
                6'd13: telem_char = to_hex(snap_pc[3:0]);
                6'd14: telem_char = " ";
                6'd15: telem_char = "|";
                6'd16: telem_char = " ";
                6'd17: telem_char = "I";
                6'd18: telem_char = "N";
                6'd19: telem_char = "S";
                6'd20: telem_char = "T";
                6'd21: telem_char = ":";
                6'd22: telem_char = " ";
                6'd23: telem_char = "0";
                6'd24: telem_char = "x";
                6'd25: telem_char = to_hex(snap_inst[31:28]);
                6'd26: telem_char = to_hex(snap_inst[27:24]);
                6'd27: telem_char = to_hex(snap_inst[23:20]);
                6'd28: telem_char = to_hex(snap_inst[19:16]);
                6'd29: telem_char = to_hex(snap_inst[15:12]);
                6'd30: telem_char = to_hex(snap_inst[11:8]);
                6'd31: telem_char = to_hex(snap_inst[7:4]);
                6'd32: telem_char = to_hex(snap_inst[3:0]);
                6'd33: telem_char = 8'h0D; // \r
                6'd34: telem_char = 8'h0A; // \n
                default: telem_char = " ";
            endcase
        end
    end

    assign telem_wr_en = telem_active && (fifo_count < FIFO_DEPTH - 2);
    assign telem_wdata = telem_char;

endmodule
