// ============================================================================
// File: uart_unit.v
// Description: Full Memory-Mapped I/O (MMIO) UART Subsystem with FIFO, 
//              Boot Banner Generator, and Real-Time Fetch & Hazard Telemetry
// Project: Pipelined RV32IM Processor (Feature 2)
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
    input  wire        dcache_stall,    // L1 D-Cache burst refill or bypass stall
    input  wire        step_trigger,    // 1-cycle pulse when a step occurs

    // Physical Serial Output
    output wire        uart_tx,         // UART TX pin (Nexys A7 Pin D4)
    output wire        uart_busy,       // Global busy indicator
    output wire        banner_done_o,   // Banner complete status

    // Program Completion & Diagnostic Summary Interface
    input  wire        prog_done,       // High when program completes
    input  wire        dcache_bypass,   // 0: Enabled, 1: Bypassed
    input  wire [31:0] stat_cycles,     // Total execution cycles
    input  wire [31:0] stat_insts,      // Total instructions retired
    input  wire [31:0] stat_hits,       // D-cache hits
    input  wire [31:0] stat_misses,     // D-cache misses
    input  wire [31:0] stat_result      // Final return value a0
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
    reg  summary_active;

    // Arbiter inputs into FIFO (MMIO has priority, then Banner, then Telemetry, then Summary)
    wire       arb_wr_en;
    wire [7:0] arb_wdata;

    wire banner_wr_en;
    wire [7:0] banner_wdata;
    wire telem_wr_en;
    wire [7:0] telem_wdata;
    wire summary_wr_en;
    wire [7:0] summary_wdata;

    assign arb_wr_en = mmio_push ? 1'b1 :
                       banner_wr_en ? 1'b1 :
                       telem_wr_en ? 1'b1 :
                       summary_wr_en ? 1'b1 : 1'b0;

    assign arb_wdata = mmio_push ? dmem_wdata[7:0] :
                       banner_wr_en ? banner_wdata :
                       telem_wr_en ? telem_wdata :
                       summary_wdata;

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

    assign uart_busy = tx_busy || !fifo_empty || telem_active || summary_active;

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
    localparam BANNER_LEN = 53;
    wire [7:0] banner_rom [0:BANNER_LEN-1];
    assign banner_rom[ 0] = 8'h0D; assign banner_rom[ 1] = 8'h0A;
    assign banner_rom[ 2] = "=";  assign banner_rom[ 3] = "=";  assign banner_rom[ 4] = "=";
    assign banner_rom[ 5] = " ";  assign banner_rom[ 6] = "R";  assign banner_rom[ 7] = "V";
    assign banner_rom[ 8] = "3";  assign banner_rom[ 9] = "2";  assign banner_rom[10] = "I";
    assign banner_rom[11] = "M";  assign banner_rom[12] = " ";  assign banner_rom[13] = "C";
    assign banner_rom[14] = "o";  assign banner_rom[15] = "r";  assign banner_rom[16] = "e";
    assign banner_rom[17] = " ";  assign banner_rom[18] = "(";  assign banner_rom[19] = "G";
    assign banner_rom[20] = "r";  assign banner_rom[21] = "o";  assign banner_rom[22] = "u";
    assign banner_rom[23] = "p";  assign banner_rom[24] = "1";  assign banner_rom[25] = "3";
    assign banner_rom[26] = ")";  assign banner_rom[27] = " ";  assign banner_rom[28] = "A";
    assign banner_rom[29] = "c";  assign banner_rom[30] = "t";  assign banner_rom[31] = "i";
    assign banner_rom[32] = "v";  assign banner_rom[33] = "e";  assign banner_rom[34] = " ";
    assign banner_rom[35] = "@";  assign banner_rom[36] = "1";  assign banner_rom[37] = "1";
    assign banner_rom[38] = "5";  assign banner_rom[39] = "2";  assign banner_rom[40] = "0";
    assign banner_rom[41] = "0";  assign banner_rom[42] = " ";  assign banner_rom[43] = "=";
    assign banner_rom[44] = "=";  assign banner_rom[45] = "=";  assign banner_rom[46] = 8'h0D;
    assign banner_rom[47] = 8'h0A; assign banner_rom[48] = "-";  assign banner_rom[49] = "-";
    assign banner_rom[50] = 8'h0D; assign banner_rom[51] = 8'h0A; assign banner_rom[52] = 8'h00;

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
    reg step_trigger_d2;
    reg is_stall_sample;
    reg is_dcache_sample;
    reg [31:0] pc_sample;
    reg [31:0] inst_sample;

    // Pending buffer so no step pulse is ever lost
    reg        step_pending;
    reg        pending_is_stall;
    reg        pending_is_dcache;
    reg [31:0] pending_pc;
    reg [31:0] pending_inst;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            step_trigger_d1   <= 1'b0;
            step_trigger_d2   <= 1'b0;
            is_stall_sample   <= 1'b0;
            is_dcache_sample  <= 1'b0;
            pc_sample         <= 32'd0;
            inst_sample       <= 32'd0;
            step_pending      <= 1'b0;
            pending_is_stall  <= 1'b0;
            pending_is_dcache <= 1'b0;
            pending_pc        <= 32'd0;
            pending_inst      <= 32'd0;
        end else begin
            step_trigger_d1 <= step_trigger;
            step_trigger_d2 <= step_trigger_d1;

            // Sample 1 cycle after core clock pulse, allowing all pipeline flip-flops,
            // memories, hazard detection, and cache hit/miss logic to settle completely!
            if (step_trigger_d1) begin
                is_stall_sample  <= (hazard_stall || dcache_stall);
                is_dcache_sample <= dcache_stall;
                pc_sample        <= fetch_pc;
                inst_sample      <= fetch_inst;
            end

            // When step has fully settled, trigger or queue telemetry
            if (step_trigger_d2 && banner_done && init_pc_sent) begin
                if (telem_active) begin
                    step_pending      <= 1'b1;
                    pending_is_stall  <= is_stall_sample;
                    pending_is_dcache <= is_dcache_sample;
                    pending_pc        <= pc_sample;
                    pending_inst      <= inst_sample;
                end
            end else if (!telem_active && step_pending) begin
                step_pending <= 1'b0;
            end
        end
    end

    // Telemetry trigger condition
    wire init_trigger = banner_done && !init_pc_sent && !telem_active && (fifo_count < FIFO_DEPTH - 2);
    wire direct_step  = step_trigger_d2 && banner_done && init_pc_sent && !telem_active;
    wire queued_step  = !telem_active && step_pending && banner_done && init_pc_sent && (fifo_count < FIFO_DEPTH - 2);

    wire [5:0] telem_max_idx = (snap_is_stall) ? 6'd33 : 6'd34;

    reg snap_is_dcache;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            telem_active   <= 1'b0;
            telem_idx      <= 6'd0;
            snap_is_stall  <= 1'b0;
            snap_is_dcache <= 1'b0;
            snap_pc        <= 32'd0;
            snap_inst      <= 32'd0;
            init_pc_sent   <= 1'b0;
        end else begin
            if (init_trigger) begin
                // Stream initial PC 0x00000000 right after boot banner
                telem_active   <= 1'b1;
                telem_idx      <= 6'd0;
                snap_is_stall  <= 1'b0;
                snap_is_dcache <= 1'b0;
                snap_pc        <= fetch_pc;
                snap_inst      <= fetch_inst;
                init_pc_sent   <= 1'b1;
            end else if (direct_step) begin
                // Stream on immediate step trigger
                telem_active   <= 1'b1;
                telem_idx      <= 6'd0;
                snap_is_stall  <= is_stall_sample;
                snap_is_dcache <= is_dcache_sample;
                snap_pc        <= pc_sample;
                snap_inst      <= inst_sample;
            end else if (queued_step) begin
                // Stream queued step if previous line was still serializing
                telem_active   <= 1'b1;
                telem_idx      <= 6'd0;
                snap_is_stall  <= pending_is_stall;
                snap_is_dcache <= pending_is_dcache;
                snap_pc        <= pending_pc;
                snap_inst      <= pending_inst;
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
            // Output: "---------stall--------- [DCACHE]\r\n" or "---------stall--------- [HAZARD]\r\n" (34 bytes)
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
                6'd23: telem_char = " ";
                6'd24: telem_char = "[";
                6'd25: telem_char = snap_is_dcache ? "D" : "H";
                6'd26: telem_char = snap_is_dcache ? "C" : "A";
                6'd27: telem_char = snap_is_dcache ? "A" : "Z";
                6'd28: telem_char = snap_is_dcache ? "C" : "A";
                6'd29: telem_char = snap_is_dcache ? "H" : "R";
                6'd30: telem_char = snap_is_dcache ? "E" : "D";
                6'd31: telem_char = "]";
                6'd32: telem_char = 8'h0D; // \r
                6'd33: telem_char = 8'h0A; // \n
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

    // ========================================================================
    // 6. Post-Run Execution & Cache Performance Summary Streamer
    // ========================================================================
    localparam SUMMARY_LEN = 388;
    reg [9:0] summary_idx;
    reg       summary_done;
    reg [31:0] snap_cycles;
    reg [31:0] snap_insts;
    reg [31:0] snap_hits;
    reg [31:0] snap_misses;
    reg [31:0] snap_result;
    reg        snap_bypass;

    wire summary_trigger = (prog_done === 1'b1) && banner_done && init_pc_sent &&
                           !telem_active && !step_pending && !summary_active && !summary_done;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            summary_idx    <= 10'd0;
            summary_active <= 1'b0;
            summary_done   <= 1'b0;
            snap_cycles    <= 32'd0;
            snap_insts     <= 32'd0;
            snap_hits      <= 32'd0;
            snap_misses    <= 32'd0;
            snap_result    <= 32'd0;
            snap_bypass    <= 1'b0;
        end else begin
            if (summary_trigger) begin
                summary_active <= 1'b1;
                summary_idx    <= 10'd0;
                snap_cycles    <= stat_cycles;
                snap_insts     <= stat_insts;
                snap_hits      <= stat_hits;
                snap_misses    <= stat_misses;
                snap_result    <= stat_result;
                snap_bypass    <= (dcache_bypass === 1'b1);
            end else if (summary_active && (fifo_count < FIFO_DEPTH - 2)) begin
                if (summary_idx < SUMMARY_LEN - 1) begin
                    summary_idx <= summary_idx + 10'd1;
                end else begin
                    summary_active <= 1'b0;
                    summary_done   <= 1'b1;
                end
            end
        end
    end

    reg [7:0] summary_char;
    always @(*) begin
        case (summary_idx)
            // Offset 0..53: "\r\n==================================================\r\n"
            10'd0:  summary_char = 8'h0D;
            10'd1:  summary_char = 8'h0A;
            10'd2, 10'd3, 10'd4, 10'd5, 10'd6, 10'd7, 10'd8, 10'd9,
            10'd10, 10'd11, 10'd12, 10'd13, 10'd14, 10'd15, 10'd16, 10'd17, 10'd18, 10'd19,
            10'd20, 10'd21, 10'd22, 10'd23, 10'd24, 10'd25, 10'd26, 10'd27, 10'd28, 10'd29,
            10'd30, 10'd31, 10'd32, 10'd33, 10'd34, 10'd35, 10'd36, 10'd37, 10'd38, 10'd39,
            10'd40, 10'd41, 10'd42, 10'd43, 10'd44, 10'd45, 10'd46, 10'd47, 10'd48, 10'd49,
            10'd50, 10'd51: summary_char = "=";
            10'd52: summary_char = 8'h0D;
            10'd53: summary_char = 8'h0A;

            // Offset 54..89: "   D-CACHE EXECUTION SUMMARY (MODE: " (36 chars)
            10'd54, 10'd55, 10'd56: summary_char = " ";
            10'd57: summary_char = "D";
            10'd58: summary_char = "-";
            10'd59: summary_char = "C";
            10'd60: summary_char = "A";
            10'd61: summary_char = "C";
            10'd62: summary_char = "H";
            10'd63: summary_char = "E";
            10'd64: summary_char = " ";
            10'd65: summary_char = "E";
            10'd66: summary_char = "X";
            10'd67: summary_char = "E";
            10'd68: summary_char = "C";
            10'd69: summary_char = "U";
            10'd70: summary_char = "T";
            10'd71: summary_char = "I";
            10'd72: summary_char = "O";
            10'd73: summary_char = "N";
            10'd74: summary_char = " ";
            10'd75: summary_char = "S";
            10'd76: summary_char = "U";
            10'd77: summary_char = "M";
            10'd78: summary_char = "M";
            10'd79: summary_char = "A";
            10'd80: summary_char = "R";
            10'd81: summary_char = "Y";
            10'd82: summary_char = " ";
            10'd83: summary_char = "(";
            10'd84: summary_char = "M";
            10'd85: summary_char = "O";
            10'd86: summary_char = "D";
            10'd87: summary_char = "E";
            10'd88: summary_char = ":";
            10'd89: summary_char = " ";

            // Offset 90..103: "ENABLED )   \r\n" or "BYPASSED)   \r\n" (14 chars)
            10'd90: summary_char = snap_bypass ? "B" : "E";
            10'd91: summary_char = snap_bypass ? "Y" : "N";
            10'd92: summary_char = snap_bypass ? "P" : "A";
            10'd93: summary_char = snap_bypass ? "A" : "B";
            10'd94: summary_char = snap_bypass ? "S" : "L";
            10'd95: summary_char = snap_bypass ? "S" : "E";
            10'd96: summary_char = snap_bypass ? "E" : "D";
            10'd97: summary_char = snap_bypass ? "D" : " ";
            10'd98: summary_char = ")";
            10'd99, 10'd100, 10'd101: summary_char = " ";
            10'd102: summary_char = 8'h0D;
            10'd103: summary_char = 8'h0A;

            // Offset 104..155: "==================================================\r\n" (52 chars)
            10'd104, 10'd105, 10'd106, 10'd107, 10'd108, 10'd109,
            10'd110, 10'd111, 10'd112, 10'd113, 10'd114, 10'd115, 10'd116, 10'd117, 10'd118, 10'd119,
            10'd120, 10'd121, 10'd122, 10'd123, 10'd124, 10'd125, 10'd126, 10'd127, 10'd128, 10'd129,
            10'd130, 10'd131, 10'd132, 10'd133, 10'd134, 10'd135, 10'd136, 10'd137, 10'd138, 10'd139,
            10'd140, 10'd141, 10'd142, 10'd143, 10'd144, 10'd145, 10'd146, 10'd147, 10'd148, 10'd149,
            10'd150, 10'd151, 10'd152, 10'd153: summary_char = "=";
            10'd154: summary_char = 8'h0D;
            10'd155: summary_char = 8'h0A;

            // Offset 156..191: " Instructions Retired : 0x" (26 chars) + 8 hex digits + "\r\n"
            10'd156: summary_char = " ";
            10'd157: summary_char = "I";
            10'd158: summary_char = "n";
            10'd159: summary_char = "s";
            10'd160: summary_char = "t";
            10'd161: summary_char = "r";
            10'd162: summary_char = "u";
            10'd163: summary_char = "c";
            10'd164: summary_char = "t";
            10'd165: summary_char = "i";
            10'd166: summary_char = "o";
            10'd167: summary_char = "n";
            10'd168: summary_char = "s";
            10'd169: summary_char = " ";
            10'd170: summary_char = "R";
            10'd171: summary_char = "e";
            10'd172: summary_char = "t";
            10'd173: summary_char = "i";
            10'd174: summary_char = "r";
            10'd175: summary_char = "e";
            10'd176: summary_char = "d";
            10'd177: summary_char = " ";
            10'd178: summary_char = ":";
            10'd179: summary_char = " ";
            10'd180: summary_char = "0";
            10'd181: summary_char = "x";
            10'd182: summary_char = to_hex(snap_insts[31:28]);
            10'd183: summary_char = to_hex(snap_insts[27:24]);
            10'd184: summary_char = to_hex(snap_insts[23:20]);
            10'd185: summary_char = to_hex(snap_insts[19:16]);
            10'd186: summary_char = to_hex(snap_insts[15:12]);
            10'd187: summary_char = to_hex(snap_insts[11:8]);
            10'd188: summary_char = to_hex(snap_insts[7:4]);
            10'd189: summary_char = to_hex(snap_insts[3:0]);
            10'd190: summary_char = 8'h0D;
            10'd191: summary_char = 8'h0A;

            // Offset 192..227: " Total Clock Cycles   : 0x" (26 chars) + 8 hex digits + "\r\n"
            10'd192: summary_char = " ";
            10'd193: summary_char = "T";
            10'd194: summary_char = "o";
            10'd195: summary_char = "t";
            10'd196: summary_char = "a";
            10'd197: summary_char = "l";
            10'd198: summary_char = " ";
            10'd199: summary_char = "C";
            10'd200: summary_char = "l";
            10'd201: summary_char = "o";
            10'd202: summary_char = "c";
            10'd203: summary_char = "k";
            10'd204: summary_char = " ";
            10'd205: summary_char = "C";
            10'd206: summary_char = "y";
            10'd207: summary_char = "c";
            10'd208: summary_char = "l";
            10'd209: summary_char = "e";
            10'd210: summary_char = "s";
            10'd211, 10'd212, 10'd213: summary_char = " ";
            10'd214: summary_char = ":";
            10'd215: summary_char = " ";
            10'd216: summary_char = "0";
            10'd217: summary_char = "x";
            10'd218: summary_char = to_hex(snap_cycles[31:28]);
            10'd219: summary_char = to_hex(snap_cycles[27:24]);
            10'd220: summary_char = to_hex(snap_cycles[23:20]);
            10'd221: summary_char = to_hex(snap_cycles[19:16]);
            10'd222: summary_char = to_hex(snap_cycles[15:12]);
            10'd223: summary_char = to_hex(snap_cycles[11:8]);
            10'd224: summary_char = to_hex(snap_cycles[7:4]);
            10'd225: summary_char = to_hex(snap_cycles[3:0]);
            10'd226: summary_char = 8'h0D;
            10'd227: summary_char = 8'h0A;

            // Offset 228..263: " L1 D-Cache Hits      : 0x" (26 chars) + 8 hex digits + "\r\n"
            10'd228: summary_char = " ";
            10'd229: summary_char = "L";
            10'd230: summary_char = "1";
            10'd231: summary_char = " ";
            10'd232: summary_char = "D";
            10'd233: summary_char = "-";
            10'd234: summary_char = "C";
            10'd235: summary_char = "a";
            10'd236: summary_char = "c";
            10'd237: summary_char = "h";
            10'd238: summary_char = "e";
            10'd239: summary_char = " ";
            10'd240: summary_char = "H";
            10'd241: summary_char = "i";
            10'd242: summary_char = "t";
            10'd243: summary_char = "s";
            10'd244, 10'd245, 10'd246, 10'd247, 10'd248, 10'd249: summary_char = " ";
            10'd250: summary_char = ":";
            10'd251: summary_char = " ";
            10'd252: summary_char = "0";
            10'd253: summary_char = "x";
            10'd254: summary_char = to_hex(snap_hits[31:28]);
            10'd255: summary_char = to_hex(snap_hits[27:24]);
            10'd256: summary_char = to_hex(snap_hits[23:20]);
            10'd257: summary_char = to_hex(snap_hits[19:16]);
            10'd258: summary_char = to_hex(snap_hits[15:12]);
            10'd259: summary_char = to_hex(snap_hits[11:8]);
            10'd260: summary_char = to_hex(snap_hits[7:4]);
            10'd261: summary_char = to_hex(snap_hits[3:0]);
            10'd262: summary_char = 8'h0D;
            10'd263: summary_char = 8'h0A;

            // Offset 264..299: " L1 D-Cache Misses    : 0x" (26 chars) + 8 hex digits + "\r\n"
            10'd264: summary_char = " ";
            10'd265: summary_char = "L";
            10'd266: summary_char = "1";
            10'd267: summary_char = " ";
            10'd268: summary_char = "D";
            10'd269: summary_char = "-";
            10'd270: summary_char = "C";
            10'd271: summary_char = "a";
            10'd272: summary_char = "c";
            10'd273: summary_char = "h";
            10'd274: summary_char = "e";
            10'd275: summary_char = " ";
            10'd276: summary_char = "M";
            10'd277: summary_char = "i";
            10'd278: summary_char = "s";
            10'd279: summary_char = "s";
            10'd280: summary_char = "e";
            10'd281: summary_char = "s";
            10'd282, 10'd283, 10'd284, 10'd285: summary_char = " ";
            10'd286: summary_char = ":";
            10'd287: summary_char = " ";
            10'd288: summary_char = "0";
            10'd289: summary_char = "x";
            10'd290: summary_char = to_hex(snap_misses[31:28]);
            10'd291: summary_char = to_hex(snap_misses[27:24]);
            10'd292: summary_char = to_hex(snap_misses[23:20]);
            10'd293: summary_char = to_hex(snap_misses[19:16]);
            10'd294: summary_char = to_hex(snap_misses[15:12]);
            10'd295: summary_char = to_hex(snap_misses[11:8]);
            10'd296: summary_char = to_hex(snap_misses[7:4]);
            10'd297: summary_char = to_hex(snap_misses[3:0]);
            10'd298: summary_char = 8'h0D;
            10'd299: summary_char = 8'h0A;

            // Offset 300..335: " Final Return Value a0: 0x" (26 chars) + 8 hex digits + "\r\n"
            10'd300: summary_char = " ";
            10'd301: summary_char = "F";
            10'd302: summary_char = "i";
            10'd303: summary_char = "n";
            10'd304: summary_char = "a";
            10'd305: summary_char = "l";
            10'd306: summary_char = " ";
            10'd307: summary_char = "R";
            10'd308: summary_char = "e";
            10'd309: summary_char = "t";
            10'd310: summary_char = "u";
            10'd311: summary_char = "r";
            10'd312: summary_char = "n";
            10'd313: summary_char = " ";
            10'd314: summary_char = "V";
            10'd315: summary_char = "a";
            10'd316: summary_char = "l";
            10'd317: summary_char = "u";
            10'd318: summary_char = "e";
            10'd319: summary_char = " ";
            10'd320: summary_char = "a";
            10'd321: summary_char = "0";
            10'd322: summary_char = ":";
            10'd323: summary_char = " ";
            10'd324: summary_char = "0";
            10'd325: summary_char = "x";
            10'd326: summary_char = to_hex(snap_result[31:28]);
            10'd327: summary_char = to_hex(snap_result[27:24]);
            10'd328: summary_char = to_hex(snap_result[23:20]);
            10'd329: summary_char = to_hex(snap_result[19:16]);
            10'd330: summary_char = to_hex(snap_result[15:12]);
            10'd331: summary_char = to_hex(snap_result[11:8]);
            10'd332: summary_char = to_hex(snap_result[7:4]);
            10'd333: summary_char = to_hex(snap_result[3:0]);
            10'd334: summary_char = 8'h0D;
            10'd335: summary_char = 8'h0A;

            // Offset 336..387: "==================================================\r\n" (52 chars)
            10'd336, 10'd337, 10'd338, 10'd339,
            10'd340, 10'd341, 10'd342, 10'd343, 10'd344, 10'd345, 10'd346, 10'd347, 10'd348, 10'd349,
            10'd350, 10'd351, 10'd352, 10'd353, 10'd354, 10'd355, 10'd356, 10'd357, 10'd358, 10'd359,
            10'd360, 10'd361, 10'd362, 10'd363, 10'd364, 10'd365, 10'd366, 10'd367, 10'd368, 10'd369,
            10'd370, 10'd371, 10'd372, 10'd373, 10'd374, 10'd375, 10'd376, 10'd377, 10'd378, 10'd379,
            10'd380, 10'd381, 10'd382, 10'd383, 10'd384, 10'd385: summary_char = "=";
            10'd386: summary_char = 8'h0D;
            10'd387: summary_char = 8'h0A;
            default: summary_char = " ";
        endcase
    end

    assign summary_wr_en = summary_active && (fifo_count < FIFO_DEPTH - 2);
    assign summary_wdata = summary_char;

endmodule
