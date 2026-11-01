// ============================================================================
// File: icache_uart_printer.v
// Module: icache_uart_printer
// Description: Post-Run Formatted UART Telemetry Streamer for I-Cache Verification
//              Supports:
//              1. Synthetic JAL Benchmark Trace Table, Summary, and Comparison Table
//              2. Bare-Metal C Program (icache.c) Trace Table & Verification Summary
// Project: RV32IMF Core with L1 I-Cache (Feature 6)
// ============================================================================

`timescale 1ns/1ps

module icache_uart_printer #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  wire        clk,
    input  wire        reset_n,

    // Trigger & Mode Info (Synthetic Benchmark)
    input  wire        start_print,        // Pulse to start continuous benchmark UART dump
    input  wire        print_banner_only,  // Pulse to print banner header only (Step mode)
    input  wire        print_single_row,   // Pulse to print a single row immediately (Step mode)
    input  wire [7:0]  single_row_addr,    // Target trace address for single row
    input  wire        print_summary_only, // Pulse to print summary after step mode halt
    input  wire        mode_bypassed,      // 0: Enabled (SW0=0), 1: Bypassed (SW0=1)
    input  wire [7:0]  trace_len,          // Total entries in trace buffer

    // Trace Buffer Read Interface
    output reg  [7:0]  trace_rd_addr,
    input  wire [83:0] trace_rd_data,     // {status_code[3:0], cyc[15:0], pc[31:0], inst[31:0]}

    // Active Run Stats (Benchmark)
    input  wire [15:0] stat_instructions,
    input  wire [15:0] stat_cycles,
    input  wire [15:0] stat_hits,
    input  wire [15:0] stat_misses,

    // Persistent Historical Stats for Comparison
    input  wire        mode0_valid,
    input  wire [15:0] mode0_instructions,
    input  wire [15:0] mode0_cycles,
    input  wire [15:0] mode0_hits,
    input  wire [15:0] mode0_misses,

    input  wire        mode1_valid,
    input  wire [15:0] mode1_instructions,
    input  wire [15:0] mode1_cycles,
    input  wire [15:0] mode1_hits,
    input  wire [15:0] mode1_misses,

    // Bare-Metal C Program Telemetry Ports
    input  wire        start_print_c,
    input  wire [15:0] c_stat_instructions,
    input  wire [15:0] c_stat_cycles,
    input  wire [15:0] c_stat_hits,
    input  wire [15:0] c_stat_misses,
    input  wire [15:0] c_stat_return_val,
    input  wire [7:0]  c_trace_len,

    // UART Physical Output
    output wire        uart_tx,
    output wire        print_busy,
    output reg         print_done
);

    // ------------------------------------------------------------------------
    // Physical UART Transmitter Instance
    // ------------------------------------------------------------------------
    reg        tx_start;
    reg  [7:0] tx_data;
    wire       tx_busy;

    uart_tx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart_tx (
        .clk      (clk),
        .reset_n  (reset_n),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx       (uart_tx),
        .tx_busy  (tx_busy)
    );

    // ------------------------------------------------------------------------
    // Number Formatting Functions
    // ------------------------------------------------------------------------
    function [7:0] to_hex(input [3:0] n);
        to_hex = (n < 4'd10) ? (8'h30 + {4'b0, n}) : (8'h41 + {4'b0, n} - 8'd10);
    endfunction

    function [7:0] dec_digit(input [15:0] val, input [1:0] pos);
        reg [15:0] d;
        begin
            case (pos)
                2'd3: d = (val / 1000) % 10;
                2'd2: d = (val / 100) % 10;
                2'd1: d = (val / 10) % 10;
                default: d = val % 10;
            endcase
            dec_digit = 8'h30 + d[7:0];
        end
    endfunction

    function [7:0] dec_space_digit(input [15:0] val, input [1:0] pos);
        begin
            if (pos == 2'd3 && val < 1000)
                dec_space_digit = " ";
            else if (pos == 2'd2 && val < 100)
                dec_space_digit = " ";
            else if (pos == 2'd1 && val < 10)
                dec_space_digit = " ";
            else
                dec_space_digit = dec_digit(val, pos);
        end
    endfunction

    function [7:0] dec2_space(input [15:0] val, input pos);
        begin
            if (pos == 1'b1 && val < 10)
                dec2_space = " ";
            else if (pos == 1'b1)
                dec2_space = 8'h30 + ((val / 10) % 10);
            else
                dec2_space = 8'h30 + (val % 10);
        end
    endfunction

    // ------------------------------------------------------------------------
    // Performance Metric Calculations
    // ------------------------------------------------------------------------
    wire [31:0] cur_tot_access = stat_hits + stat_misses;
    wire [31:0] cur_rate_x10   = (cur_tot_access > 0) ? ((stat_hits * 1000) / cur_tot_access) : 0;
    wire [31:0] cur_cpi_x100   = (stat_instructions > 0) ? ((stat_cycles * 100) / stat_instructions) : 0;

    wire [31:0] m0_tot_access  = mode0_hits + mode0_misses;
    wire [31:0] m0_rate_x10    = (m0_tot_access > 0) ? ((mode0_hits * 1000) / m0_tot_access) : 0;
    wire [31:0] m0_cpi_x100    = (mode0_instructions > 0) ? ((mode0_cycles * 100) / mode0_instructions) : 0;

    wire [31:0] m1_tot_access  = mode1_hits + mode1_misses;
    wire [31:0] m1_rate_x10    = (m1_tot_access > 0) ? ((mode1_hits * 1000) / m1_tot_access) : 0;
    wire [31:0] m1_cpi_x100    = (mode1_instructions > 0) ? ((mode1_cycles * 100) / mode1_instructions) : 0;

    wire [31:0] speedup_x100   = (mode0_cycles > 0) ? ((mode1_cycles * 100) / mode0_cycles) : 0;

    // C Program metrics
    wire [31:0] c_tot_access   = c_stat_hits + c_stat_misses;
    wire [31:0] c_rate_x10     = (c_tot_access > 0) ? ((c_stat_hits * 1000) / c_tot_access) : 0;
    wire [31:0] c_cpi_x100     = (c_stat_instructions > 0) ? ((c_stat_cycles * 100) / c_stat_instructions) : 0;

    // Unpack current trace entry
    wire [3:0]  row_status = trace_rd_data[83:80];
    wire [15:0] row_cyc    = trace_rd_data[79:64];
    wire [31:0] row_pc     = trace_rd_data[63:32];
    wire [31:0] row_inst   = trace_rd_data[31:0];

    // FSM States
    localparam S_IDLE      = 4'd0;
    localparam S_BANNER    = 4'd1;
    localparam S_ROW       = 4'd2;
    localparam S_SUMMARY   = 4'd3;
    localparam S_COMPARE   = 4'd4;
    localparam S_DONE      = 4'd5;
    localparam S_C_BANNER  = 4'd6;
    localparam S_C_ROW     = 4'd7;
    localparam S_C_SUMMARY = 4'd8;

    reg [3:0] state;
    reg [3:0] sub_step;
    reg [6:0] char_idx;
    reg [7:0] current_row;
    reg       is_step_op;

    assign print_busy = (state != S_IDLE);

    // ------------------------------------------------------------------------
    // Combinational Character Generator
    // ------------------------------------------------------------------------
    reg [7:0] cur_char;
    reg [6:0] cur_len;

    always @(*) begin
        cur_char = " ";
        cur_len  = 7'd0;

        case (state)
            S_BANNER: begin
                case (sub_step)
                    4'd0: begin // \r\n (2)
                        cur_len = 7'd2;
                        cur_char = (char_idx == 0) ? 8'h0D : 8'h0A;
                    end

                    4'd1, 4'd3: begin // ============================================================\r\n (62)
                        cur_len = 7'd62;
                        if (char_idx < 60) cur_char = "=";
                        else if (char_idx == 60) cur_char = 8'h0D;
                        else cur_char = 8'h0A;
                    end

                    4'd2: begin // Title (50 or 51)
                        if (!mode_bypassed) begin
                            cur_len = 7'd50;
                            case (char_idx)
                                0,1: cur_char = " ";
                                2: cur_char = "I"; 3: cur_char = "-"; 4: cur_char = "C"; 5: cur_char = "A";
                                6: cur_char = "C"; 7: cur_char = "H"; 8: cur_char = "E"; 9: cur_char = " ";
                                10: cur_char = "T"; 11: cur_char = "R"; 12: cur_char = "A"; 13: cur_char = "C"; 14: cur_char = "E";
                                15: cur_char = " "; 16: cur_char = "("; 17: cur_char = "M"; 18: cur_char = "O"; 19: cur_char = "D"; 20: cur_char = "E";
                                21: cur_char = ":"; 22: cur_char = " "; 23: cur_char = "I"; 24: cur_char = "-"; 25: cur_char = "C"; 26: cur_char = "A";
                                27: cur_char = "C"; 28: cur_char = "H"; 29: cur_char = "E"; 30: cur_char = " ";
                                31: cur_char = "E"; 32: cur_char = "N"; 33: cur_char = "A"; 34: cur_char = "B"; 35: cur_char = "L"; 36: cur_char = "E"; 37: cur_char = "D";
                                38: cur_char = " "; 39: cur_char = "["; 40: cur_char = "S"; 41: cur_char = "W"; 42: cur_char = "0"; 43: cur_char = "="; 44: cur_char = "0"; 45: cur_char = "]";
                                46: cur_char = ")"; 47: cur_char = " "; 48: cur_char = 8'h0D; 49: cur_char = 8'h0A;
                                default: cur_char = " ";
                            endcase
                        end else begin
                            cur_len = 7'd51;
                            case (char_idx)
                                0,1: cur_char = " ";
                                2: cur_char = "I"; 3: cur_char = "-"; 4: cur_char = "C"; 5: cur_char = "A";
                                6: cur_char = "C"; 7: cur_char = "H"; 8: cur_char = "E"; 9: cur_char = " ";
                                10: cur_char = "T"; 11: cur_char = "R"; 12: cur_char = "A"; 13: cur_char = "C"; 14: cur_char = "E";
                                15: cur_char = " "; 16: cur_char = "("; 17: cur_char = "M"; 18: cur_char = "O"; 19: cur_char = "D"; 20: cur_char = "E";
                                21: cur_char = ":"; 22: cur_char = " "; 23: cur_char = "I"; 24: cur_char = "-"; 25: cur_char = "C"; 26: cur_char = "A";
                                27: cur_char = "C"; 28: cur_char = "H"; 29: cur_char = "E"; 30: cur_char = " ";
                                31: cur_char = "B"; 32: cur_char = "Y"; 33: cur_char = "P"; 34: cur_char = "A"; 35: cur_char = "S"; 36: cur_char = "S"; 37: cur_char = "E"; 38: cur_char = "D";
                                39: cur_char = " "; 40: cur_char = "["; 41: cur_char = "S"; 42: cur_char = "W"; 43: cur_char = "0"; 44: cur_char = "="; 45: cur_char = "1"; 46: cur_char = "]";
                                47: cur_char = ")"; 48: cur_char = " "; 49: cur_char = 8'h0D; 50: cur_char = 8'h0A;
                                default: cur_char = " ";
                            endcase
                        end
                    end

                    4'd4: begin // "     CYC   PC           INSTR               STATUS\r\n" (52)
                        cur_len = 7'd52;
                        case (char_idx)
                            0,1,2,3,4: cur_char = " ";
                            5: cur_char = "C"; 6: cur_char = "Y"; 7: cur_char = "C";
                            8,9,10: cur_char = " ";
                            11: cur_char = "P"; 12: cur_char = "C";
                            13,14,15,16,17,18,19,20,21,22,23: cur_char = " ";
                            24: cur_char = "I"; 25: cur_char = "N"; 26: cur_char = "S"; 27: cur_char = "T"; 28: cur_char = "R";
                            29,30,31,32,33,34,35,36,37,38,39,40,41,42,43: cur_char = " ";
                            44: cur_char = "S"; 45: cur_char = "T"; 46: cur_char = "A"; 47: cur_char = "T"; 48: cur_char = "U"; 49: cur_char = "S";
                            50: cur_char = 8'h0D; 51: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd5: begin // ------------------------------------------------------------\r\n (62)
                        cur_len = 7'd62;
                        if (char_idx < 60) cur_char = "-";
                        else if (char_idx == 60) cur_char = 8'h0D;
                        else cur_char = 8'h0A;
                    end
                endcase
            end

            S_ROW, S_C_ROW: begin
                if (row_status == 4'd11) begin
                    // "     FLUSH  PC=0x00000014   (jal PC + 4)\r\n" (42 chars)
                    cur_len = 7'd42;
                    case (char_idx)
                        0,1,2,3,4: cur_char = " ";
                        5: cur_char = "F"; 6: cur_char = "L"; 7: cur_char = "U"; 8: cur_char = "S"; 9: cur_char = "H";
                        10,11: cur_char = " ";
                        12: cur_char = "P"; 13: cur_char = "C"; 14: cur_char = "="; 15: cur_char = "0"; 16: cur_char = "x";
                        17: cur_char = to_hex(row_pc[31:28]); 18: cur_char = to_hex(row_pc[27:24]);
                        19: cur_char = to_hex(row_pc[23:20]); 20: cur_char = to_hex(row_pc[19:16]);
                        21: cur_char = to_hex(row_pc[15:12]); 22: cur_char = to_hex(row_pc[11:8]);
                        23: cur_char = to_hex(row_pc[7:4]);   24: cur_char = to_hex(row_pc[3:0]);
                        25,26,27: cur_char = " ";
                        28: cur_char = "("; 29: cur_char = "j"; 30: cur_char = "a"; 31: cur_char = "l"; 32: cur_char = " ";
                        33: cur_char = "P"; 34: cur_char = "C"; 35: cur_char = " "; 36: cur_char = "+"; 37: cur_char = " ";
                        38: cur_char = "4"; 39: cur_char = ")"; 40: cur_char = 8'h0D; 41: cur_char = 8'h0A;
                        default: cur_char = " ";
                    endcase
                end else begin
                    // Row with CYC, PC, INSTR, STATUS
                    if (row_status == 4'd0) cur_len = 7'd59;           // HIT
                    else if (row_status == 4'd10) cur_len = 7'd77;     // FETCHED
                    else cur_len = 7'd63;                              // MISS / STALL

                    case (char_idx)
                        0,1,2,3: cur_char = " ";
                        4: cur_char = dec_space_digit(row_cyc, 2'd3);
                        5: cur_char = dec_space_digit(row_cyc, 2'd2);
                        6: cur_char = dec_space_digit(row_cyc, 2'd1);
                        7: cur_char = dec_space_digit(row_cyc, 2'd0);
                        8,9,10: cur_char = " ";
                        11: cur_char = "0"; 12: cur_char = "x";
                        13: cur_char = to_hex(row_pc[31:28]); 14: cur_char = to_hex(row_pc[27:24]);
                        15: cur_char = to_hex(row_pc[23:20]); 16: cur_char = to_hex(row_pc[19:16]);
                        17: cur_char = to_hex(row_pc[15:12]); 18: cur_char = to_hex(row_pc[11:8]);
                        19: cur_char = to_hex(row_pc[7:4]);   20: cur_char = to_hex(row_pc[3:0]);
                        21,22,23: cur_char = " ";
                        24: cur_char = "0"; 25: cur_char = "x";
                        26: cur_char = to_hex(row_inst[31:28]); 27: cur_char = to_hex(row_inst[27:24]);
                        28: cur_char = to_hex(row_inst[23:20]); 29: cur_char = to_hex(row_inst[19:16]);
                        30: cur_char = to_hex(row_inst[15:12]); 31: cur_char = to_hex(row_inst[11:8]);
                        32: cur_char = to_hex(row_inst[7:4]);   33: cur_char = to_hex(row_inst[3:0]);
                        34,35,36,37,38,39,40,41,42,43: cur_char = " ";

                        // Status Column:
                        44: cur_char = (row_status == 4'd0) ? "H" :
                                       (row_status == 4'd1) ? "M" :
                                       (row_status == 4'd10) ? "F" : "S";
                        45: cur_char = (row_status == 4'd0) ? "I" :
                                       (row_status == 4'd1) ? "I" :
                                       (row_status == 4'd10) ? "E" : "T";
                        46: cur_char = (row_status == 4'd0) ? "T" :
                                       (row_status == 4'd1) ? "S" :
                                       (row_status == 4'd10) ? "T" : "A";
                        47: cur_char = (row_status == 4'd0) ? " " :
                                       (row_status == 4'd1) ? "S" :
                                       (row_status == 4'd10) ? "C" : "L";
                        48: cur_char = (row_status == 4'd0) ? " " :
                                       (row_status == 4'd1) ? " " :
                                       (row_status == 4'd10) ? "H" : "L";
                        49: cur_char = (row_status == 4'd0) ? " " :
                                       (row_status == 4'd1) ? " " :
                                       (row_status == 4'd10) ? "E" : " ";
                        50: cur_char = (row_status == 4'd0) ? " " :
                                       (row_status == 4'd1) ? "(" :
                                       (row_status == 4'd10) ? "D" : "(";
                        51: cur_char = (row_status == 4'd0) ? " " :
                                       (row_status == 4'd10) ? " " : "s";
                        52: cur_char = (row_status == 4'd0) ? " " :
                                       (row_status == 4'd10) ? "(" : "t";
                        53: cur_char = (row_status == 4'd0) ? " " :
                                       (row_status == 4'd10) ? "i" : "a";
                        54: cur_char = (row_status == 4'd0) ? " " :
                                       (row_status == 4'd10) ? "n" : "l";
                        55: cur_char = (row_status == 4'd0) ? " " :
                                       (row_status == 4'd10) ? "s" : "l";
                        56: cur_char = (row_status == 4'd0) ? " " :
                                       (row_status == 4'd10) ? "t" : " ";
                        57: cur_char = (row_status == 4'd0) ? 8'h0D :
                                       (row_status == 4'd1) ? "1" :
                                       (row_status == 4'd10) ? "r" : (8'h30 + row_status);
                        58: cur_char = (row_status == 4'd0) ? 8'h0A :
                                       (row_status == 4'd10) ? "u" : "/";
                        59: cur_char = (row_status == 4'd10) ? "c" : "9";
                        60: cur_char = (row_status == 4'd10) ? "t" : ")";
                        61: cur_char = (row_status == 4'd10) ? "i" : 8'h0D;
                        62: cur_char = (row_status == 4'd10) ? "o" : 8'h0A;
                        63: cur_char = "n"; 64: cur_char = " ";
                        65: cur_char = "d"; 66: cur_char = "e"; 67: cur_char = "l"; 68: cur_char = "i";
                        69: cur_char = "v"; 70: cur_char = "e"; 71: cur_char = "r"; 72: cur_char = "e";
                        73: cur_char = "d"; 74: cur_char = ")"; 75: cur_char = 8'h0D; 76: cur_char = 8'h0A;
                        default: cur_char = " ";
                    endcase
                end
            end

            S_SUMMARY: begin
                case (sub_step)
                    4'd0: begin // ------------------------------------------------------------\r\n (62)
                        cur_len = 7'd62;
                        if (char_idx < 60) cur_char = "-";
                        else if (char_idx == 60) cur_char = 8'h0D;
                        else cur_char = 8'h0A;
                    end

                    4'd1, 4'd3, 4'd10: begin // ============================================================\r\n (62)
                        cur_len = 7'd62;
                        if (char_idx < 60) cur_char = "=";
                        else if (char_idx == 60) cur_char = 8'h0D;
                        else cur_char = 8'h0A;
                    end

                    4'd2: begin // "                   MODE EXECUTION SUMMARY\r\n" (43)
                        cur_len = 7'd43;
                        case (char_idx)
                            0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18: cur_char = " ";
                            19: cur_char = "M"; 20: cur_char = "O"; 21: cur_char = "D"; 22: cur_char = "E";
                            23: cur_char = " "; 24: cur_char = "E"; 25: cur_char = "X"; 26: cur_char = "E"; 27: cur_char = "C"; 28: cur_char = "U"; 29: cur_char = "T"; 30: cur_char = "I"; 31: cur_char = "O"; 32: cur_char = "N";
                            33: cur_char = " "; 34: cur_char = "S"; 35: cur_char = "U"; 36: cur_char = "M"; 37: cur_char = "M"; 38: cur_char = "A"; 39: cur_char = "R"; 40: cur_char = "Y";
                            41: cur_char = 8'h0D; 42: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd4: begin // "Total instructions : %4d\r\n" (27)
                        cur_len = 7'd27;
                        case (char_idx)
                            0: cur_char = "T"; 1: cur_char = "o"; 2: cur_char = "t"; 3: cur_char = "a"; 4: cur_char = "l";
                            5: cur_char = " "; 6: cur_char = "i"; 7: cur_char = "n"; 8: cur_char = "s"; 9: cur_char = "t";
                            10: cur_char = "r"; 11: cur_char = "u"; 12: cur_char = "c"; 13: cur_char = "t"; 14: cur_char = "i"; 15: cur_char = "o"; 16: cur_char = "n"; 17: cur_char = "s";
                            18: cur_char = " "; 19: cur_char = ":"; 20: cur_char = " ";
                            21: cur_char = dec_space_digit(stat_instructions, 2'd3);
                            22: cur_char = dec_space_digit(stat_instructions, 2'd2);
                            23: cur_char = dec_space_digit(stat_instructions, 2'd1);
                            24: cur_char = dec_space_digit(stat_instructions, 2'd0);
                            25: cur_char = 8'h0D; 26: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd5: begin // "Total clock cycles : %4d\r\n" (27)
                        cur_len = 7'd27;
                        case (char_idx)
                            0: cur_char = "T"; 1: cur_char = "o"; 2: cur_char = "t"; 3: cur_char = "a"; 4: cur_char = "l";
                            5: cur_char = " "; 6: cur_char = "c"; 7: cur_char = "l"; 8: cur_char = "o"; 9: cur_char = "c"; 10: cur_char = "k";
                            11: cur_char = " "; 12: cur_char = "c"; 13: cur_char = "y"; 14: cur_char = "c"; 15: cur_char = "l"; 16: cur_char = "e"; 17: cur_char = "s";
                            18: cur_char = " "; 19: cur_char = ":"; 20: cur_char = " ";
                            21: cur_char = dec_space_digit(stat_cycles, 2'd3);
                            22: cur_char = dec_space_digit(stat_cycles, 2'd2);
                            23: cur_char = dec_space_digit(stat_cycles, 2'd1);
                            24: cur_char = dec_space_digit(stat_cycles, 2'd0);
                            25: cur_char = 8'h0D; 26: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd6: begin // "I-cache hits       : %4d\r\n" (27)
                        cur_len = 7'd27;
                        case (char_idx)
                            0: cur_char = "I"; 1: cur_char = "-"; 2: cur_char = "c"; 3: cur_char = "a"; 4: cur_char = "c"; 5: cur_char = "h"; 6: cur_char = "e";
                            7: cur_char = " "; 8: cur_char = "h"; 9: cur_char = "i"; 10: cur_char = "t"; 11: cur_char = "s";
                            12,13,14,15,16,17,18: cur_char = " ";
                            19: cur_char = ":"; 20: cur_char = " ";
                            21: cur_char = dec_space_digit(stat_hits, 2'd3);
                            22: cur_char = dec_space_digit(stat_hits, 2'd2);
                            23: cur_char = dec_space_digit(stat_hits, 2'd1);
                            24: cur_char = dec_space_digit(stat_hits, 2'd0);
                            25: cur_char = 8'h0D; 26: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd7: begin // "I-cache misses     : %4d\r\n" (27)
                        cur_len = 7'd27;
                        case (char_idx)
                            0: cur_char = "I"; 1: cur_char = "-"; 2: cur_char = "c"; 3: cur_char = "a"; 4: cur_char = "c"; 5: cur_char = "h"; 6: cur_char = "e";
                            7: cur_char = " "; 8: cur_char = "m"; 9: cur_char = "i"; 10: cur_char = "s"; 11: cur_char = "s"; 12: cur_char = "e"; 13: cur_char = "s";
                            14,15,16,17,18: cur_char = " ";
                            19: cur_char = ":"; 20: cur_char = " ";
                            21: cur_char = dec_space_digit(stat_misses, 2'd3);
                            22: cur_char = dec_space_digit(stat_misses, 2'd2);
                            23: cur_char = dec_space_digit(stat_misses, 2'd1);
                            24: cur_char = dec_space_digit(stat_misses, 2'd0);
                            25: cur_char = 8'h0D; 26: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd8: begin // "Hit rate           : %2d.%1d %\r\n" (29)
                        cur_len = 7'd29;
                        case (char_idx)
                            0: cur_char = "H"; 1: cur_char = "i"; 2: cur_char = "t"; 3: cur_char = " "; 4: cur_char = "r"; 5: cur_char = "a"; 6: cur_char = "t"; 7: cur_char = "e";
                            8,9,10,11,12,13,14,15,16,17,18: cur_char = " ";
                            19: cur_char = ":"; 20: cur_char = " ";
                            21: cur_char = dec2_space(cur_rate_x10 / 10, 1'b1);
                            22: cur_char = dec2_space(cur_rate_x10 / 10, 1'b0);
                            23: cur_char = ".";
                            24: cur_char = 8'h30 + (cur_rate_x10 % 10);
                            25: cur_char = " "; 26: cur_char = "%"; 27: cur_char = 8'h0D; 28: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd9: begin // "Average CPI        : %2d.%02d\r\n" (28)
                        cur_len = 7'd28;
                        case (char_idx)
                            0: cur_char = "A"; 1: cur_char = "v"; 2: cur_char = "e"; 3: cur_char = "r"; 4: cur_char = "a"; 5: cur_char = "g"; 6: cur_char = "e";
                            7: cur_char = " "; 8: cur_char = "C"; 9: cur_char = "P"; 10: cur_char = "I";
                            11,12,13,14,15,16,17,18: cur_char = " ";
                            19: cur_char = ":"; 20: cur_char = " ";
                            21: cur_char = dec2_space(cur_cpi_x100 / 100, 1'b1);
                            22: cur_char = dec2_space(cur_cpi_x100 / 100, 1'b0);
                            23: cur_char = ".";
                            24: cur_char = 8'h30 + ((cur_cpi_x100 / 10) % 10);
                            25: cur_char = 8'h30 + (cur_cpi_x100 % 10);
                            26: cur_char = 8'h0D; 27: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end
                endcase
            end

            S_COMPARE: begin
                case (sub_step)
                    4'd0: begin // \r\n (2)
                        cur_len = 7'd2;
                        cur_char = (char_idx == 0) ? 8'h0D : 8'h0A;
                    end

                    4'd1, 4'd3, 4'd11, 4'd13: begin // ============================================================\r\n (62)
                        cur_len = 7'd62;
                        if (char_idx < 60) cur_char = "=";
                        else if (char_idx == 60) cur_char = 8'h0D;
                        else cur_char = 8'h0A;
                    end

                    4'd2: begin // "              I-CACHE PERFORMANCE COMPARISON SUMMARY\r\n" (54)
                        cur_len = 7'd54;
                        case (char_idx)
                            0,1,2,3,4,5,6,7,8,9,10,11,12,13: cur_char = " ";
                            14: cur_char = "I"; 15: cur_char = "-"; 16: cur_char = "C"; 17: cur_char = "A"; 18: cur_char = "C"; 19: cur_char = "H"; 20: cur_char = "E";
                            21: cur_char = " "; 22: cur_char = "P"; 23: cur_char = "E"; 24: cur_char = "R"; 25: cur_char = "F"; 26: cur_char = "O"; 27: cur_char = "R"; 28: cur_char = "M"; 29: cur_char = "A"; 30: cur_char = "N"; 31: cur_char = "C"; 32: cur_char = "E";
                            33: cur_char = " "; 34: cur_char = "C"; 35: cur_char = "O"; 36: cur_char = "M"; 37: cur_char = "P"; 38: cur_char = "A"; 39: cur_char = "R"; 40: cur_char = "I"; 41: cur_char = "S"; 42: cur_char = "O"; 43: cur_char = "N";
                            44: cur_char = " "; 45: cur_char = "S"; 46: cur_char = "U"; 47: cur_char = "M"; 48: cur_char = "M"; 49: cur_char = "A"; 50: cur_char = "R"; 51: cur_char = "Y";
                            52: cur_char = 8'h0D; 53: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd4: begin // "Metric                      Mode 0 (Enabled)    Mode 1 (Bypassed)\r\n" (59)
                        cur_len = 7'd59;
                        case (char_idx)
                            0: cur_char = "M"; 1: cur_char = "e"; 2: cur_char = "t"; 3: cur_char = "r"; 4: cur_char = "i"; 5: cur_char = "c";
                            6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27: cur_char = " ";
                            28: cur_char = "M"; 29: cur_char = "o"; 30: cur_char = "d"; 31: cur_char = "e"; 32: cur_char = " "; 33: cur_char = "0";
                            34: cur_char = " "; 35: cur_char = "("; 36: cur_char = "E"; 37: cur_char = "n"; 38: cur_char = "a"; 39: cur_char = "b"; 40: cur_char = "l"; 41: cur_char = "e"; 42: cur_char = "d"; 43: cur_char = ")";
                            44,45,46,47: cur_char = " ";
                            48: cur_char = "M"; 49: cur_char = "o"; 50: cur_char = "d"; 51: cur_char = "e"; 52: cur_char = " "; 53: cur_char = "1";
                            54: cur_char = " "; 55: cur_char = "("; 56: cur_char = "B"; 57: cur_char = "y"; 58: cur_char = "p"; 59: cur_char = "a"; 60: cur_char = "s"; 61: cur_char = "s"; 62: cur_char = "e"; 63: cur_char = "d"; 64: cur_char = ")";
                            default: cur_char = " ";
                        endcase
                        if (char_idx == 57) cur_char = 8'h0D;
                        if (char_idx == 58) cur_char = 8'h0A;
                    end

                    4'd5: begin // ------------------------------------------------------------\r\n (62)
                        cur_len = 7'd62;
                        if (char_idx < 60) cur_char = "-";
                        else if (char_idx == 60) cur_char = 8'h0D;
                        else cur_char = 8'h0A;
                    end

                    4'd6: begin // "Total instructions         %4d                %4d\r\n" (55)
                        cur_len = 7'd55;
                        case (char_idx)
                            0: cur_char = "T"; 1: cur_char = "o"; 2: cur_char = "t"; 3: cur_char = "a"; 4: cur_char = "l";
                            5: cur_char = " "; 6: cur_char = "i"; 7: cur_char = "n"; 8: cur_char = "s"; 9: cur_char = "t";
                            10: cur_char = "r"; 11: cur_char = "u"; 12: cur_char = "c"; 13: cur_char = "t"; 14: cur_char = "i"; 15: cur_char = "o"; 16: cur_char = "n"; 17: cur_char = "s";
                            18,19,20,21,22,23,24,25,26: cur_char = " ";
                            27: cur_char = dec_space_digit(mode0_instructions, 2'd3);
                            28: cur_char = dec_space_digit(mode0_instructions, 2'd2);
                            29: cur_char = dec_space_digit(mode0_instructions, 2'd1);
                            30: cur_char = dec_space_digit(mode0_instructions, 2'd0);
                            31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46: cur_char = " ";
                            47: cur_char = dec_space_digit(mode1_instructions, 2'd3);
                            48: cur_char = dec_space_digit(mode1_instructions, 2'd2);
                            49: cur_char = dec_space_digit(mode1_instructions, 2'd1);
                            50: cur_char = dec_space_digit(mode1_instructions, 2'd0);
                            51,52: cur_char = " ";
                            53: cur_char = 8'h0D; 54: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd7: begin // "Total clock cycles         %4d                %4d\r\n" (55)
                        cur_len = 7'd55;
                        case (char_idx)
                            0: cur_char = "T"; 1: cur_char = "o"; 2: cur_char = "t"; 3: cur_char = "a"; 4: cur_char = "l";
                            5: cur_char = " "; 6: cur_char = "c"; 7: cur_char = "l"; 8: cur_char = "o"; 9: cur_char = "c"; 10: cur_char = "k";
                            11: cur_char = " "; 12: cur_char = "c"; 13: cur_char = "y"; 14: cur_char = "c"; 15: cur_char = "l"; 16: cur_char = "e"; 17: cur_char = "s";
                            18,19,20,21,22,23,24,25,26: cur_char = " ";
                            27: cur_char = dec_space_digit(mode0_cycles, 2'd3);
                            28: cur_char = dec_space_digit(mode0_cycles, 2'd2);
                            29: cur_char = dec_space_digit(mode0_cycles, 2'd1);
                            30: cur_char = dec_space_digit(mode0_cycles, 2'd0);
                            31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46: cur_char = " ";
                            47: cur_char = dec_space_digit(mode1_cycles, 2'd3);
                            48: cur_char = dec_space_digit(mode1_cycles, 2'd2);
                            49: cur_char = dec_space_digit(mode1_cycles, 2'd1);
                            50: cur_char = dec_space_digit(mode1_cycles, 2'd0);
                            51,52: cur_char = " ";
                            53: cur_char = 8'h0D; 54: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd8: begin // "I-cache hits               %4d                %4d\r\n" (55)
                        cur_len = 7'd55;
                        case (char_idx)
                            0: cur_char = "I"; 1: cur_char = "-"; 2: cur_char = "c"; 3: cur_char = "a"; 4: cur_char = "c"; 5: cur_char = "h"; 6: cur_char = "e";
                            7: cur_char = " "; 8: cur_char = "h"; 9: cur_char = "i"; 10: cur_char = "t"; 11: cur_char = "s";
                            12,13,14,15,16,17,18,19,20,21,22,23,24,25,26: cur_char = " ";
                            27: cur_char = dec_space_digit(mode0_hits, 2'd3);
                            28: cur_char = dec_space_digit(mode0_hits, 2'd2);
                            29: cur_char = dec_space_digit(mode0_hits, 2'd1);
                            30: cur_char = dec_space_digit(mode0_hits, 2'd0);
                            31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46: cur_char = " ";
                            47: cur_char = dec_space_digit(mode1_hits, 2'd3);
                            48: cur_char = dec_space_digit(mode1_hits, 2'd2);
                            49: cur_char = dec_space_digit(mode1_hits, 2'd1);
                            50: cur_char = dec_space_digit(mode1_hits, 2'd0);
                            51,52: cur_char = " ";
                            53: cur_char = 8'h0D; 54: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd9: begin // "I-cache misses             %4d                %4d\r\n" (55)
                        cur_len = 7'd55;
                        case (char_idx)
                            0: cur_char = "I"; 1: cur_char = "-"; 2: cur_char = "c"; 3: cur_char = "a"; 4: cur_char = "c"; 5: cur_char = "h"; 6: cur_char = "e";
                            7: cur_char = " "; 8: cur_char = "m"; 9: cur_char = "i"; 10: cur_char = "s"; 11: cur_char = "s"; 12: cur_char = "e"; 13: cur_char = "s";
                            14,15,16,17,18,19,20,21,22,23,24,25,26: cur_char = " ";
                            27: cur_char = dec_space_digit(mode0_misses, 2'd3);
                            28: cur_char = dec_space_digit(mode0_misses, 2'd2);
                            29: cur_char = dec_space_digit(mode0_misses, 2'd1);
                            30: cur_char = dec_space_digit(mode0_misses, 2'd0);
                            31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46: cur_char = " ";
                            47: cur_char = dec_space_digit(mode1_misses, 2'd3);
                            48: cur_char = dec_space_digit(mode1_misses, 2'd2);
                            49: cur_char = dec_space_digit(mode1_misses, 2'd1);
                            50: cur_char = dec_space_digit(mode1_misses, 2'd0);
                            51,52: cur_char = " ";
                            53: cur_char = 8'h0D; 54: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd10: begin // "Hit rate                  %2d.%1d %%            %2d.%1d %%\r\n" (58)
                        cur_len = 7'd58;
                        case (char_idx)
                            0: cur_char = "H"; 1: cur_char = "i"; 2: cur_char = "t"; 3: cur_char = " "; 4: cur_char = "r"; 5: cur_char = "a"; 6: cur_char = "t"; 7: cur_char = "e";
                            8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26: cur_char = " ";
                            27: cur_char = dec2_space(m0_rate_x10 / 10, 1'b1);
                            28: cur_char = dec2_space(m0_rate_x10 / 10, 1'b0);
                            29: cur_char = ".";
                            30: cur_char = 8'h30 + (m0_rate_x10 % 10);
                            31: cur_char = " "; 32: cur_char = "%";
                            33,34,35,36,37,38,39,40,41,42,43,44,45,46: cur_char = " ";
                            47: cur_char = dec2_space(m1_rate_x10 / 10, 1'b1);
                            48: cur_char = dec2_space(m1_rate_x10 / 10, 1'b0);
                            49: cur_char = ".";
                            50: cur_char = 8'h30 + (m1_rate_x10 % 10);
                            51: cur_char = " "; 52: cur_char = "%";
                            53,54,55: cur_char = " ";
                            56: cur_char = 8'h0D; 57: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd12: begin // "Speedup (CPI improvement) :  %2d.%02dx\r\n" (40)
                        cur_len = 7'd40;
                        case (char_idx)
                            0: cur_char = "S"; 1: cur_char = "p"; 2: cur_char = "e"; 3: cur_char = "e"; 4: cur_char = "d"; 5: cur_char = "u"; 6: cur_char = "p";
                            7: cur_char = " "; 8: cur_char = "("; 9: cur_char = "C"; 10: cur_char = "P"; 11: cur_char = "I"; 12: cur_char = " "; 13: cur_char = "i";
                            14: cur_char = "m"; 15: cur_char = "p"; 16: cur_char = "r"; 17: cur_char = "o"; 18: cur_char = "v"; 19: cur_char = "e"; 20: cur_char = "m"; 21: cur_char = "e"; 22: cur_char = "n"; 23: cur_char = "t"; 24: cur_char = ")";
                            25: cur_char = " "; 26: cur_char = ":"; 27,28: cur_char = " ";
                            29: cur_char = dec2_space(speedup_x100 / 100, 1'b1);
                            30: cur_char = dec2_space(speedup_x100 / 100, 1'b0);
                            31: cur_char = ".";
                            32: cur_char = 8'h30 + ((speedup_x100 / 10) % 10);
                            33: cur_char = 8'h30 + (speedup_x100 % 10);
                            34: cur_char = "x";
                            35,36,37: cur_char = " ";
                            38: cur_char = 8'h0D; 39: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end
                endcase
            end

            // ----------------------------------------------------------------
            // Bare-Metal C Program Header Banner
            // ----------------------------------------------------------------
            S_C_BANNER: begin
                case (sub_step)
                    4'd0: begin // \r\n (2)
                        cur_len = 7'd2;
                        cur_char = (char_idx == 0) ? 8'h0D : 8'h0A;
                    end

                    4'd1, 4'd3: begin // ============================================================\r\n (62)
                        cur_len = 7'd62;
                        if (char_idx < 60) cur_char = "=";
                        else if (char_idx == 60) cur_char = 8'h0D;
                        else cur_char = 8'h0A;
                    end

                    4'd2: begin // "   FEATURE 6: BARE-METAL C PROGRAM I-CACHE VERIFICATION     \r\n" (62)
                        cur_len = 7'd62;
                        case (char_idx)
                            0,1,2: cur_char = " ";
                            3: cur_char = "F"; 4: cur_char = "E"; 5: cur_char = "A"; 6: cur_char = "T"; 7: cur_char = "U"; 8: cur_char = "R"; 9: cur_char = "E";
                            10: cur_char = " "; 11: cur_char = "6"; 12: cur_char = ":"; 13: cur_char = " ";
                            14: cur_char = "B"; 15: cur_char = "A"; 16: cur_char = "R"; 17: cur_char = "E"; 18: cur_char = "-";
                            19: cur_char = "M"; 20: cur_char = "E"; 21: cur_char = "T"; 22: cur_char = "A"; 23: cur_char = "L"; 24: cur_char = " ";
                            25: cur_char = "C"; 26: cur_char = " ";
                            27: cur_char = "P"; 28: cur_char = "R"; 29: cur_char = "O"; 30: cur_char = "G"; 31: cur_char = "R"; 32: cur_char = "A"; 33: cur_char = "M"; 34: cur_char = " ";
                            35: cur_char = "I"; 36: cur_char = "-"; 37: cur_char = "C"; 38: cur_char = "A"; 39: cur_char = "C"; 40: cur_char = "H"; 41: cur_char = "E"; 42: cur_char = " ";
                            43: cur_char = "V"; 44: cur_char = "E"; 45: cur_char = "R"; 46: cur_char = "I"; 47: cur_char = "F"; 48: cur_char = "I"; 49: cur_char = "C"; 50: cur_char = "A"; 51: cur_char = "T"; 52: cur_char = "I"; 53: cur_char = "O"; 54: cur_char = "N";
                            55,56,57,58,59: cur_char = " ";
                            60: cur_char = 8'h0D; 61: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd4: begin // "     CYC   PC           INSTR               STATUS\r\n" (52)
                        cur_len = 7'd52;
                        case (char_idx)
                            0,1,2,3,4: cur_char = " ";
                            5: cur_char = "C"; 6: cur_char = "Y"; 7: cur_char = "C";
                            8,9,10: cur_char = " ";
                            11: cur_char = "P"; 12: cur_char = "C";
                            13,14,15,16,17,18,19,20,21,22,23: cur_char = " ";
                            24: cur_char = "I"; 25: cur_char = "N"; 26: cur_char = "S"; 27: cur_char = "T"; 28: cur_char = "R";
                            29,30,31,32,33,34,35,36,37,38,39,40,41,42,43: cur_char = " ";
                            44: cur_char = "S"; 45: cur_char = "T"; 46: cur_char = "A"; 47: cur_char = "T"; 48: cur_char = "U"; 49: cur_char = "S";
                            50: cur_char = 8'h0D; 51: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd5: begin // ------------------------------------------------------------\r\n (62)
                        cur_len = 7'd62;
                        if (char_idx < 60) cur_char = "-";
                        else if (char_idx == 60) cur_char = 8'h0D;
                        else cur_char = 8'h0A;
                    end
                endcase
            end

            // ----------------------------------------------------------------
            // Bare-Metal C Program Verification Summary
            // ----------------------------------------------------------------
            S_C_SUMMARY: begin
                case (sub_step)
                    4'd0: begin // ------------------------------------------------------------\r\n (62)
                        cur_len = 7'd62;
                        if (char_idx < 60) cur_char = "-";
                        else if (char_idx == 60) cur_char = 8'h0D;
                        else cur_char = 8'h0A;
                    end

                    4'd1, 4'd3, 4'd13: begin // ============================================================\r\n (62)
                        cur_len = 7'd62;
                        if (char_idx < 60) cur_char = "=";
                        else if (char_idx == 60) cur_char = 8'h0D;
                        else cur_char = 8'h0A;
                    end

                    4'd2: begin // "             BARE-METAL C VERIFICATION SUMMARY              \r\n" (62)
                        cur_len = 7'd62;
                        case (char_idx)
                            0,1,2,3,4,5,6,7,8,9,10,11,12: cur_char = " ";
                            13: cur_char = "B"; 14: cur_char = "A"; 15: cur_char = "R"; 16: cur_char = "E"; 17: cur_char = "-";
                            18: cur_char = "M"; 19: cur_char = "E"; 20: cur_char = "T"; 21: cur_char = "A"; 22: cur_char = "L"; 23: cur_char = " ";
                            24: cur_char = "C"; 25: cur_char = " ";
                            26: cur_char = "V"; 27: cur_char = "E"; 28: cur_char = "R"; 29: cur_char = "I"; 30: cur_char = "F"; 31: cur_char = "I"; 32: cur_char = "C"; 33: cur_char = "A"; 34: cur_char = "T"; 35: cur_char = "I"; 36: cur_char = "O"; 37: cur_char = "N"; 38: cur_char = " ";
                            39: cur_char = "S"; 40: cur_char = "U"; 41: cur_char = "M"; 42: cur_char = "M"; 43: cur_char = "A"; 44: cur_char = "R"; 45: cur_char = "Y";
                            46,47,48,49,50,51,52,53,54,55,56,57,58,59: cur_char = " ";
                            60: cur_char = 8'h0D; 61: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd4: begin // "Program Source           : icache.c (like addition.c)\r\n" (56)
                        cur_len = 7'd56;
                        case (char_idx)
                            0: cur_char = "P"; 1: cur_char = "r"; 2: cur_char = "o"; 3: cur_char = "g"; 4: cur_char = "r"; 5: cur_char = "a"; 6: cur_char = "m";
                            7: cur_char = " "; 8: cur_char = "S"; 9: cur_char = "o"; 10: cur_char = "u"; 11: cur_char = "r"; 12: cur_char = "c"; 13: cur_char = "e";
                            14,15,16,17,18,19,20,21,22,23,24: cur_char = " ";
                            25: cur_char = ":"; 26: cur_char = " ";
                            27: cur_char = "i"; 28: cur_char = "c"; 29: cur_char = "a"; 30: cur_char = "c"; 31: cur_char = "h"; 32: cur_char = "e"; 33: cur_char = "."; 34: cur_char = "c";
                            35: cur_char = " "; 36: cur_char = "("; 37: cur_char = "l"; 38: cur_char = "i"; 39: cur_char = "k"; 40: cur_char = "e"; 41: cur_char = " ";
                            42: cur_char = "a"; 43: cur_char = "d"; 44: cur_char = "d"; 45: cur_char = "i"; 46: cur_char = "t"; 47: cur_char = "i"; 48: cur_char = "o"; 49: cur_char = "n"; 50: cur_char = "."; 51: cur_char = "c"; 52: cur_char = ")";
                            53: cur_char = " "; 54: cur_char = 8'h0D; 55: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd5: begin // "Execution Status         : COMPLETED (Halt on RET)\r\n" (53)
                        cur_len = 7'd53;
                        case (char_idx)
                            0: cur_char = "E"; 1: cur_char = "x"; 2: cur_char = "e"; 3: cur_char = "c"; 4: cur_char = "u"; 5: cur_char = "t"; 6: cur_char = "i"; 7: cur_char = "o"; 8: cur_char = "n";
                            9: cur_char = " "; 10: cur_char = "S"; 11: cur_char = "t"; 12: cur_char = "a"; 13: cur_char = "t"; 14: cur_char = "u"; 15: cur_char = "s";
                            16,17,18,19,20,21,22,23,24: cur_char = " ";
                            25: cur_char = ":"; 26: cur_char = " ";
                            27: cur_char = "C"; 28: cur_char = "O"; 29: cur_char = "M"; 30: cur_char = "P"; 31: cur_char = "L"; 32: cur_char = "E"; 33: cur_char = "T"; 34: cur_char = "E"; 35: cur_char = "D";
                            36: cur_char = " "; 37: cur_char = "("; 38: cur_char = "H"; 39: cur_char = "a"; 40: cur_char = "l"; 41: cur_char = "t"; 42: cur_char = " ";
                            43: cur_char = "o"; 44: cur_char = "n"; 45: cur_char = " "; 46: cur_char = "R"; 47: cur_char = "E"; 48: cur_char = "T"; 49: cur_char = ")";
                            50: cur_char = " "; 51: cur_char = 8'h0D; 52: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd6: begin // "Return Value (a0 / x10)  : %4d (0x000000%02x)\r\n" (46)
                        cur_len = 7'd46;
                        case (char_idx)
                            0: cur_char = "R"; 1: cur_char = "e"; 2: cur_char = "t"; 3: cur_char = "u"; 4: cur_char = "r"; 5: cur_char = "n";
                            6: cur_char = " "; 7: cur_char = "V"; 8: cur_char = "a"; 9: cur_char = "l"; 10: cur_char = "u"; 11: cur_char = "e";
                            12: cur_char = " "; 13: cur_char = "("; 14: cur_char = "a"; 15: cur_char = "0"; 16: cur_char = " "; 17: cur_char = "/"; 18: cur_char = " "; 19: cur_char = "x"; 20: cur_char = "1"; 21: cur_char = "0"; 22: cur_char = ")";
                            23,24: cur_char = " ";
                            25: cur_char = ":"; 26: cur_char = " ";
                            27: cur_char = dec_space_digit(c_stat_return_val, 2'd3);
                            28: cur_char = dec_space_digit(c_stat_return_val, 2'd2);
                            29: cur_char = dec_space_digit(c_stat_return_val, 2'd1);
                            30: cur_char = dec_space_digit(c_stat_return_val, 2'd0);
                            31: cur_char = " "; 32: cur_char = "("; 33: cur_char = "0"; 34: cur_char = "x";
                            35: cur_char = "0"; 36: cur_char = "0"; 37: cur_char = "0"; 38: cur_char = "0";
                            39: cur_char = "0"; 40: cur_char = "0";
                            41: cur_char = to_hex(c_stat_return_val[7:4]);
                            42: cur_char = to_hex(c_stat_return_val[3:0]);
                            43: cur_char = ")";
                            44: cur_char = 8'h0D; 45: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd7: begin // "Total Clock Cycles       : %4d (< 40 cycles approx)\r\n" (55)
                        cur_len = 7'd55;
                        case (char_idx)
                            0: cur_char = "T"; 1: cur_char = "o"; 2: cur_char = "t"; 3: cur_char = "a"; 4: cur_char = "l";
                            5: cur_char = " "; 6: cur_char = "C"; 7: cur_char = "l"; 8: cur_char = "o"; 9: cur_char = "c"; 10: cur_char = "k";
                            11: cur_char = " "; 12: cur_char = "C"; 13: cur_char = "y"; 14: cur_char = "c"; 15: cur_char = "l"; 16: cur_char = "e"; 17: cur_char = "s";
                            18,19,20,21,22,23,24: cur_char = " ";
                            25: cur_char = ":"; 26: cur_char = " ";
                            27: cur_char = dec_space_digit(c_stat_cycles, 2'd3);
                            28: cur_char = dec_space_digit(c_stat_cycles, 2'd2);
                            29: cur_char = dec_space_digit(c_stat_cycles, 2'd1);
                            30: cur_char = dec_space_digit(c_stat_cycles, 2'd0);
                            31: cur_char = " "; 32: cur_char = "("; 33: cur_char = "<"; 34: cur_char = " "; 35: cur_char = "4"; 36: cur_char = "0";
                            37: cur_char = " "; 38: cur_char = "c"; 39: cur_char = "y"; 40: cur_char = "c"; 41: cur_char = "l"; 42: cur_char = "e"; 43: cur_char = "s";
                            44: cur_char = " "; 45: cur_char = "a"; 46: cur_char = "p"; 47: cur_char = "p"; 48: cur_char = "r"; 49: cur_char = "o"; 50: cur_char = "x"; 51: cur_char = ")";
                            52: cur_char = " "; 53: cur_char = 8'h0D; 54: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd8: begin // "Instructions Retired     : %4d\r\n" (33)
                        cur_len = 7'd33;
                        case (char_idx)
                            0: cur_char = "I"; 1: cur_char = "n"; 2: cur_char = "s"; 3: cur_char = "t"; 4: cur_char = "r"; 5: cur_char = "u"; 6: cur_char = "c"; 7: cur_char = "t"; 8: cur_char = "i"; 9: cur_char = "o"; 10: cur_char = "n"; 11: cur_char = "s";
                            12: cur_char = " "; 13: cur_char = "R"; 14: cur_char = "e"; 15: cur_char = "t"; 16: cur_char = "i"; 17: cur_char = "r"; 18: cur_char = "e"; 19: cur_char = "d";
                            20,21,22,23,24: cur_char = " ";
                            25: cur_char = ":"; 26: cur_char = " ";
                            27: cur_char = dec_space_digit(c_stat_instructions, 2'd3);
                            28: cur_char = dec_space_digit(c_stat_instructions, 2'd2);
                            29: cur_char = dec_space_digit(c_stat_instructions, 2'd1);
                            30: cur_char = dec_space_digit(c_stat_instructions, 2'd0);
                            31: cur_char = 8'h0D; 32: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd9: begin // "L1 I-Cache Hits          : %4d\r\n" (33)
                        cur_len = 7'd33;
                        case (char_idx)
                            0: cur_char = "L"; 1: cur_char = "1"; 2: cur_char = " "; 3: cur_char = "I"; 4: cur_char = "-"; 5: cur_char = "C"; 6: cur_char = "a"; 7: cur_char = "c"; 8: cur_char = "h"; 9: cur_char = "e";
                            10: cur_char = " "; 11: cur_char = "H"; 12: cur_char = "i"; 13: cur_char = "t"; 14: cur_char = "s";
                            15,16,17,18,19,20,21,22,23,24: cur_char = " ";
                            25: cur_char = ":"; 26: cur_char = " ";
                            27: cur_char = dec_space_digit(c_stat_hits, 2'd3);
                            28: cur_char = dec_space_digit(c_stat_hits, 2'd2);
                            29: cur_char = dec_space_digit(c_stat_hits, 2'd1);
                            30: cur_char = dec_space_digit(c_stat_hits, 2'd0);
                            31: cur_char = 8'h0D; 32: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd10: begin // "L1 I-Cache Misses        : %4d\r\n" (33)
                        cur_len = 7'd33;
                        case (char_idx)
                            0: cur_char = "L"; 1: cur_char = "1"; 2: cur_char = " "; 3: cur_char = "I"; 4: cur_char = "-"; 5: cur_char = "C"; 6: cur_char = "a"; 7: cur_char = "c"; 8: cur_char = "h"; 9: cur_char = "e";
                            10: cur_char = " "; 11: cur_char = "M"; 12: cur_char = "i"; 13: cur_char = "s"; 14: cur_char = "s"; 15: cur_char = "e"; 16: cur_char = "s";
                            17,18,19,20,21,22,23,24: cur_char = " ";
                            25: cur_char = ":"; 26: cur_char = " ";
                            27: cur_char = dec_space_digit(c_stat_misses, 2'd3);
                            28: cur_char = dec_space_digit(c_stat_misses, 2'd2);
                            29: cur_char = dec_space_digit(c_stat_misses, 2'd1);
                            30: cur_char = dec_space_digit(c_stat_misses, 2'd0);
                            31: cur_char = 8'h0D; 32: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd11: begin // "L1 I-Cache Hit Rate      : %2d.%1d %\r\n" (35)
                        cur_len = 7'd35;
                        case (char_idx)
                            0: cur_char = "L"; 1: cur_char = "1"; 2: cur_char = " "; 3: cur_char = "I"; 4: cur_char = "-"; 5: cur_char = "C"; 6: cur_char = "a"; 7: cur_char = "c"; 8: cur_char = "h"; 9: cur_char = "e";
                            10: cur_char = " "; 11: cur_char = "H"; 12: cur_char = "i"; 13: cur_char = "t"; 14: cur_char = " "; 15: cur_char = "R"; 16: cur_char = "a"; 17: cur_char = "t"; 18: cur_char = "e";
                            19,20,21,22,23,24: cur_char = " ";
                            25: cur_char = ":"; 26: cur_char = " ";
                            27: cur_char = dec2_space(c_rate_x10 / 10, 1'b1);
                            28: cur_char = dec2_space(c_rate_x10 / 10, 1'b0);
                            29: cur_char = ".";
                            30: cur_char = 8'h30 + (c_rate_x10 % 10);
                            31: cur_char = " "; 32: cur_char = "%"; 33: cur_char = 8'h0D; 34: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd12: begin // "Average CPI              : %2d.%02d\r\n" (34)
                        cur_len = 7'd34;
                        case (char_idx)
                            0: cur_char = "A"; 1: cur_char = "v"; 2: cur_char = "e"; 3: cur_char = "r"; 4: cur_char = "a"; 5: cur_char = "g"; 6: cur_char = "e";
                            7: cur_char = " "; 8: cur_char = "C"; 9: cur_char = "P"; 10: cur_char = "I";
                            11,12,13,14,15,16,17,18,19,20,21,22,23,24: cur_char = " ";
                            25: cur_char = ":"; 26: cur_char = " ";
                            27: cur_char = dec2_space(c_cpi_x100 / 100, 1'b1);
                            28: cur_char = dec2_space(c_cpi_x100 / 100, 1'b0);
                            29: cur_char = ".";
                            30: cur_char = 8'h30 + ((c_cpi_x100 / 10) % 10);
                            31: cur_char = 8'h30 + (c_cpi_x100 % 10);
                            32: cur_char = 8'h0D; 33: cur_char = 8'h0A;
                            default: cur_char = " ";
                        endcase
                    end

                    4'd14: begin // \r\n (2)
                        cur_len = 7'd2;
                        cur_char = (char_idx == 0) ? 8'h0D : 8'h0A;
                    end
                endcase
            end

            default: begin
                cur_len  = 7'd0;
                cur_char = " ";
            end
        endcase
    end

    // ------------------------------------------------------------------------
    // Sequential Transmitter Control FSM
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state         <= S_IDLE;
            sub_step      <= 4'd0;
            char_idx      <= 7'd0;
            current_row   <= 8'd0;
            trace_rd_addr <= 8'd0;
            tx_start      <= 1'b0;
            tx_data       <= 8'd0;
            print_done    <= 1'b0;
            is_step_op    <= 1'b0;
        end else begin
            print_done <= 1'b0;

            case (state)
                S_IDLE: begin
                    tx_start <= 1'b0;
                    char_idx <= 7'd0;
                    sub_step <= 4'd0;

                    if (start_print) begin
                        state       <= S_BANNER;
                        is_step_op  <= 1'b0;
                        current_row <= 8'd0;
                    end else if (start_print_c) begin
                        state       <= S_C_BANNER;
                        is_step_op  <= 1'b0;
                        current_row <= 8'd0;
                    end else if (print_banner_only) begin
                        state      <= S_BANNER;
                        is_step_op <= 1'b1;
                    end else if (print_single_row) begin
                        state         <= S_ROW;
                        is_step_op    <= 1'b1;
                        current_row   <= single_row_addr;
                        trace_rd_addr <= single_row_addr;
                    end else if (print_summary_only) begin
                        state      <= S_SUMMARY;
                        is_step_op <= 1'b1;
                    end
                end

                S_BANNER: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data  <= cur_char;
                        tx_start <= 1'b1;

                        if (char_idx < cur_len - 1) begin
                            char_idx <= char_idx + 7'd1;
                        end else begin
                            char_idx <= 7'd0;
                            if (sub_step < 4'd5) begin
                                sub_step <= sub_step + 4'd1;
                            end else begin
                                sub_step      <= 4'd0;
                                current_row   <= 8'd0;
                                trace_rd_addr <= 8'd0;
                                state         <= is_step_op ? S_IDLE : S_ROW;
                            end
                        end
                    end else begin
                        tx_start <= 1'b0;
                    end
                end

                S_ROW: begin
                    trace_rd_addr <= current_row;

                    if (!tx_busy && !tx_start) begin
                        tx_data  <= cur_char;
                        tx_start <= 1'b1;

                        if (char_idx < cur_len - 1) begin
                            char_idx <= char_idx + 7'd1;
                        end else begin
                            char_idx <= 7'd0;
                            if (is_step_op) begin
                                state <= S_IDLE;
                            end else if (current_row < trace_len - 1) begin
                                current_row   <= current_row + 8'd1;
                                trace_rd_addr <= current_row + 8'd1;
                            end else begin
                                sub_step <= 4'd0;
                                state    <= S_SUMMARY;
                            end
                        end
                    end else begin
                        tx_start <= 1'b0;
                    end
                end

                S_SUMMARY: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data  <= cur_char;
                        tx_start <= 1'b1;

                        if (char_idx < cur_len - 1) begin
                            char_idx <= char_idx + 7'd1;
                        end else begin
                            char_idx <= 7'd0;
                            if (sub_step < 4'd10) begin
                                sub_step <= sub_step + 4'd1;
                            end else begin
                                sub_step <= 4'd0;
                                state    <= S_COMPARE;
                            end
                        end
                    end else begin
                        tx_start <= 1'b0;
                    end
                end

                S_COMPARE: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data  <= cur_char;
                        tx_start <= 1'b1;

                        if (char_idx < cur_len - 1) begin
                            char_idx <= char_idx + 7'd1;
                        end else begin
                            char_idx <= 7'd0;
                            if (mode0_valid && mode1_valid) begin
                                if (sub_step < 4'd13) begin
                                    sub_step <= sub_step + 4'd1;
                                end else begin
                                    state <= S_DONE;
                                end
                            end else begin
                                if (sub_step < 4'd1) begin
                                    sub_step <= sub_step + 4'd1;
                                end else begin
                                    state <= S_DONE;
                                end
                            end
                        end
                    end else begin
                        tx_start <= 1'b0;
                    end
                end

                // ------------------------------------------------------------
                // Bare-Metal C Program Sequence States
                // ------------------------------------------------------------
                S_C_BANNER: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data  <= cur_char;
                        tx_start <= 1'b1;

                        if (char_idx < cur_len - 1) begin
                            char_idx <= char_idx + 7'd1;
                        end else begin
                            char_idx <= 7'd0;
                            if (sub_step < 4'd5) begin
                                sub_step <= sub_step + 4'd1;
                            end else begin
                                sub_step      <= 4'd0;
                                current_row   <= 8'd0;
                                trace_rd_addr <= 8'd0;
                                state         <= (c_trace_len > 0) ? S_C_ROW : S_C_SUMMARY;
                            end
                        end
                    end else begin
                        tx_start <= 1'b0;
                    end
                end

                S_C_ROW: begin
                    trace_rd_addr <= current_row;

                    if (!tx_busy && !tx_start) begin
                        tx_data  <= cur_char;
                        tx_start <= 1'b1;

                        if (char_idx < cur_len - 1) begin
                            char_idx <= char_idx + 7'd1;
                        end else begin
                            char_idx <= 7'd0;
                            if (current_row < c_trace_len - 1) begin
                                current_row   <= current_row + 8'd1;
                                trace_rd_addr <= current_row + 8'd1;
                            end else begin
                                sub_step <= 4'd0;
                                state    <= S_C_SUMMARY;
                            end
                        end
                    end else begin
                        tx_start <= 1'b0;
                    end
                end

                S_C_SUMMARY: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data  <= cur_char;
                        tx_start <= 1'b1;

                        if (char_idx < cur_len - 1) begin
                            char_idx <= char_idx + 7'd1;
                        end else begin
                            char_idx <= 7'd0;
                            if (sub_step < 4'd14) begin
                                sub_step <= sub_step + 4'd1;
                            end else begin
                                state <= S_DONE;
                            end
                        end
                    end else begin
                        tx_start <= 1'b0;
                    end
                end

                S_DONE: begin
                    print_done <= 1'b1;
                    tx_start   <= 1'b0;
                    state      <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
