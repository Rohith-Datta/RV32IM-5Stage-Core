// ============================================================================
// File: fpga_top_feature6.v
// Module: fpga_top_feature6
// Description: Synthesizable FPGA Top-Level Module for Feature 6 (L1 I-Cache Core)
//              Target Board: Digilent Nexys A7-100T (Xilinx Artix-7 XC7A100T-1CSG324C)
//              Features:
//              - 50 MHz Core Clock Derived from 100 MHz Oscillator
//              - RV32IMF Core with Parameterized 2 KB L1 I-Cache & Direct DMEM Access
//              - SW[0] Mode Selector: SW0=0 -> I-Cache Enabled, SW0=1 -> I-Cache Bypassed
//              - Switch Latching at Run Start (flipping switch during run has no effect)
//              - Cold Cache Initialization on Each Run
//              - 3-Iteration JAL Loop Hardware Halt at PC 0x00000010
//              - Post-Run Formatted UART Output (115200 8N1):
//                  1. Cycle-by-cycle trace table (HIT, MISS, STALL, FETCHED, FLUSH)
//                  2. Mode Summary (Instructions, Cycles, Hits, Misses, Hit Rate %, CPI)
//                  3. Side-by-Side Comparison Summary when both modes have completed
// ============================================================================

`timescale 1ns/1ps

module fpga_top_feature6 #(
    parameter CLK_FREQ       = 50_000_000,
    parameter BAUD_RATE      = 115_200,
    parameter DEBOUNCE_LIMIT = 20'd1_000_000
)(
    input  wire        CLK100MHZ,      // 100 MHz onboard oscillator
    input  wire        CPU_RESETN,     // Active-low CPU reset push button
    input  wire        BTNC,           // Center push button: reset comparison history
    input  wire [15:0] SW,             // Slide switches (SW[0] selects mode)
    output wire [15:0] LED,            // Status and diagnostic LEDs
    output wire [7:0]  AN,             // 7-segment digit anodes (active low)
    output wire [6:0]  SEG,            // 7-segment cathode segments (active low)
    output wire        DP,             // 7-segment decimal point
    output wire        UART_TXD_IN     // Serial TX to FTDI USB-UART bridge (Pin D4)
);

    // ========================================================================
    // 1. Clock Generation: 50 MHz Core Clock
    // ========================================================================
    reg clk_50mhz = 1'b0;
    always @(posedge CLK100MHZ) begin
        clk_50mhz <= ~clk_50mhz;
    end

    // Synchronize active-low reset to 50 MHz clock domain
    reg [2:0] reset_sync = 3'b000;
    always @(posedge clk_50mhz) begin
        reset_sync <= {reset_sync[1:0], CPU_RESETN};
    end
    wire reset_n = reset_sync[2];

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
                if (btnc_timer == DEBOUNCE_LIMIT) begin // Debounce window (20ms on hardware)
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

    wire btnc_step_pulse = btnc_debounced && !btnc_debounced_d; // Clean 1-cycle edge pulse
    wire btnc_pressed    = btnc_step_pulse;

    // ========================================================================
    // 2. Program Instruction Helper Function
    // ========================================================================
    function [31:0] get_inst_for_pc(input [31:0] a);
        case (a[11:2])
            10'd0:   get_inst_for_pc = 32'h0000_0093; // addi x1, x0, 0
            10'd1:   get_inst_for_pc = 32'h0000_0113; // addi x2, x0, 0
            10'd2:   get_inst_for_pc = 32'h0010_8093; // addi x1, x1, 1
            10'd3:   get_inst_for_pc = 32'h0011_0133; // add  x2, x2, x1
            10'd4:   get_inst_for_pc = 32'hFF9F_F06F; // jal  x0, -8
            default: get_inst_for_pc = 32'h0000_0013; // nop
        endcase
    endfunction

    // ========================================================================
    // 3. Memory Bus Interconnects
    // ========================================================================
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;
    wire        imem_req;

    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we;
    wire        dmem_re;
    wire [31:0] dmem_rdata;

    // Pipeline telemetry signals
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
    // 4. Backing Instruction & Data Memories
    // ========================================================================
    instr_mem #(
        .HEX_FILE ("C:/CS2202L/RISCV/feature_6/mem/imem.hex"),
        .WORDS    (1024)
    ) u_backing_imem (
        .clk   (clk_50mhz),
        .pc    (imem_addr),
        .instr (imem_rdata)
    );

    data_mem #(
        .HEX_FILE ("C:/CS2202L/RISCV/feature_6/mem/dmem.hex"),
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

    // ========================================================================
    // 5. Run Controller, Stepping Logic & Trace Buffer
    // ========================================================================
    reg        latched_mode = 1'b0;   // Latched SW[0] at start of run
    reg        run_active   = 1'b0;   // 1 while benchmark is executing
    reg        run_done     = 1'b0;   // 1 when 3rd JAL completes
    reg [1:0]  jal_loop_cnt = 2'd0;   // Counts JAL loop completions (0, 1, 2 -> done)
    reg [31:0] final_halt_pc = 32'h0000_0010;

    reg [15:0] global_cyc    = 16'd1; // UNIFIED GLOBAL CYCLE COUNTER (starts at 1!)
    reg [15:0] halted_cycles = 16'd0;
    reg [15:0] active_insts  = 16'd0;
    reg [15:0] active_hits   = 16'd0;
    reg [15:0] active_misses = 16'd0;

    // 256-entry Trace Buffer: {status_code[3:0], cyc[15:0], pc[31:0], inst[31:0]}
    // status_code:
    //   4'd0: HIT
    //   4'd1: MISS (stall 1/9)
    //   4'd2..9: STALL (stall 2/9 .. 9/9)
    //   4'd10: FETCHED (instruction delivered)
    //   4'd11: FLUSH  PC=0x00000014   (jal PC + 4)
    (* ram_style = "block" *) reg [83:0] trace_mem [0:255];
    reg [7:0]  trace_len = 8'd0;
    wire [7:0] trace_rd_addr;
    reg [83:0] trace_rd_data;

    // Synchronous BRAM read/write
    reg        trace_wr_en = 1'b0;
    reg [83:0] trace_wr_data = 84'd0;
    reg [7:0]  trace_wr_addr = 8'd0;

    always @(posedge clk_50mhz) begin
        if (trace_wr_en) begin
            trace_mem[trace_wr_addr] <= trace_wr_data;
        end
        trace_rd_data <= trace_mem[trace_rd_addr];
    end

    // Persistent Historical Stats for Comparison (preserved across CPU_RESETN)
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

    // Trigger pulses for UART print engine
    reg start_print        = 1'b0;
    reg step_print_banner  = 1'b0;
    reg step_print_row     = 1'b0;
    reg [7:0] step_row_addr = 8'd0;
    reg step_print_summary = 1'b0;
    reg banner_printed_for_step = 1'b0;

    wire printer_busy;
    wire printer_done;

    // Hardware Debug Stepping Mode:
    // SW[15] = 1: Manual Step Mode (advances 1 clock cycle per BTNC clean press)
    // SW[15] = 0: Continuous Run Mode (runs at 50 MHz standard clock)
    wire step_mode_active = SW[15];
    wire can_step         = step_mode_active ? (btnc_step_pulse && !printer_busy) : 1'b1;
    wire core_clk_en      = run_active && can_step;
    wire stall_core       = !core_clk_en;

    // In Continuous Mode, BTNC can be pressed to reset comparison history
    always @(posedge clk_50mhz) begin
        if (!step_mode_active && btnc_pressed) begin
            mode0_valid <= 1'b0;
            mode1_valid <= 1'b0;
        end
    end

    // Detect JAL executed in ID stage: IF is presenting pc_if == 0x00000014, which is FLUSHED!
    wire jal_taken_id;

    always @(posedge clk_50mhz or negedge reset_n) begin
        if (!reset_n) begin
            latched_mode             <= SW[0];
            run_active               <= 1'b1;  // Ready to run on first cycle exiting reset!
            run_done                 <= 1'b0;
            start_print              <= 1'b0;
            step_print_banner        <= 1'b0;
            step_print_row           <= 1'b0;
            step_row_addr            <= 8'd0;
            step_print_summary       <= 1'b0;
            banner_printed_for_step  <= 1'b0;
            jal_loop_cnt             <= 2'd0;
            global_cyc               <= 16'd1; // First clock cycle is CYC = 1!
            halted_cycles            <= 16'd0;
            active_insts             <= 16'd0;
            active_hits              <= 16'd0;
            active_misses            <= 16'd0;
            trace_len                <= 8'd0;
            final_halt_pc            <= 32'h0000_0010;
            trace_wr_en              <= 1'b0;
        end else begin
            start_print        <= 1'b0;
            step_print_banner  <= 1'b0;
            step_print_row     <= 1'b0;
            step_print_summary <= 1'b0;
            trace_wr_en        <= 1'b0;

            // In Step Mode, print banner header as soon as reset is released
            if (step_mode_active && !banner_printed_for_step && !printer_busy) begin
                step_print_banner       <= 1'b1;
                banner_printed_for_step <= 1'b1;
            end

            if (run_active && can_step) begin
                global_cyc <= global_cyc + 16'd1;

                if (jal_taken_id) begin
                    // JAL in ID: the instruction currently being fetched at 0x00000014 is FLUSHED!
                    trace_wr_en   <= 1'b1;
                    trace_wr_addr <= trace_len;
                    trace_wr_data <= {4'd11, global_cyc, 32'h0000_0014, 32'h0000_0013};

                    if (step_mode_active) begin
                        step_print_row <= 1'b1;
                        step_row_addr  <= trace_len;
                    end
                    trace_len    <= trace_len + 8'd1;
                    jal_loop_cnt <= jal_loop_cnt + 2'd1;

                    if (jal_loop_cnt == 2'd2) begin
                        // 3rd JAL completion reached! Stop core and trigger summary print
                        run_active    <= 1'b0;
                        run_done      <= 1'b1;
                        final_halt_pc <= 32'h0000_0010;
                        halted_cycles <= global_cyc;

                        if (!step_mode_active) begin
                            start_print <= 1'b1;
                        end else begin
                            step_print_summary <= 1'b1;
                        end

                        if (!latched_mode) begin
                            mode0_valid        <= 1'b1;
                            mode0_instructions <= active_insts;
                            mode0_cycles       <= global_cyc;
                            mode0_hits         <= active_hits;
                            mode0_misses       <= active_misses;
                        end else begin
                            mode1_valid        <= 1'b1;
                            mode1_instructions <= active_insts;
                            mode1_cycles       <= global_cyc;
                            mode1_hits         <= active_hits;
                            mode1_misses       <= active_misses;
                        end
                    end
                end else begin
                    // Normal cycle logging:
                    case (icache_state)
                        2'b00: begin // STATE_IDLE
                            if (icache_just_refilled) begin
                                // Instruction delivered on cycle 10 of miss (enabled mode)
                                trace_wr_en   <= 1'b1;
                                trace_wr_addr <= trace_len;
                                trace_wr_data <= {4'd10, global_cyc, pc_if, get_inst_for_pc(pc_if)};

                                if (step_mode_active) begin
                                    step_print_row <= 1'b1;
                                    step_row_addr  <= trace_len;
                                end
                                trace_len    <= trace_len + 8'd1;
                                active_insts <= active_insts + 16'd1;
                            end else if (icache_hit) begin
                                // 1-cycle HIT
                                trace_wr_en   <= 1'b1;
                                trace_wr_addr <= trace_len;
                                trace_wr_data <= {4'd0, global_cyc, pc_if, get_inst_for_pc(pc_if)};

                                if (step_mode_active) begin
                                    step_print_row <= 1'b1;
                                    step_row_addr  <= trace_len;
                                end
                                trace_len    <= trace_len + 8'd1;
                                active_hits  <= active_hits + 16'd1;
                                active_insts <= active_insts + 16'd1;
                            end else if (icache_miss) begin
                                // Cycle 1 of MISS (stall 1/9)
                                trace_wr_en   <= 1'b1;
                                trace_wr_addr <= trace_len;
                                trace_wr_data <= {4'd1, global_cyc, pc_if, get_inst_for_pc(pc_if)};

                                if (step_mode_active) begin
                                    step_print_row <= 1'b1;
                                    step_row_addr  <= trace_len;
                                end
                                trace_len     <= trace_len + 8'd1;
                                active_misses <= active_misses + 16'd1;
                            end
                        end

                        2'b01: begin // STATE_REFILL
                            // Cycles 2..9 of miss / refill
                            trace_wr_en   <= 1'b1;
                            trace_wr_addr <= trace_len;
                            trace_wr_data <= {4'd2 + icache_refill_cnt, global_cyc, icache_latched_pc, get_inst_for_pc(icache_latched_pc)};

                            if (step_mode_active) begin
                                step_print_row <= 1'b1;
                                step_row_addr  <= trace_len;
                            end
                            trace_len <= trace_len + 8'd1;
                        end

                        2'b10: begin // STATE_BYPASS
                            // Cycle 10 of bypassed fetch (instruction delivered)
                            trace_wr_en   <= 1'b1;
                            trace_wr_addr <= trace_len;
                            trace_wr_data <= {4'd10, global_cyc, icache_latched_pc, get_inst_for_pc(icache_latched_pc)};

                            if (step_mode_active) begin
                                step_print_row <= 1'b1;
                                step_row_addr  <= trace_len;
                            end
                            trace_len    <= trace_len + 8'd1;
                            active_insts <= active_insts + 16'd1;
                        end
                    endcase
                end
            end
        end
    end

    // ========================================================================
    // 6. Pipelined RV32IMF Core with L1 I-Cache
    // ========================================================================
    pipeline_5stage #(
        .RESET_PC     (32'h0000_0000),
        .HIT_TIME     (1),
        .MISS_PENALTY (9)
    ) u_core (
        .clk                    (clk_50mhz),
        .reset_n                (reset_n),
        .stall_ext              (stall_core),
        .use_dsp_i              (SW[2]),
        .icache_bypass_i        (latched_mode),
        .imem_addr              (imem_addr),
        .imem_rdata             (imem_rdata),
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
        .icache_just_refilled_o (icache_just_refilled)
    );

    // ========================================================================
    // 7. Formatted UART Output Engine
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
        .stat_instructions  (active_insts),
        .stat_cycles        (halted_cycles),
        .stat_hits          (active_hits),
        .stat_misses        (active_misses),
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
        .uart_tx            (uart_tx_line),
        .print_busy         (printer_busy),
        .print_done         (printer_done)
    );

    assign UART_TXD_IN = uart_tx_line;

    // ========================================================================
    // 8. Diagnostic LEDs
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

    assign LED[0]  = run_active;                               // Core currently executing benchmark
    assign LED[1]  = run_done;                                 // 3-iteration run completed
    assign LED[2]  = latched_mode;                             // Active mode (0: Enabled, 1: Bypassed)
    assign LED[3]  = printer_busy;                             // UART printer active
    assign LED[4]  = printer_done;                             // UART transmission completed
    assign LED[5]  = mode0_valid;                              // Mode 0 results stored
    assign LED[6]  = mode1_valid;                              // Mode 1 results stored
    assign LED[7]  = mode0_valid && mode1_valid;               // Both modes completed comparison ready!
    assign LED[8]  = (icache_hit_timer != 0);                  // I-Cache Hit pulse (Green)
    assign LED[9]  = (icache_miss_timer != 0);                 // I-Cache Miss pulse (Orange)
    assign LED[10] = step_mode_active;                         // Step Mode Active (SW[15]=1)
    assign LED[11] = btnc_debounced;                           // Clean BTNC state
    assign LED[12] = div_busy || fpu_busy;
    assign LED[13] = hazard_stall;
    assign LED[14] = 1'b0;
    assign LED[15] = heartbeat_cnt[24];                        // Alive blink

    // ========================================================================
    // 9. Seven-Segment Multiplexed Display Controller
    // ========================================================================
    reg [31:0] display_data;
    always @(*) begin
        case (SW[5:3])
            3'b000: display_data = run_done ? final_halt_pc : pc_wb;          // Mode 0: Consistently 0x00000010 on halt!
            3'b001: display_data = {16'h0, run_done ? halted_cycles : global_cyc}; // Mode 1: Unified Global Cycles
            3'b010: display_data = {16'h0, active_hits};                      // Mode 2: Active Hits
            3'b011: display_data = {16'h0, active_misses};                    // Mode 3: Active Misses
            3'b100: display_data = imem_rdata;                                // Mode 4: Fetched Instruction
            3'b101: display_data = {27'h0, wb_dest_reg};                      // Mode 5: Writeback Destination Reg
            3'b110: display_data = {14'h0, div_busy, fpu_busy, 16'h0};       // Mode 6: Math Busy Flags
            3'b111: display_data = 32'h0000_0006;                             // Mode 7: Feature 6 Tag
        endcase
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

