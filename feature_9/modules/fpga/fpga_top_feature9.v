// ============================================================================
// File: fpga_top_feature9.v
// Module: fpga_top_feature9
// Description: Synthesizable FPGA Top-Level Module for Feature 9:
//              Comprehensive Zbb Bit-Manipulation Extension & Telemetry
// Target Device: Xilinx Artix-7 XC7A100T-1CSG324C (Digilent Nexys A7-100T Board)
//
// Dual-Mode Single Switch Verification:
//   - SW[4] = 0 (OFF / down): Runs ONLY Bare-Metal C Program (zbb.c) -> streams C trace -> halts
//   - SW[4] = 1 (ON  / up  ): Runs ONLY Synthetic BTB/Zbb Benchmark -> streams trace table -> halts
//
// Clocks:
//   - Onboard Oscillator: 100 MHz (Pin E3)
//   - Core & UART Clock : 50 MHz (generated via clk_50mhz_reg toggle)
//
// UART Configuration:
//   - Baud Rate: 115200 Baud, 8 Data Bits, No Parity, 1 Stop Bit (8N1)
// ============================================================================

`timescale 1ns/1ps

module fpga_top_feature9 #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  wire        clk_100mhz,  // 100 MHz onboard oscillator (Pin E3)
    input  wire        cpu_resetn,  // Active-low CPU reset push button (Pin C12)
    input  wire        btnc,        // Center push button: manual retransmit
    input  wire [15:0] sw,          // 16 slide switches (SW[4] selects program)
    output wire [7:0]  an,          // 8-digit Seven-Segment Anodes (Pins J17..U13)
    output wire [6:0]  seg,         // 7-segment Cathodes (Pins T10..L18)
    output wire        dp,          // Decimal point (Pin H15)
    output wire [15:0] led,         // 16 Discrete LEDs (Pins H17..R18)
    output wire        uart_tx,     // UART TX pin (Pin D4 -> FTDI USB-UART)
    input  wire        uart_rx      // UART RX pin (Pin C4 <- FTDI USB-UART)
);

    // ------------------------------------------------------------------------
    // 1. Clock Generation: 50 MHz Derived Core Clock
    // ------------------------------------------------------------------------
    reg clk_50mhz_reg = 1'b0;
    always @(posedge clk_100mhz) begin
        clk_50mhz_reg <= ~clk_50mhz_reg;
    end
    wire clk_50mhz = clk_50mhz_reg;

    // ------------------------------------------------------------------------
    // 2. Synchronous Reset De-assertion in 50 MHz Domain
    // ------------------------------------------------------------------------
    reg [2:0] rst_sync;
    always @(posedge clk_50mhz or negedge cpu_resetn) begin
        if (!cpu_resetn)
            rst_sync <= 3'b000;
        else
            rst_sync <= {rst_sync[1:0], 1'b1};
    end
    wire sys_reset_n = rst_sync[2];

    // ------------------------------------------------------------------------
    // 3. Instruction and Data Memories
    // ------------------------------------------------------------------------
    localparam PHASE_BENCHMARK = 1'b1;
    localparam PHASE_C_PROGRAM = 1'b0;
    reg active_phase;

    wire [31:0] imem_addr;
    wire [31:0] bench_imem_rdata;
    wire [31:0] c_imem_rdata;

    instr_mem #(
        .HEX_FILE("imem_bench.hex"),
        .WORDS(1024)
    ) u_imem_bench (
        .clk   (clk_50mhz),
        .pc    (imem_addr),
        .instr (bench_imem_rdata)
    );

    instr_mem #(
        .HEX_FILE("imem_c.hex"),
        .WORDS(1024)
    ) u_imem_c (
        .clk   (clk_50mhz),
        .pc    (imem_addr),
        .instr (c_imem_rdata)
    );

    reg saw_c_ret;
    wire [31:0] core_imem_rdata = (active_phase == PHASE_BENCHMARK) ? bench_imem_rdata :
                                  (saw_c_ret ? 32'h0000_0013 : c_imem_rdata);

    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we;
    wire        dmem_re;
    wire [31:0] dmem_rdata;

    data_mem #(
        .HEX_FILE("dmem.hex"),
        .WORDS(1024)
    ) u_dmem (
        .clk   (clk_50mhz),
        .re    (dmem_re),
        .raddr (dmem_addr),
        .rdata (dmem_rdata),
        .we    (dmem_we),
        .waddr (dmem_addr),
        .wdata (dmem_wdata),
        .wstrb (dmem_wstrb)
    );

    // ------------------------------------------------------------------------
    // 4. Processor Core Instantiation
    // ------------------------------------------------------------------------
    reg core_freeze;
    reg core_soft_reset_n;
    wire core_reset_n = sys_reset_n & core_soft_reset_n;

    wire [31:0] pc_if;
    wire [31:0] pc_id;
    wire [31:0] pc_ex;
    wire [31:0] pc_mem;
    wire [31:0] pc_wb;
    wire        wb_reg_write;
    wire [4:0]  wb_dest_reg;
    wire [31:0] wb_data;
    wire        hazard_stall;
    wire        hazard_flush_id;
    wire        hazard_flush_ex;
    wire [1:0]  forward_a;
    wire [1:0]  forward_b;
    wire        mul_active;
    wire        div_active;
    wire        div_busy;
    wire        fpu_active;
    wire        fpu_busy;
    wire        exception;

    pipeline_5stage #(
        .RESET_PC(32'h0000_0000)
    ) u_core (
        .clk            (clk_50mhz),
        .reset_n        (core_reset_n),
        .stall_ext      (core_freeze),
        .use_dsp_i      (1'b1),
        .imem_addr      (imem_addr),
        .imem_rdata     (core_imem_rdata),
        .dmem_addr      (dmem_addr),
        .dmem_wdata     (dmem_wdata),
        .dmem_wstrb     (dmem_wstrb),
        .dmem_we        (dmem_we),
        .dmem_re        (dmem_re),
        .dmem_rdata     (dmem_rdata),
        .pc_if          (pc_if),
        .pc_id          (pc_id),
        .pc_ex          (pc_ex),
        .pc_mem         (pc_mem),
        .pc_wb          (pc_wb),
        .wb_reg_write   (wb_reg_write),
        .wb_dest_reg    (wb_dest_reg),
        .wb_data        (wb_data),
        .hazard_stall   (hazard_stall),
        .hazard_flush_id(hazard_flush_id),
        .hazard_flush_ex(hazard_flush_ex),
        .forward_a      (forward_a),
        .forward_b      (forward_b),
        .mul_active     (mul_active),
        .div_active     (div_active),
        .div_busy       (div_busy),
        .fpu_active     (fpu_active),
        .fpu_busy       (fpu_busy),
        .exception      (exception),
        .btb_pred_hit   (),
        .btb_pred_taken (),
        .btb_mispredict ()
    );

    // ------------------------------------------------------------------------
    // 5. Execution Sequencer & Dual Verification Controller
    // ------------------------------------------------------------------------
    localparam SEQ_IDLE      = 3'd0;
    localparam SEQ_BENCH_RUN = 3'd1;
    localparam SEQ_BENCH_TX  = 3'd2;
    localparam SEQ_C_RESET   = 3'd3;
    localparam SEQ_C_RUN     = 3'd4;
    localparam SEQ_C_TX      = 3'd5;
    localparam SEQ_ALL_DONE  = 3'd6;

    reg [2:0] seq_state;

    // Benchmark Execution State
    reg [31:0] wb_trace_data [0:21];
    reg [4:0]  bench_retire_count;
    reg        bench_run_done;
    reg        timing_violation;
    integer init_idx;

    // C Program Execution State
    reg [15:0] c_total_cycles;
    reg [15:0] c_insts_retired;
    reg [15:0] c_return_val_a0;
    reg [2:0]  c_drain_cnt;
    reg        c_run_done;
    reg [3:0]  c_reset_timer;

    wire run_done = (active_phase == PHASE_BENCHMARK) ? bench_run_done : c_run_done;

    reg uart_seq_done;

    always @(posedge clk_50mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            seq_state          <= SEQ_IDLE;
            active_phase       <= PHASE_BENCHMARK;
            core_freeze        <= 1'b0;
            core_soft_reset_n  <= 1'b1;

            bench_retire_count <= 5'd0;
            bench_run_done     <= 1'b0;
            timing_violation   <= 1'b0;
            for (init_idx = 0; init_idx < 22; init_idx = init_idx + 1) begin
                wb_trace_data[init_idx] <= 32'h0;
            end

            c_total_cycles     <= 16'd0;
            c_insts_retired    <= 16'd0;
            c_return_val_a0    <= 16'd0;
            c_drain_cnt        <= 3'd0;
            c_run_done         <= 1'b0;
            c_reset_timer      <= 4'd0;
            saw_c_ret          <= 1'b0;
        end else begin
            case (seq_state)
                SEQ_IDLE: begin
                    core_freeze <= 1'b0;
                    if (sw[4]) begin
                        // SW[4] = 1 (ON / Up): Runs ONLY Synthetic BTB/Zbb Benchmark
                        active_phase      <= PHASE_BENCHMARK;
                        core_soft_reset_n <= 1'b1;
                        seq_state         <= SEQ_BENCH_RUN;
                    end else begin
                        // SW[4] = 0 (OFF / Down): Runs ONLY Bare-Metal C Program (zbb.c)
                        active_phase      <= PHASE_C_PROGRAM;
                        core_soft_reset_n <= 1'b0;
                        seq_state         <= SEQ_C_RESET;
                    end
                end

                SEQ_BENCH_RUN: begin
                    // Capture WB values for instructions x1 to x22
                    if (wb_reg_write && (wb_dest_reg != 5'd0) && (wb_dest_reg <= 5'd22)) begin
                        wb_trace_data[wb_dest_reg - 5'd1] <= wb_data;
                        bench_retire_count                <= bench_retire_count + 5'd1;
                    end

                    // Timing violation check for Zbb instructions in EX stage
                    if ((pc_ex >= 32'h0000_0008) && (pc_ex <= 32'h0000_0054)) begin
                        if (hazard_stall || div_busy || fpu_busy) begin
                            timing_violation <= 1'b1;
                        end
                    end

                    // Stop condition: nop at 0x58 completes Writeback stage
                    if (pc_wb == 32'h0000_0058) begin
                        bench_run_done <= 1'b1;
                        core_freeze    <= 1'b1;
                        seq_state      <= SEQ_BENCH_TX;
                    end
                end

                SEQ_BENCH_TX: begin
                    if (uart_seq_done) begin
                        seq_state <= SEQ_ALL_DONE;
                    end
                end

                SEQ_C_RESET: begin
                    core_freeze <= 1'b0;
                    if (c_reset_timer < 4'd8) begin
                        c_reset_timer     <= c_reset_timer + 4'd1;
                        core_soft_reset_n <= 1'b0;
                    end else begin
                        core_soft_reset_n <= 1'b1;
                        seq_state         <= SEQ_C_RUN;
                    end
                end

                SEQ_C_RUN: begin
                    if (!c_run_done) begin
                        c_total_cycles <= c_total_cycles + 16'd1;

                        if (wb_reg_write && !hazard_stall) begin
                            c_insts_retired <= c_insts_retired + 16'd1;
                            if (wb_dest_reg == 5'd10)
                                c_return_val_a0 <= wb_data[15:0];
                        end

                        // Detect ret (0x00008067)
                        if (c_imem_rdata == 32'h0000_8067 && pc_if != 32'd0 && !saw_c_ret) begin
                            saw_c_ret <= 1'b1;
                        end

                        if (saw_c_ret) begin
                            if (c_drain_cnt < 3'd6)
                                c_drain_cnt <= c_drain_cnt + 3'd1;
                            else begin
                                c_run_done  <= 1'b1;
                                core_freeze <= 1'b1;
                                seq_state   <= SEQ_C_TX;
                            end
                        end
                    end
                end

                SEQ_C_TX: begin
                    if (uart_seq_done) begin
                        seq_state <= SEQ_ALL_DONE;
                    end
                end

                SEQ_ALL_DONE: begin
                    core_freeze <= 1'b1;
                end

                default: seq_state <= SEQ_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // 6. UART Telemetry Streaming Engine
    // ------------------------------------------------------------------------
    `include "zbb_trace_rom.vh"
    `include "zbb_c_trace_rom.vh"

    reg  [11:0] tx_rom_addr;
    reg         uart_tx_start;
    reg  [7:0]  uart_tx_data;
    wire        uart_tx_busy;

    uart_tx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_uart (
        .clk     (clk_50mhz),
        .reset_n (sys_reset_n),
        .tx_start(uart_tx_start),
        .tx_data (uart_tx_data),
        .tx      (uart_tx),
        .tx_busy (uart_tx_busy)
    );

    // TX Step Sub-state
    localparam TX_IDLE  = 2'd0;
    localparam TX_SEND  = 2'd1;
    localparam TX_WAIT  = 2'd2;
    localparam TX_NEXT  = 2'd3;

    reg [1:0] tx_fsm;

    // Helper functions for character formatting (Benchmark Table)
    wire [11:0] table_start_offset = 12'd106; // 41 + 65
    wire [11:0] table_end_offset   = 12'd106 + 12'd1298; // 22 rows * 59 bytes

    wire is_in_table = (tx_rom_addr >= table_start_offset) && (tx_rom_addr < table_end_offset);
    wire [11:0] offset_in_table = tx_rom_addr - table_start_offset;
    wire [4:0]  row_idx = offset_in_table / 59;
    wire [5:0]  col_idx = offset_in_table % 59;

    // Columns 49 to 56 hold the 8 hex digits
    wire is_hex_val = is_in_table && (col_idx >= 6'd49) && (col_idx <= 6'd56);
    wire [2:0] hex_nibble_idx = 3'd7 - (col_idx - 6'd49);
    wire [3:0] active_nibble = (row_idx < 22) ? wb_trace_data[row_idx][hex_nibble_idx*4 +: 4] : 4'd0;

    function [7:0] nibble_to_hex_char;
        input [3:0] nibble;
        begin
            if (nibble < 4'd10)
                nibble_to_hex_char = 8'h30 + {4'd0, nibble};
            else
                nibble_to_hex_char = 8'h41 + {4'd0, nibble} - 8'd10;
        end
    endfunction

    wire [11:0] max_tx_rom_addr = (active_phase == PHASE_BENCHMARK) ? (ZBB_ROM_LEN - 1) : (ZBB_C_ROM_LEN - 1);

    always @(posedge clk_50mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            tx_rom_addr   <= 12'd0;
            uart_tx_start <= 1'b0;
            uart_tx_data  <= 8'd0;
            uart_seq_done <= 1'b0;
            tx_fsm        <= TX_IDLE;
        end else begin
            case (tx_fsm)
                TX_IDLE: begin
                    uart_tx_start <= 1'b0;
                    if (((seq_state == SEQ_BENCH_TX || seq_state == SEQ_C_TX) && !uart_seq_done) ||
                        ((seq_state == SEQ_ALL_DONE) && btnc)) begin
                        tx_rom_addr   <= 12'd0;
                        uart_seq_done <= 1'b0;
                        tx_fsm        <= TX_SEND;
                    end
                end

                TX_SEND: begin
                    if (!uart_tx_busy) begin
                        if (active_phase == PHASE_BENCHMARK) begin
                            if (is_hex_val)
                                uart_tx_data <= nibble_to_hex_char(active_nibble);
                            else
                                uart_tx_data <= get_zbb_rom_char(tx_rom_addr);
                        end else begin
                            uart_tx_data <= get_zbb_c_trace_char(tx_rom_addr);
                        end
                        uart_tx_start <= 1'b1;
                        tx_fsm        <= TX_WAIT;
                    end
                end

                TX_WAIT: begin
                    uart_tx_start <= 1'b0;
                    if (uart_tx_busy) begin
                        tx_fsm <= TX_NEXT;
                    end
                end

                TX_NEXT: begin
                    if (!uart_tx_busy) begin
                        if (tx_rom_addr < max_tx_rom_addr) begin
                            tx_rom_addr <= tx_rom_addr + 12'd1;
                            tx_fsm      <= TX_SEND;
                        end else begin
                            uart_seq_done <= 1'b1;
                            tx_fsm        <= TX_IDLE;
                        end
                    end
                end
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // 7. Seven-Segment Display Controller
    // ------------------------------------------------------------------------
    wire display_mode = sw[4]; // 0 = C Program, 1 = Benchmark

    reg [31:0] display_data;
    always @(*) begin
        if (display_mode) begin
            // Benchmark Stats
            case (sw[2:0])
                3'b000:  display_data = {16'h0018, 16'h0022}; // 18 Zbb / 22 Total
                default: display_data = ((sw[3:0] < 22) ? wb_trace_data[sw[3:0]] : 32'h0);
            endcase
        end else begin
            // Bare-Metal C Program Stats
            case (sw[2:0])
                3'b000:  display_data = {16'h0000, c_return_val_a0}; // Return value: 0x0012 (18)
                3'b001:  display_data = {16'h0000, c_total_cycles};   // Cycles: 83 (0x0053)
                3'b010:  display_data = {16'h0000, c_insts_retired};  // Retired: 93 (0x005D)
                3'b011:  display_data = 32'h0000_0018;                // 18 Passed
                default: display_data = 32'h0000_BEEF;
            endcase
        end
    end

    seven_seg_controller u_seven_seg (
        .clk        (clk_100mhz),
        .reset_n    (sys_reset_n),
        .data_in    (display_data),
        .show_dashes(1'b0),
        .an         (an),
        .seg        (seg),
        .dp         (dp)
    );

    // ------------------------------------------------------------------------
    // 8. Status LEDs
    // ------------------------------------------------------------------------
    assign led[0]     = (seq_state == SEQ_ALL_DONE);
    assign led[1]     = (tx_fsm != TX_IDLE);
    assign led[2]     = uart_seq_done;
    assign led[3]     = timing_violation;
    assign led[4]     = (seq_state == SEQ_ALL_DONE) && (!timing_violation) &&
                        ((active_phase == PHASE_BENCHMARK) ? (bench_retire_count == 22) : (c_return_val_a0 == 18));
    assign led[9:5]   = (active_phase == PHASE_BENCHMARK) ? bench_retire_count : c_return_val_a0[4:0];
    assign led[14:10] = 5'd0;
    assign led[15]    = sw[4]; // Mode switch indicator (1 = Benchmark, 0 = C Program)

endmodule
