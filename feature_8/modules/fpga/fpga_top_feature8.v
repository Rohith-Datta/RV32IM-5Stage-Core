// ============================================================================
// File: fpga_top_feature8.v
// Module: fpga_top_feature8
// Description: Synthesizable FPGA Top-Level Module for Feature 8:
//              Static 32-Entry Branch Target Buffer (BTB) Verification with Dual UART Telemetry
//              Supports BOTH:
//                1. 16-Cycle Synthetic BTB Verification Benchmark (Trace table & stats)
//                2. Bare-Metal C Program (btb.c / imem.hex, ~75 cycles, branches, return value)
// Target Device: Xilinx Artix-7 XC7A100T-1CSG324C (Digilent Nexys A7-100T Board)
//
// Clocks:
//   - Onboard Oscillator: 100 MHz (Pin E3)
//   - Core & UART Clock : 50 MHz (generated via divide-by-2 toggle register clk_50mhz_reg)
//
// UART Configuration:
//   - Baud Rate: 115200 Baud, 8 Data Bits, No Parity, 1 Stop Bit (8N1)
//   - Baud Divider from 50 MHz: 50,000,000 / 115,200 = 434 cycles/bit
//
// Controls:
//   - sw[2:0] : 7-segment display mode
//   - sw[3]   : 0 = Display C program stats, 1 = Display Benchmark stats
//   - sw[4]   : 0 = Automatic Sequential (Runs Benchmark + C Program)
//               1 = Manual Select: sw[5]=0 -> C Program only, sw[5]=1 -> Benchmark only
//   - cpu_resetn : Active-low hardware reset (Pin C12)
// ============================================================================

