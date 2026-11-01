// ============================================================================
// File: fpga_top_feature6.v
// Module: fpga_top_feature6
// Description: Synthesizable FPGA Top-Level Module for Feature 6:
//              RV32IMF Core with 2 KB L1 Instruction Cache & Dual UART Verification:
//              1. Synthetic JAL Benchmark (Trace Table, Mode Summary, Mode Comparison)
//              2. Bare-Metal C Program (icache.c like addition.c, completes in < 40 cycles approx)
// Target Board: Digilent Nexys A7-100T (Xilinx Artix-7 XC7A100T-1CSG324C)
// Clocks:
//   - 100 MHz Onboard Oscillator (CLK100MHZ, Pin E3)
//   - 50 MHz Core & UART Clock (derived via divide-by-2 toggle register clk_50mhz_reg)
// UART:
//   - 115200 Baud 8N1 (50 MHz / 434 clock divider) on Pin D4
// Controls:
//   - SW[0]   : I-Cache Mode (0 = Enabled, 1 = Bypassed)
//   - SW[2]   : Multiplier (1 = DSP48E1, 0 = Booth Radix-4)
//   - SW[3]   : 7-Seg Mode (0 = C Program Stats, 1 = Benchmark Stats)
//   - SW[4]   : Execution Mode:
//               0 = Automatic Sequential (Runs Benchmark, then C Program)
//               1 = Manual Selection: SW[5]=0 -> C Program only, SW[5]=1 -> Benchmark only
//   - SW[5:3] : 7-Seg Diagnostic Sub-mode
//   - SW[15]  : Hardware Single-Step Debug Mode (with BTNC)
//   - CPU_RESETN : Active-Low CPU Reset (Pin C12)
//   - BTNC    : Center Button (Debounced Single-Step / Comparison Reset)
// ============================================================================

`timescale 1ns/1ps

module fpga_top_feature6 #(
    parameter CLK_FREQ       = 50_000_000,
    parameter BAUD_RATE      = 115_200,
    parameter DEBOUNCE_LIMIT = 20'd1_000_000
)(
    input  wire        CLK100MHZ,      // 100 MHz onboard oscillator (Pin E3)
    input  wire        CPU_RESETN,     // Active-low CPU reset push button (Pin C12)
    input  wire        BTNC,           // Center push button: step / reset comparison
    input  wire [15:0] SW,             // Slide switches
    output wire [15:0] LED,            // Status and diagnostic LEDs
    output wire [7:0]  AN,             // 7-segment digit anodes (active low)
    output wire [6:0]  SEG,            // 7-segment cathode segments (active low)
    output wire        DP,             // 7-segment decimal point
    output wire        UART_TXD_IN     // Serial TX to FTDI USB-UART bridge (Pin D4)
);

    // ========================================================================
    // 1. Clock Generation: 50 MHz Core Clock
    // ========================================================================
    reg clk_50mhz_reg = 1'b0;
    always @(posedge CLK100MHZ) begin
        clk_50mhz_reg <= ~clk_50mhz_reg;
    end
    wire clk_50mhz = clk_50mhz_reg;

    // Synchronize active-low reset to 50 MHz clock domain
    reg [2:0] reset_sync = 3'b000;
    always @(posedge clk_50mhz or negedge CPU_RESETN) begin
        if (!CPU_RESETN)
            reset_sync <= 3'b000;
        else
            reset_sync <= {reset_sync[1:0], 1'b1};
    end
    wire reset_n = reset_sync[2];

    // Core soft reset control for resetting between Benchmark and C Program
    reg  core_soft_reset_n = 1'b1;
    wire core_reset_n = reset_n && core_soft_reset_n;

    // ------------------------------------------------------------------------
    // BTNC 20ms Digital Debouncer & Positive Edge Detector
    // ------------------------------------------------------------------------
    reg [2:0]  btnc_sync_reg = 3'b000;
    reg [19:0] btnc_timer = 20'd0;
    reg        btnc_debounced = 1'b0;
    reg        btnc_debounced_d = 1'b0;

    always @(posedge clk_50mhz or negedge reset_n) begin
        if (!reset_n) begin
            btnc_sync_reg       <= 3'b000;
            btnc_timer          <= 20'd0;
            btnc_debounced      <= 1'b0;
            btnc_debounced_d    <= 1'b0;
        end else begin
            btnc_sync_reg <= {btnc_sync_reg[1:0], BTNC};
            if (btnc_sync_reg[2] != btnc_debounced) begin
                if (btnc_timer == DEBOUNCE_LIMIT) begin
                    btnc_debounced <= btnc_sync_reg[2];
                    btnc_timer     <= 20'd0;
                end else begin
                    btnc_timer     <= btnc_timer + 20'd1;
                end
            end else begin
                btnc_timer <= 20'd0;
            end
            btnc_debounced_d <= btnc_debounced;
        end
    end

    wire btnc_step_pulse = btnc_debounced && !btnc_debounced_d;
    wire btnc_pressed    = btnc_step_pulse;

    // ========================================================================
    // 2. Execution Phases & Dual Sequencer States
    // ========================================================================
    localparam PHASE_BENCHMARK = 2'd0;
    localparam PHASE_C_PROGRAM = 2'd1;

    localparam SEQ_IDLE      = 3'd0;
    localparam SEQ_BENCH_RUN = 3'd1;
    localparam SEQ_BENCH_TX  = 3'd2;
    localparam SEQ_C_RESET   = 3'd3;
    localparam SEQ_C_RUN     = 3'd4;
    localparam SEQ_C_TX      = 3'd5;
    localparam SEQ_ALL_DONE  = 3'd6;

    reg [2:0] seq_state = SEQ_IDLE;
    reg [1:0] active_phase = PHASE_BENCHMARK;
    reg       core_freeze  = 1'b0;

    // ========================================================================
    // 3. Instruction & Data Memories
    // ========================================================================
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata_raw;
    wire        imem_req;

    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we;
    wire        dmem_re;
    wire [31:0] dmem_rdata;

    instr_mem #(
        .HEX_FILE ("imem.hex"),
        .WORDS    (1024)
    ) u_backing_imem (
        .clk   (clk_50mhz),
        .pc    (imem_addr),
        .instr (imem_rdata_raw)
    );

    data_mem #(
        .HEX_FILE ("dmem.hex"),
        .WORDS    (1024)
    ) u_backing_dmem (
        .clk   (clk_50mhz),
        .re    (dmem_re),
        .raddr (dmem_addr),
        .rdata (dmem_rdata),
        .we    (dmem_we),
        .waddr (dmem_addr),
        .wdata (dmem_wdata),
        .wstrb (dmem_wstrb)
    );

    // Hardcoded synthetic benchmark instructions (Phase 1)
    wire [31:0] bench_instr = (imem_addr == 32'h00) ? 32'h0000_0093 : // addi x1, x0, 0
                              (imem_addr == 32'h04) ? 32'h0000_0113 : // addi x2, x0, 0
                              (imem_addr == 32'h08) ? 32'h0010_8093 : // addi x1, x1, 1
                              (imem_addr == 32'h0C) ? 32'h0011_0133 : // add  x2, x2, x1
                              (imem_addr == 32'h10) ? 32'hFF9F_F06F : // jal  x0, -8
                              32'h0000_0013;                          // nop

    reg saw_c_ret = 1'b0;

    // Active instruction multiplexer
    wire [31:0] core_imem_rdata = (active_phase == PHASE_BENCHMARK) ? bench_instr :
                                  (saw_c_ret ? 32'h0000_0013 : imem_rdata_raw);

    // ========================================================================
    // 4. Pipeline Telemetry Signals
    // ========================================================================
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
    wire        branch_or_jump_taken;
    wire        jal_taken_id;
    wire [31:0] core_inst_if;
    wire [31:0] core_inst_id;

    // L1 I-Cache Diagnostics
    wire        icache_stall;
    wire        icache_hit;
    wire        icache_miss;
    wire [31:0] icache_hit_count;
    wire [31:0] icache_miss_count;
    wire [1:0]  icache_state;
    wire [3:0]  icache_refill_cnt;
    wire [31:0] icache_latched_pc;
    wire        icache_just_refilled;

    // ========================================================================
    // 5. Run Controllers, Performance Counters & Trace Buffer
    // ========================================================================
    reg        latched_mode = 1'b0;   // Latched SW[0] at start of run
    reg        bench_run_done = 1'b0;
    reg [1:0]  jal_loop_cnt = 2'd0;
    reg [31:0] final_halt_pc = 32'h0000_0010;

    reg [15:0] bench_cyc     = 16'd1;
    reg [15:0] bench_halted_cycles = 16'd0;
    reg [15:0] bench_insts   = 16'd0;
    reg [15:0] bench_hits    = 16'd0;
    reg [15:0] bench_misses  = 16'd0;

    // Bare-Metal C Program Performance Counters
    reg [15:0] c_total_cycles  = 16'd1;
    reg [15:0] c_insts_retired = 16'd0;
    reg [15:0] c_hits          = 16'd0;
    reg [15:0] c_misses        = 16'd0;
    reg [15:0] c_return_val_a0 = 16'd0;
    reg [2:0]  c_drain_cnt     = 3'd0;
    reg        c_run_done      = 1'b0;
    reg [3:0]  c_reset_timer   = 4'd0;
    reg [7:0]  c_trace_len     = 8'd0;

    // 256-entry Trace Buffer: {status_code[3:0], cyc[15:0], pc[31:0], inst[31:0]}
    (* ram_style = "block" *) reg [83:0] trace_mem [0:255];
    reg [7:0]  trace_len = 8'd0;
    wire [7:0] trace_rd_addr;
    reg [83:0] trace_rd_data;

    reg        trace_wr_en = 1'b0;
    reg [83:0] trace_wr_data = 84'd0;
    reg [7:0]  trace_wr_addr = 8'd0;

    always @(posedge clk_50mhz) begin
        if (trace_wr_en) begin
            trace_mem[trace_wr_addr] <= trace_wr_data;
        end
        trace_rd_data <= trace_mem[trace_rd_addr];
    end

    // Persistent Historical Stats for Comparison
    reg        mode0_valid        = 1'b0;
    reg [15:0] mode0_instructions = 16'd0;
    reg [15:0] mode0_cycles       = 16'd0;
    reg [15:0] mode0_hits         = 16'd0;
    reg [15:0] mode0_misses       = 16'd0;

    reg        mode1_valid        = 1'b0;
    reg [15:0] mode1_instructions = 16'd0;
    reg [15:0] mode1_cycles       = 16'd0;
    reg [15:0] mode1_hits         = 16'd0;
    reg [15:0] mode1_misses       = 16'd0;

    // UART print engine triggers
    reg start_print        = 1'b0;
    reg start_print_c      = 1'b0;
    reg step_print_banner  = 1'b0;
    reg step_print_row     = 1'b0;
    reg [7:0] step_row_addr = 8'd0;
    reg step_print_summary = 1'b0;
    reg banner_printed_for_step = 1'b0;

    wire printer_busy;
    wire printer_done;

    // Hardware Step Mode
    wire step_mode_active = SW[15];
    wire can_step         = step_mode_active ? (btnc_step_pulse && !printer_busy) : 1'b1;
    wire core_clk_en      = (seq_state == SEQ_BENCH_RUN || seq_state == SEQ_C_RUN) && !core_freeze && can_step;
    wire stall_core       = !core_clk_en;

    // In Continuous Mode, BTNC resets comparison history
    always @(posedge clk_50mhz) begin
        if (!step_mode_active && btnc_pressed) begin
            mode0_valid <= 1'b0;
            mode1_valid <= 1'b0;
        end
    end

    // ========================================================================
    // 6. Dual Sequencer Controller FSM
    // ========================================================================
    always @(posedge clk_50mhz or negedge reset_n) begin
        if (!reset_n) begin
            latched_mode             <= SW[0];
            seq_state                <= SEQ_IDLE;
            active_phase             <= PHASE_BENCHMARK;
            core_soft_reset_n        <= 1'b1;
            core_freeze              <= 1'b0;

            // Benchmark resets
            bench_run_done           <= 1'b0;
            start_print              <= 1'b0;
            start_print_c            <= 1'b0;
            step_print_banner        <= 1'b0;
            step_print_row           <= 1'b0;
            step_row_addr            <= 8'd0;
            step_print_summary       <= 1'b0;
            banner_printed_for_step  <= 1'b0;
            jal_loop_cnt             <= 2'd0;
            bench_cyc                <= 16'd1;
            bench_halted_cycles      <= 16'd0;
            bench_insts              <= 16'd0;
            bench_hits               <= 16'd0;
            bench_misses             <= 16'd0;
            trace_len                <= 8'd0;
            final_halt_pc            <= 32'h0000_0010;
            trace_wr_en              <= 1'b0;

            // C program resets
            c_total_cycles           <= 16'd1;
            c_insts_retired          <= 16'd0;
            c_hits                   <= 16'd0;
            c_misses                 <= 16'd0;
            c_return_val_a0          <= 16'd0;
            saw_c_ret                <= 1'b0;
            c_drain_cnt              <= 3'd0;
            c_run_done               <= 1'b0;
            c_reset_timer            <= 4'd0;
            c_trace_len              <= 8'd0;
        end else begin
            start_print        <= 1'b0;
            start_print_c      <= 1'b0;
            step_print_banner  <= 1'b0;
            step_print_row     <= 1'b0;
            step_print_summary <= 1'b0;
            trace_wr_en        <= 1'b0;

            case (seq_state)
                SEQ_IDLE: begin
                    core_freeze <= 1'b0;
                    latched_mode <= SW[0];

                    if (SW[4] && !SW[5]) begin
                        // Manual Mode: C Program only
                        active_phase      <= PHASE_C_PROGRAM;
                        core_soft_reset_n <= 1'b0;
                        c_reset_timer     <= 4'd0;
                        seq_state         <= SEQ_C_RESET;
                    end else begin
                        // Default Sequential Mode or Benchmark only (SW[4] && SW[5])
                        active_phase      <= PHASE_BENCHMARK;
                        core_soft_reset_n <= 1'b1;
                        seq_state         <= SEQ_BENCH_RUN;
                    end
                end

                // ------------------------------------------------------------
                // Phase 1: Synthetic Benchmark Run State
                // ------------------------------------------------------------
                SEQ_BENCH_RUN: begin
                    if (step_mode_active && !banner_printed_for_step && !printer_busy) begin
                        step_print_banner       <= 1'b1;
                        banner_printed_for_step <= 1'b1;
                    end

                    if (!bench_run_done && can_step) begin
                        bench_cyc <= bench_cyc + 16'd1;

                        if (jal_taken_id) begin
                            // JAL in ID: flushed instruction at PC=0x00000014
                            trace_wr_en   <= 1'b1;
                            trace_wr_addr <= trace_len;
                            trace_wr_data <= {4'd11, bench_cyc, 32'h0000_0014, 32'h0000_0013};

                            if (step_mode_active) begin
                                step_print_row <= 1'b1;
                                step_row_addr  <= trace_len;
                            end
                            trace_len    <= trace_len + 8'd1;
                            jal_loop_cnt <= jal_loop_cnt + 2'd1;

                            if (jal_loop_cnt == 2'd2) begin
                                // 3rd JAL completion reached! Stop core and trigger summary print
                                bench_run_done      <= 1'b1;
                                core_freeze         <= 1'b1;
                                final_halt_pc       <= 32'h0000_0010;
                                bench_halted_cycles <= bench_cyc;

                                if (!step_mode_active) begin
                                    start_print <= 1'b1;
                                end else begin
                                    step_print_summary <= 1'b1;
                                end

                                if (!latched_mode) begin
                                    mode0_valid        <= 1'b1;
                                    mode0_instructions <= bench_insts;
                                    mode0_cycles       <= bench_cyc;
                                    mode0_hits         <= bench_hits;
                                    mode0_misses       <= bench_misses;
                                end else begin
                                    mode1_valid        <= 1'b1;
                                    mode1_instructions <= bench_insts;
                                    mode1_cycles       <= bench_cyc;
                                    mode1_hits         <= bench_hits;
                                    mode1_misses       <= bench_misses;
                                end
                                seq_state <= SEQ_BENCH_TX;
                            end
                        end else begin
                            case (icache_state)
                                2'b00: begin // STATE_IDLE
                                    if (icache_just_refilled) begin
                                        trace_wr_en   <= 1'b1;
                                        trace_wr_addr <= trace_len;
                                        trace_wr_data <= {4'd10, bench_cyc, pc_if, bench_instr};
                                        if (step_mode_active) begin
                                            step_print_row <= 1'b1;
                                            step_row_addr  <= trace_len;
                                        end
                                        trace_len   <= trace_len + 8'd1;
                                        bench_insts <= bench_insts + 16'd1;
                                    end else if (icache_hit) begin
                                        trace_wr_en   <= 1'b1;
                                        trace_wr_addr <= trace_len;
                                        trace_wr_data <= {4'd0, bench_cyc, pc_if, bench_instr};
                                        if (step_mode_active) begin
                                            step_print_row <= 1'b1;
                                            step_row_addr  <= trace_len;
                                        end
                                        trace_len   <= trace_len + 8'd1;
                                        bench_hits  <= bench_hits + 16'd1;
                                        bench_insts <= bench_insts + 16'd1;
                                    end else if (icache_miss) begin
                                        trace_wr_en   <= 1'b1;
                                        trace_wr_addr <= trace_len;
                                        trace_wr_data <= {4'd1, bench_cyc, pc_if, bench_instr};
                                        if (step_mode_active) begin
                                            step_print_row <= 1'b1;
                                            step_row_addr  <= trace_len;
                                        end
                                        trace_len    <= trace_len + 8'd1;
                                        bench_misses <= bench_misses + 16'd1;
                                    end
                                end

                                2'b01: begin // STATE_REFILL
                                    trace_wr_en   <= 1'b1;
                                    trace_wr_addr <= trace_len;
                                    trace_wr_data <= {4'd2 + icache_refill_cnt, bench_cyc, icache_latched_pc, bench_instr};
                                    if (step_mode_active) begin
                                        step_print_row <= 1'b1;
                                        step_row_addr  <= trace_len;
                                    end
                                    trace_len <= trace_len + 8'd1;
                                end

                                2'b10: begin // STATE_BYPASS
                                    trace_wr_en   <= 1'b1;
                                    trace_wr_addr <= trace_len;
                                    trace_wr_data <= {4'd10, bench_cyc, icache_latched_pc, bench_instr};
                                    if (step_mode_active) begin
                                        step_print_row <= 1'b1;
                                        step_row_addr  <= trace_len;
                                    end
                                    trace_len   <= trace_len + 8'd1;
                                    bench_insts <= bench_insts + 16'd1;
                                end
                            endcase
                        end
                    end
                end

                // ------------------------------------------------------------
                // Phase 1: Benchmark UART Output Wait State
                // ------------------------------------------------------------
                SEQ_BENCH_TX: begin
                    if (printer_done) begin
                        if (SW[4] && SW[5]) begin
                            // Manual mode: Benchmark only
                            seq_state <= SEQ_ALL_DONE;
                        end else begin
                            // Sequential mode: Proceed to Bare-Metal C Program
                            active_phase      <= PHASE_C_PROGRAM;
                            core_soft_reset_n <= 1'b0;
                            c_reset_timer     <= 4'd0;
                            seq_state         <= SEQ_C_RESET;
                        end
                    end
                end

                // ------------------------------------------------------------
                // Transition to C Program: Core Reset
                // ------------------------------------------------------------
                SEQ_C_RESET: begin
                    core_freeze <= 1'b0;
                    if (c_reset_timer < 4'd8) begin
                        c_reset_timer     <= c_reset_timer + 4'd1;
                        core_soft_reset_n <= 1'b0;
                    end else begin
                        core_soft_reset_n <= 1'b1;
                        trace_len         <= 8'd0;
                        c_total_cycles    <= 16'd1;
                        c_insts_retired   <= 16'd0;
                        c_hits            <= 16'd0;
                        c_misses          <= 16'd0;
                        c_return_val_a0   <= 16'd0;
                        saw_c_ret         <= 1'b0;
                        c_drain_cnt       <= 3'd0;
                        c_run_done        <= 1'b0;
                        c_trace_len       <= 8'd0;
                        seq_state         <= SEQ_C_RUN;
                    end
                end

                // ------------------------------------------------------------
                // Phase 2: Bare-Metal C Program Execution State
                // ------------------------------------------------------------
                SEQ_C_RUN: begin
                    if (!c_run_done && can_step) begin
                        c_total_cycles <= c_total_cycles + 16'd1;

                        if (wb_reg_write && !hazard_stall) begin
                            c_insts_retired <= c_insts_retired + 16'd1;
                            if (wb_dest_reg == 5'd10) begin
                                c_return_val_a0 <= wb_data[15:0];
                            end
                        end

                        // Detect ret (0x00008067) decoded in ID stage
                        if (core_inst_id == 32'h0000_8067 && !hazard_stall && pc_id != 32'd0 && !saw_c_ret) begin
                            saw_c_ret   <= 1'b1;
                            c_drain_cnt <= 3'd0;
                        end

                        // Log cycle-by-cycle trace for C Program
                        case (icache_state)
                            2'b00: begin // IDLE
                                if (icache_just_refilled) begin
                                    trace_wr_en   <= 1'b1;
                                    trace_wr_addr <= trace_len;
                                    trace_wr_data <= {4'd10, c_total_cycles, pc_if, core_inst_if};
                                    trace_len     <= trace_len + 8'd1;
                                end else if (icache_hit) begin
                                    trace_wr_en   <= 1'b1;
                                    trace_wr_addr <= trace_len;
                                    trace_wr_data <= {4'd0, c_total_cycles, pc_if, core_inst_if};
                                    trace_len     <= trace_len + 8'd1;
                                    c_hits        <= c_hits + 16'd1;
                                end else if (icache_miss) begin
                                    trace_wr_en   <= 1'b1;
                                    trace_wr_addr <= trace_len;
                                    trace_wr_data <= {4'd1, c_total_cycles, pc_if, core_inst_if};
                                    trace_len     <= trace_len + 8'd1;
                                    c_misses      <= c_misses + 16'd1;
                                end
                            end

                            2'b01: begin // REFILL
                                trace_wr_en   <= 1'b1;
                                trace_wr_addr <= trace_len;
                                trace_wr_data <= {4'd2 + icache_refill_cnt, c_total_cycles, icache_latched_pc, core_inst_if};
                                trace_len     <= trace_len + 8'd1;
                            end

                            2'b10: begin // BYPASS
                                trace_wr_en   <= 1'b1;
                                trace_wr_addr <= trace_len;
                                trace_wr_data <= {4'd10, c_total_cycles, icache_latched_pc, core_inst_if};
                                trace_len     <= trace_len + 8'd1;
                            end
                        endcase

                        if (saw_c_ret) begin
                            if (c_drain_cnt < 3'd3) begin
                                c_drain_cnt <= c_drain_cnt + 3'd1;
                            end else begin
                                c_run_done    <= 1'b1;
                                core_freeze   <= 1'b1;
                                c_trace_len   <= trace_len;
                                start_print_c <= 1'b1;
                                seq_state     <= SEQ_C_TX;
                            end
                        end
                    end
                end

                // ------------------------------------------------------------
                // Phase 2: C Program UART Output State
                // ------------------------------------------------------------
                SEQ_C_TX: begin
                    if (printer_done) begin
                        seq_state <= SEQ_ALL_DONE;
                    end
                end

                // ------------------------------------------------------------
                // All Tests Completed State
                // ------------------------------------------------------------
                SEQ_ALL_DONE: begin
                    core_freeze <= 1'b1;
                end
            endcase
        end
    end

    // ========================================================================
    // 7. Pipelined RV32IMF Core with L1 I-Cache
    // ========================================================================
    pipeline_5stage #(
        .RESET_PC     (32'h0000_0000),
        .HIT_TIME     (1),
        .MISS_PENALTY (9)
    ) u_core (
        .clk                    (clk_50mhz),
        .reset_n                (core_reset_n),
        .stall_ext              (stall_core),
        .use_dsp_i              (SW[2]),
        .icache_bypass_i        (latched_mode),
        .imem_addr              (imem_addr),
        .imem_rdata             (core_imem_rdata),
        .imem_req               (imem_req),
        .dmem_addr              (dmem_addr),
        .dmem_wdata             (dmem_wdata),
        .dmem_wstrb             (dmem_wstrb),
        .dmem_we                (dmem_we),
        .dmem_re                (dmem_re),
        .dmem_rdata             (dmem_rdata),
        .pc_if                  (pc_if),
        .pc_id                  (pc_id),
        .pc_ex                  (pc_ex),
        .pc_mem                 (pc_mem),
        .pc_wb                  (pc_wb),
        .wb_reg_write           (wb_reg_write),
        .wb_dest_reg            (wb_dest_reg),
        .wb_data                (wb_data),
        .hazard_stall           (hazard_stall),
        .hazard_flush_id        (hazard_flush_id),
        .hazard_flush_ex        (hazard_flush_ex),
        .forward_a              (forward_a),
        .forward_b              (forward_b),
        .mul_active             (mul_active),
        .div_active             (div_active),
        .div_busy               (div_busy),
        .fpu_active             (fpu_active),
        .fpu_busy               (fpu_busy),
        .exception              (exception),
        .icache_stall           (icache_stall),
        .icache_hit             (icache_hit),
        .icache_miss            (icache_miss),
        .icache_hit_count       (icache_hit_count),
        .icache_miss_count      (icache_miss_count),
        .branch_or_jump_taken_o (branch_or_jump_taken),
        .jal_taken_id_o         (jal_taken_id),
        .icache_state_o         (icache_state),
        .icache_refill_cnt_o    (icache_refill_cnt),
        .icache_latched_pc_o    (icache_latched_pc),
        .icache_just_refilled_o (icache_just_refilled),
        .inst_if                (core_inst_if),
        .inst_id                (core_inst_id)
    );

    // ========================================================================
    // 8. Formatted UART Output Engine
    // ========================================================================
    wire uart_tx_line;

    icache_uart_printer #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_printer (
        .clk                (clk_50mhz),
        .reset_n            (reset_n),
        .start_print        (start_print),
        .print_banner_only  (step_print_banner),
        .print_single_row   (step_print_row),
        .single_row_addr    (step_row_addr),
        .print_summary_only (step_print_summary),
        .mode_bypassed      (latched_mode),
        .trace_len          (trace_len),
        .trace_rd_addr      (trace_rd_addr),
        .trace_rd_data      (trace_rd_data),
        .stat_instructions  (bench_insts),
        .stat_cycles        (bench_halted_cycles),
        .stat_hits          (bench_hits),
        .stat_misses        (bench_misses),
        .mode0_valid        (mode0_valid),
        .mode0_instructions (mode0_instructions),
        .mode0_cycles       (mode0_cycles),
        .mode0_hits         (mode0_hits),
        .mode0_misses       (mode0_misses),
        .mode1_valid        (mode1_valid),
        .mode1_instructions (mode1_instructions),
        .mode1_cycles       (mode1_cycles),
        .mode1_hits         (mode1_hits),
        .mode1_misses       (mode1_misses),
        .start_print_c      (start_print_c),
        .c_stat_instructions(c_insts_retired),
        .c_stat_cycles      (c_total_cycles),
        .c_stat_hits        (c_hits),
        .c_stat_misses      (c_misses),
        .c_stat_return_val  (c_return_val_a0),
        .c_trace_len        (c_trace_len),
        .uart_tx            (uart_tx_line),
        .print_busy         (printer_busy),
        .print_done         (printer_done)
    );

    assign UART_TXD_IN = uart_tx_line;

    // ========================================================================
    // 9. Diagnostic LEDs
    // ========================================================================
    reg [21:0] icache_hit_timer  = 22'd0;
    reg [21:0] icache_miss_timer = 22'd0;
    localparam STRETCH_CYCLES = 22'd2_500_000; // ~50 ms pulse at 50 MHz

    always @(posedge clk_50mhz or negedge reset_n) begin
        if (!reset_n) begin
            icache_hit_timer  <= 22'd0;
            icache_miss_timer <= 22'd0;
        end else begin
            if (icache_hit)
                icache_hit_timer <= STRETCH_CYCLES;
            else if (icache_hit_timer != 0)
                icache_hit_timer <= icache_hit_timer - 1'b1;

            if (icache_miss)
                icache_miss_timer <= STRETCH_CYCLES;
            else if (icache_miss_timer != 0)
                icache_miss_timer <= icache_miss_timer - 1'b1;
        end
    end

    // Heartbeat counter (LED[15])
    reg [24:0] heartbeat_cnt = 25'd0;
    always @(posedge clk_50mhz) heartbeat_cnt <= heartbeat_cnt + 1'b1;

    assign LED[0]  = (seq_state == SEQ_BENCH_RUN);             // Benchmark executing
    assign LED[1]  = bench_run_done;                           // Benchmark run completed
    assign LED[2]  = latched_mode;                             // Active mode (0: Enabled, 1: Bypassed)
    assign LED[3]  = printer_busy;                             // UART printer active
    assign LED[4]  = printer_done;                             // UART transmission completed
    assign LED[5]  = (seq_state == SEQ_C_RUN);                 // C program executing
    assign LED[6]  = c_run_done;                               // C program completed
    assign LED[7]  = bench_run_done && c_run_done;             // Both tests completed!
    assign LED[8]  = (icache_hit_timer != 0);                  // I-Cache Hit pulse (Green)
    assign LED[9]  = (icache_miss_timer != 0);                 // I-Cache Miss pulse (Orange)
    assign LED[10] = step_mode_active;                         // Step Mode Active (SW[15]=1)
    assign LED[11] = btnc_debounced;                           // Clean BTNC state
    assign LED[12] = div_busy || fpu_busy;
    assign LED[13] = hazard_stall;
    assign LED[14] = (active_phase == PHASE_C_PROGRAM);        // Active phase (1: C Program)
    assign LED[15] = heartbeat_cnt[24];                        // Alive blink

    // ========================================================================
    // 10. Seven-Segment Multiplexed Display Controller
    // ========================================================================
    reg [31:0] display_data;
    always @(*) begin
        if (!SW[3]) begin
            // SW[3] = 0: Bare-Metal C Program telemetry
            case (SW[5:4])
                2'b00: display_data = {16'h0, c_return_val_a0}; // Return value a0 (0x0025 = 37)
                2'b01: display_data = {16'h0, c_total_cycles};  // C program clock cycles (~32)
                2'b10: display_data = {16'h0, c_hits};          // C program I-Cache Hits (~11)
                2'b11: display_data = {16'h0, c_misses};        // C program I-Cache Misses (~2)
            endcase
        end else begin
            // SW[3] = 1: Benchmark telemetry
            case (SW[5:3])
                3'b001: display_data = {16'h0, bench_run_done ? bench_halted_cycles : bench_cyc};
                3'b011: display_data = {16'h0, bench_misses};
                3'b101: display_data = {27'h0, wb_dest_reg};
                3'b111: display_data = 32'h0000_0006;           // Feature 6 Tag
                default: display_data = bench_run_done ? final_halt_pc : pc_wb;
            endcase
        end
    end

    seven_seg_controller u_seven_seg (
        .clk         (clk_50mhz),
        .reset_n     (reset_n),
        .data_in     (display_data),
        .show_dashes (1'b0),
        .an          (AN),
        .seg         (SEG),
        .dp          (DP)
    );

endmodule