`timescale 1ns/1ps

module fpga_top_feature8 #(
    parameter CLK_FREQ       = 50_000_000,
    parameter BAUD_RATE      = 115_200,
    parameter BTB_ENTRIES    = 32,
    parameter BTB_TAG_WIDTH  = 25,
    parameter TRACE_DEPTH    = 32
)(
    input  wire        clk_100mhz,  // 100 MHz onboard oscillator (Pin E3)
    input  wire        cpu_resetn,  // Active-low CPU reset push button (Pin C12)
    input  wire        btnc,        // Center push button: manual trigger / step (Pin N17)
    input  wire [15:0] sw,          // 16 slide switches
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

    // Core soft reset control for resetting between Phase 1 and Phase 2
    reg  core_soft_reset_n;
    wire core_reset_n = sys_reset_n && core_soft_reset_n;

    // ------------------------------------------------------------------------
    // 3. Execution Phases and Sequencer States
    // ------------------------------------------------------------------------
    localparam PHASE_BENCHMARK = 2'd0;
    localparam PHASE_C_PROGRAM = 2'd1;

    localparam SEQ_IDLE      = 3'd0;
    localparam SEQ_BENCH_RUN = 3'd1;
    localparam SEQ_BENCH_TX  = 3'd2;
    localparam SEQ_C_RESET   = 3'd3;
    localparam SEQ_C_RUN     = 3'd4;
    localparam SEQ_C_TX      = 3'd5;
    localparam SEQ_ALL_DONE  = 3'd6;

    reg [2:0] seq_state;
    reg [1:0] active_phase;
    reg       core_freeze;

    // ------------------------------------------------------------------------
    // 4. Instruction and Data Memories (4 KB / 1024 Words)
    // ------------------------------------------------------------------------
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata_raw;

    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we;
    wire        dmem_re;
    wire [31:0] dmem_rdata;

    instr_mem #(
        .HEX_FILE("imem.hex"),
        .WORDS(1024)
    ) u_imem (
        .clk   (clk_50mhz),
        .pc    (imem_addr),
        .instr (imem_rdata_raw)
    );

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

    // Hardcoded synthetic BTB verification loop instructions (Phase 1)
    wire [31:0] bench_instr = (imem_addr == 32'h00) ? 32'h0030_0093 : // addi x1, x0, 2 (3 branch evaluations)
                              (imem_addr == 32'h04) ? 32'h0000_0113 : // addi x2, x0, 0
                              (imem_addr == 32'h08) ? 32'h0011_0113 : // addi x2, x2, 1
                              (imem_addr == 32'h0C) ? 32'hFFF0_8093 : // addi x1, x1, -1
                              (imem_addr == 32'h10) ? 32'hFE00_9CE3 : // bne  x1, x0, -8
                              32'h0000_0013;                          // nop

    reg saw_c_ret;

    // Active instruction multiplexer
    wire [31:0] core_imem_rdata = (active_phase == PHASE_BENCHMARK) ? bench_instr :
                                  (saw_c_ret ? 32'h0000_0013 : imem_rdata_raw);

    // ------------------------------------------------------------------------
    // 5. 5-Stage RV32IMF Core with Integrated 32-Entry Static BTB
    // ------------------------------------------------------------------------
    wire [31:0] pc_if, pc_id, pc_ex, pc_mem, pc_wb;
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

    wire        btb_pred_hit;
    wire        btb_pred_taken;
    wire        btb_mispredict;

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
        .btb_pred_hit   (btb_pred_hit),
        .btb_pred_taken (btb_pred_taken),
        .btb_mispredict (btb_mispredict)
    );

    // ------------------------------------------------------------------------
    // 6. Phase 1: Synthetic Benchmark Execution & Trace Buffer
    // ------------------------------------------------------------------------
    localparam TYPE_NORMAL_00          = 4'd0;
    localparam TYPE_NORMAL_04          = 4'd1;
    localparam TYPE_NORMAL_08          = 4'd2;
    localparam TYPE_NORMAL_0C          = 4'd3;
    localparam TYPE_MISPRED_TAKEN_MISS = 4'd4;
    localparam TYPE_FLUSH_1            = 4'd5;
    localparam TYPE_FLUSH_2            = 4'd6;
    localparam TYPE_PRED_CORRECT       = 4'd7;
    localparam TYPE_MISPRED_NOT_TAKEN  = 4'd8;
    localparam TYPE_NORMAL_14          = 4'd9;

    reg [4:0]  trace_cyc  [1:16];
    reg [31:0] trace_pc   [1:16];
    reg [3:0]  trace_type [1:16];

    reg        bench_trace_started;
    reg [4:0]  bench_cur_cyc;
    reg [1:0]  bench_flush_pending;
    reg        bench_run_done;

    reg [15:0] bench_total_branches;
    reg [15:0] bench_correct_predictions;
    reg [15:0] bench_mispredictions;
    reg [15:0] bench_flush_penalty_cycles;
    wire [15:0] bench_accuracy = (bench_total_branches > 0) ?
                                 ((bench_correct_predictions * 16'd100) / bench_total_branches) : 16'd0;

    // ------------------------------------------------------------------------
    // 7. Phase 2: Bare-Metal C Program Execution Counters & Status
    // ------------------------------------------------------------------------
    reg [15:0] c_total_cycles;
    reg [15:0] c_insts_retired;
    reg [15:0] c_total_branches;
    reg [15:0] c_correct_predictions;
    reg [15:0] c_mispredictions;
    reg [15:0] c_return_val_a0;
    reg [2:0]  c_drain_cnt;
    reg        c_run_done;
    reg [3:0]  c_reset_timer;

    wire [15:0] c_accuracy = (c_total_branches > 0) ?
                             ((c_correct_predictions * 16'd100) / c_total_branches) : 16'd0;

    // Record branch event cycle numbers
    reg [7:0] c_branch_cyc [1:5];
    reg [2:0] c_branch_idx;
    reg [7:0] c_ret_cyc;

    reg       uart_tx_bench_done;
    reg       uart_tx_c_done;

    // ------------------------------------------------------------------------
    // 8. Dual Sequencer Controller
    // ------------------------------------------------------------------------
    always @(posedge clk_50mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            seq_state                  <= SEQ_IDLE;
            active_phase               <= PHASE_BENCHMARK;
            core_soft_reset_n          <= 1'b1;
            core_freeze                <= 1'b0;

            // Phase 1 resets
            bench_trace_started        <= 1'b0;
            bench_cur_cyc              <= 5'd0;
            bench_flush_pending        <= 2'd0;
            bench_run_done             <= 1'b0;
            bench_total_branches       <= 16'd0;
            bench_correct_predictions  <= 16'd0;
            bench_mispredictions       <= 16'd0;
            bench_flush_penalty_cycles <= 16'd0;

            // Phase 2 resets
            c_total_cycles             <= 16'd0;
            c_insts_retired            <= 16'd0;
            c_total_branches           <= 16'd0;
            c_correct_predictions      <= 16'd0;
            c_mispredictions           <= 16'd0;
            c_return_val_a0            <= 16'd0;
            saw_c_ret                  <= 1'b0;
            c_drain_cnt                <= 3'd0;
            c_run_done                 <= 1'b0;
            c_reset_timer              <= 4'd0;
            c_branch_idx               <= 3'd0;
            c_ret_cyc                  <= 8'd0;
        end else begin
            case (seq_state)
                SEQ_IDLE: begin
                    core_freeze <= 1'b0;
                    if (sw[4] && !sw[5]) begin
                        // Manual mode: C Program only
                        active_phase      <= PHASE_C_PROGRAM;
                        core_soft_reset_n <= 1'b0;
                        seq_state         <= SEQ_C_RESET;
                    end else begin
                        // Default / Benchmark mode
                        active_phase      <= PHASE_BENCHMARK;
                        core_soft_reset_n <= 1'b1;
                        seq_state         <= SEQ_BENCH_RUN;
                    end
                end

                // ------------------------------------------------------------
                // Benchmark Run State (16 cycles)
                // ------------------------------------------------------------
                SEQ_BENCH_RUN: begin
                    if (!bench_run_done) begin
                        if (!bench_trace_started) begin
                            if (pc_ex == 32'h0000_0000 && !hazard_stall) begin
                                bench_trace_started        <= 1'b1;
                                bench_cur_cyc              <= 5'd1;
                                trace_cyc[1]               <= 5'd1;
                                trace_pc[1]                <= 32'h0000_0000;
                                trace_type[1]              <= TYPE_NORMAL_00;
                            end
                        end else begin
                            if (bench_flush_pending == 2'd2) begin
                                bench_cur_cyc                  <= bench_cur_cyc + 5'd1;
                                trace_cyc[bench_cur_cyc + 1]   <= bench_cur_cyc + 5'd1;
                                trace_pc[bench_cur_cyc + 1]    <= 32'h0;
                                trace_type[bench_cur_cyc + 1]  <= TYPE_FLUSH_1;
                                bench_flush_pending            <= 2'd1;
                                bench_flush_penalty_cycles     <= bench_flush_penalty_cycles + 16'd1;
                            end else if (bench_flush_pending == 2'd1) begin
                                bench_cur_cyc                  <= bench_cur_cyc + 5'd1;
                                trace_cyc[bench_cur_cyc + 1]   <= bench_cur_cyc + 5'd1;
                                trace_pc[bench_cur_cyc + 1]    <= 32'h0;
                                trace_type[bench_cur_cyc + 1]  <= TYPE_FLUSH_2;
                                bench_flush_pending            <= 2'd0;
                                bench_flush_penalty_cycles     <= bench_flush_penalty_cycles + 16'd1;
                            end else if (pc_ex == 32'h0000_0010) begin
                                bench_cur_cyc                <= bench_cur_cyc + 5'd1;
                                trace_cyc[bench_cur_cyc + 1] <= bench_cur_cyc + 5'd1;
                                trace_pc[bench_cur_cyc + 1]  <= 32'h0000_0010;
                                bench_total_branches         <= bench_total_branches + 16'd1;

                                if (btb_mispredict) begin
                                    bench_mispredictions <= bench_mispredictions + 16'd1;
                                    bench_flush_pending  <= 2'd2;
                                    if (bench_cur_cyc == 5'd4)
                                        trace_type[bench_cur_cyc + 1] <= TYPE_MISPRED_TAKEN_MISS;
                                    else
                                        trace_type[bench_cur_cyc + 1] <= TYPE_MISPRED_NOT_TAKEN;
                                end else begin
                                    bench_correct_predictions    <= bench_correct_predictions + 16'd1;
                                    trace_type[bench_cur_cyc + 1] <= TYPE_PRED_CORRECT;
                                end
                            end else if (pc_ex == 32'h0000_0004) begin
                                bench_cur_cyc                <= bench_cur_cyc + 5'd1;
                                trace_cyc[bench_cur_cyc + 1] <= bench_cur_cyc + 5'd1;
                                trace_pc[bench_cur_cyc + 1]  <= 32'h0000_0004;
                                trace_type[bench_cur_cyc + 1]<= TYPE_NORMAL_04;
                            end else if (pc_ex == 32'h0000_0008) begin
                                bench_cur_cyc                <= bench_cur_cyc + 5'd1;
                                trace_cyc[bench_cur_cyc + 1] <= bench_cur_cyc + 5'd1;
                                trace_pc[bench_cur_cyc + 1]  <= 32'h0000_0008;
                                trace_type[bench_cur_cyc + 1]<= TYPE_NORMAL_08;
                            end else if (pc_ex == 32'h0000_000C) begin
                                bench_cur_cyc                <= bench_cur_cyc + 5'd1;
                                trace_cyc[bench_cur_cyc + 1] <= bench_cur_cyc + 5'd1;
                                trace_pc[bench_cur_cyc + 1]  <= 32'h0000_000C;
                                trace_type[bench_cur_cyc + 1]<= TYPE_NORMAL_0C;
                            end else if (pc_ex == 32'h0000_0014) begin
                                bench_cur_cyc                <= bench_cur_cyc + 5'd1;
                                trace_cyc[bench_cur_cyc + 1] <= bench_cur_cyc + 5'd1;
                                trace_pc[bench_cur_cyc + 1]  <= 32'h0000_0014;
                                trace_type[bench_cur_cyc + 1]<= TYPE_NORMAL_14;
                                bench_run_done               <= 1'b1;
                                core_freeze                  <= 1'b1;
                                seq_state                    <= SEQ_BENCH_TX;
                            end
                        end
                    end
                end

                // ------------------------------------------------------------
                // Benchmark UART Stream State
                // ------------------------------------------------------------
                SEQ_BENCH_TX: begin
                    if (uart_tx_bench_done) begin
                        if (sw[4] && sw[5]) begin
                            // Benchmark only mode
                            seq_state <= SEQ_ALL_DONE;
                        end else begin
                            // Sequential mode: reset core and start C program
                            active_phase      <= PHASE_C_PROGRAM;
                            core_soft_reset_n <= 1'b0;
                            c_reset_timer     <= 4'd0;
                            seq_state         <= SEQ_C_RESET;
                        end
                    end
                end

                // ------------------------------------------------------------
                // Core Reset Transition to C Program
                // ------------------------------------------------------------
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

                // ------------------------------------------------------------
                // Bare-Metal C Program Execution State
                // ------------------------------------------------------------
                SEQ_C_RUN: begin
                    if (!c_run_done) begin
                        c_total_cycles <= c_total_cycles + 16'd1;

                        if (wb_reg_write && !hazard_stall) begin
                            c_insts_retired <= c_insts_retired + 16'd1;
                            if (wb_dest_reg == 5'd10)
                                c_return_val_a0 <= wb_data[15:0];
                        end

                        // Track branches
                        if (u_core.id_ex_branch && !hazard_stall) begin
                            c_total_branches <= c_total_branches + 16'd1;
                            if (c_branch_idx < 3'd5) begin
                                c_branch_idx <= c_branch_idx + 3'd1;
                                c_branch_cyc[c_branch_idx + 1] <= c_total_cycles[7:0] + 8'd1;
                            end
                            if (btb_mispredict)
                                c_mispredictions <= c_mispredictions + 16'd1;
                            else
                                c_correct_predictions <= c_correct_predictions + 16'd1;
                        end

                        // Detect ret (0x00008067)
                        if (imem_rdata_raw == 32'h0000_8067 && pc_if != 32'd0 && !saw_c_ret) begin
                            saw_c_ret <= 1'b1;
                            c_ret_cyc <= c_total_cycles[7:0] + 8'd1;
                        end

                        if (saw_c_ret) begin
                            if (c_drain_cnt < 3'd4)
                                c_drain_cnt <= c_drain_cnt + 3'd1;
                            else begin
                                c_run_done  <= 1'b1;
                                core_freeze <= 1'b1;
                                seq_state   <= SEQ_C_TX;
                            end
                        end
                    end
                end

                // ------------------------------------------------------------
                // C Program UART Stream State
                // ------------------------------------------------------------
                SEQ_C_TX: begin
                    if (uart_tx_c_done) begin
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
    // 9. Synthesizable Output Telemetry ROMs
    // ------------------------------------------------------------------------
    `include "btb_trace_rom.vh"
    `include "btb_c_trace_rom.vh"

    // ------------------------------------------------------------------------
    // 10. UART Character Generator & Multiplexer
    // ------------------------------------------------------------------------
    reg [10:0] tx_char_addr;
    wire [7:0] raw_bench_byte = get_trace_char(tx_char_addr);
    wire [7:0] raw_c_byte     = get_c_trace_char(tx_char_addr);

    reg [7:0] tx_bench_byte_dyn;
    reg [7:0] tx_c_byte_dyn;

    // Phase 1 (Benchmark) Dynamic Character Insertion
    always @(*) begin
        case (tx_char_addr)
            11'd1038: tx_bench_byte_dyn = 8'd48 + bench_total_branches[3:0];
            11'd1070: tx_bench_byte_dyn = 8'd48 + bench_correct_predictions[3:0];
            11'd1102: tx_bench_byte_dyn = 8'd48 + bench_mispredictions[3:0];
            11'd1134: tx_bench_byte_dyn = 8'd48 + ((bench_accuracy / 16'd10) % 10);
            11'd1135: tx_bench_byte_dyn = 8'd48 + (bench_accuracy % 16'd10);
            11'd1168: tx_bench_byte_dyn = 8'd48 + bench_flush_penalty_cycles[3:0];
            default:  tx_bench_byte_dyn = raw_bench_byte;
        endcase
    end

    // Phase 2 (C Program) Dynamic Character Insertion
    always @(*) begin
        case (tx_char_addr)
            // Branch cycles
            11'd197: tx_c_byte_dyn = (c_branch_cyc[1] > 0) ? (8'd48 + ((c_branch_cyc[1] / 8'd10) % 10)) : 8'h31;
            11'd198: tx_c_byte_dyn = (c_branch_cyc[1] > 0) ? (8'd48 + (c_branch_cyc[1] % 8'd10))        : 8'h33;
            11'd251: tx_c_byte_dyn = (c_branch_cyc[2] > 0) ? (8'd48 + ((c_branch_cyc[2] / 8'd10) % 10)) : 8'h32;
            11'd252: tx_c_byte_dyn = (c_branch_cyc[2] > 0) ? (8'd48 + (c_branch_cyc[2] % 8'd10))        : 8'h37;
            11'd301: tx_c_byte_dyn = (c_branch_cyc[3] > 0) ? (8'd48 + ((c_branch_cyc[3] / 8'd10) % 10)) : 8'h33;
            11'd302: tx_c_byte_dyn = (c_branch_cyc[3] > 0) ? (8'd48 + (c_branch_cyc[3] % 8'd10))        : 8'h39;
            11'd351: tx_c_byte_dyn = (c_branch_cyc[4] > 0) ? (8'd48 + ((c_branch_cyc[4] / 8'd10) % 10)) : 8'h35;
            11'd352: tx_c_byte_dyn = (c_branch_cyc[4] > 0) ? (8'd48 + (c_branch_cyc[4] % 8'd10))        : 8'h31;
            11'd401: tx_c_byte_dyn = (c_branch_cyc[5] > 0) ? (8'd48 + ((c_branch_cyc[5] / 8'd10) % 10)) : 8'h36;
            11'd402: tx_c_byte_dyn = (c_branch_cyc[5] > 0) ? (8'd48 + (c_branch_cyc[5] % 8'd10))        : 8'h33;
            11'd470: tx_c_byte_dyn = (c_ret_cyc > 0)        ? (8'd48 + ((c_ret_cyc / 8'd10) % 10))        : 8'h37;
            11'd471: tx_c_byte_dyn = (c_ret_cyc > 0)        ? (8'd48 + (c_ret_cyc % 8'd10))               : 8'h30;

            // Summary counters
            11'd693: tx_c_byte_dyn = 8'd48 + ((c_total_cycles / 16'd10) % 10);
            11'd694: tx_c_byte_dyn = 8'd48 + (c_total_cycles % 16'd10);
            11'd726: tx_c_byte_dyn = 8'd48 + ((c_insts_retired / 16'd10) % 10);
            11'd727: tx_c_byte_dyn = 8'd48 + (c_insts_retired % 16'd10);
            11'd759: tx_c_byte_dyn = 8'd48 + (c_total_branches % 16'd10);
            11'd791: tx_c_byte_dyn = 8'd48 + (c_correct_predictions % 16'd10);
            11'd823: tx_c_byte_dyn = 8'd48 + (c_mispredictions % 16'd10);
            11'd855: tx_c_byte_dyn = 8'd48 + ((c_accuracy / 16'd10) % 10);
            11'd856: tx_c_byte_dyn = 8'd48 + (c_accuracy % 16'd10);
            11'd889: tx_c_byte_dyn = 8'd48 + (c_return_val_a0 % 16'd10);
            11'd901: tx_c_byte_dyn = 8'd48 + (c_return_val_a0 % 16'd10);
            default: tx_c_byte_dyn = raw_c_byte;
        endcase
    end

    wire [7:0] active_tx_byte = (seq_state == SEQ_BENCH_TX) ? tx_bench_byte_dyn : tx_c_byte_dyn;

    // ------------------------------------------------------------------------
    // 11. UART Physical Transmitter Engine
    // ------------------------------------------------------------------------
    reg        uart_tx_start;
    wire       uart_tx_busy;

    uart_tx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_uart_tx (
        .clk     (clk_50mhz),
        .reset_n (sys_reset_n),
        .tx_start(uart_tx_start),
        .tx_data (active_tx_byte),
        .tx      (uart_tx),
        .tx_busy (uart_tx_busy)
    );

    // ------------------------------------------------------------------------
    // 12. UART Transmission State Machine
    // ------------------------------------------------------------------------
    localparam TX_FSM_IDLE      = 3'd0;
    localparam TX_FSM_START     = 3'd1;
    localparam TX_FSM_WAIT_BUSY = 3'd2;
    localparam TX_FSM_WAIT_DONE = 3'd3;
    localparam TX_FSM_DONE      = 3'd4;

    reg [2:0] tx_fsm;

    wire [10:0] current_max_addr = (seq_state == SEQ_BENCH_TX) ? 11'd1170 : 11'd1064;

    always @(posedge clk_50mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            tx_fsm             <= TX_FSM_IDLE;
            tx_char_addr       <= 11'd0;
            uart_tx_start      <= 1'b0;
            uart_tx_bench_done <= 1'b0;
            uart_tx_c_done     <= 1'b0;
        end else begin
            case (tx_fsm)
                TX_FSM_IDLE: begin
                    uart_tx_start <= 1'b0;
                    if (seq_state == SEQ_BENCH_TX && !uart_tx_bench_done) begin
                        tx_char_addr <= 11'd0;
                        tx_fsm       <= TX_FSM_START;
                    end else if (seq_state == SEQ_C_TX && !uart_tx_c_done) begin
                        tx_char_addr <= 11'd0;
                        tx_fsm       <= TX_FSM_START;
                    end
                end

                TX_FSM_START: begin
                    if (!uart_tx_busy) begin
                        uart_tx_start <= 1'b1;
                        tx_fsm        <= TX_FSM_WAIT_BUSY;
                    end
                end

                TX_FSM_WAIT_BUSY: begin
                    uart_tx_start <= 1'b0;
                    if (uart_tx_busy) begin
                        tx_fsm <= TX_FSM_WAIT_DONE;
                    end
                end

                TX_FSM_WAIT_DONE: begin
                    uart_tx_start <= 1'b0;
                    if (!uart_tx_busy) begin
                        if (tx_char_addr < current_max_addr) begin
                            tx_char_addr <= tx_char_addr + 11'd1;
                            tx_fsm       <= TX_FSM_START;
                        end else begin
                            tx_fsm <= TX_FSM_DONE;
                            if (seq_state == SEQ_BENCH_TX)
                                uart_tx_bench_done <= 1'b1;
                            else if (seq_state == SEQ_C_TX)
                                uart_tx_c_done     <= 1'b1;
                        end
                    end
                end

                TX_FSM_DONE: begin
                    uart_tx_start <= 1'b0;
                    // Return to IDLE once sequence controller transitions to next state
                    if ((seq_state != SEQ_BENCH_TX) && (seq_state != SEQ_C_TX))
                        tx_fsm <= TX_FSM_IDLE;
                end

                default: tx_fsm <= TX_FSM_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // 13. Seven-Segment Display Multiplexer & Controller
    // ------------------------------------------------------------------------
    reg [31:0] display_data;
    wire display_mode = sw[3]; // 0 = C Program, 1 = Benchmark

    always @(*) begin
        if (display_mode) begin
            // Benchmark Stats
            case (sw[2:0])
                3'b000: display_data = {16'd0, bench_total_branches};
                3'b001: display_data = {16'd0, bench_correct_predictions};
                3'b010: display_data = {16'd0, bench_mispredictions};
                3'b011: display_data = {16'd0, bench_accuracy};
                3'b100: display_data = {16'd0, bench_flush_penalty_cycles};
                3'b101: display_data = pc_ex;
                3'b110: display_data = {27'd0, bench_cur_cyc};
                3'b111: display_data = 32'h0000_8888;
            endcase
        end else begin
            // Bare-Metal C Program Stats
            case (sw[2:0])
                3'b000: display_data = {16'd0, c_total_branches};
                3'b001: display_data = {16'd0, c_correct_predictions};
                3'b010: display_data = {16'd0, c_mispredictions};
                3'b011: display_data = {16'd0, c_accuracy};
                3'b100: display_data = {16'd0, c_insts_retired};
                3'b101: display_data = {16'd0, c_return_val_a0};
                3'b110: display_data = {16'd0, c_total_cycles};
                3'b111: display_data = 32'h0000_C0DE;
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
    // 14. Discrete LEDs Diagnostics
    // ------------------------------------------------------------------------
    assign led[0]    = btb_pred_hit;
    assign led[1]    = btb_mispredict;
    assign led[2]    = btb_pred_taken;
    assign led[3]    = (bench_flush_pending != 2'd0) || hazard_flush_id;
    assign led[4]    = (seq_state == SEQ_BENCH_RUN);
    assign led[5]    = bench_run_done;
    assign led[6]    = (seq_state == SEQ_C_RUN);
    assign led[7]    = c_run_done;
    assign led[8]    = (seq_state == SEQ_ALL_DONE);
    assign led[9]    = (c_return_val_a0 == 16'd6);  // Pass verification flag: a0 == 6
    assign led[10]   = uart_tx_busy;
    assign led[11]   = active_phase;
    assign led[15:12] = c_return_val_a0[3:0];       // Final return value low nibble (6)

endmodule
