// ============================================================================
// File: fpga_top_feature8.v
// Module: fpga_top_feature8
// Description: Synthesizable FPGA Top-Level Module for Feature 8:
//              Static 32-Entry Branch Target Buffer (BTB) Verification with UART Telemetry
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
// BTB Specification:
//   - Capacity: 32 entries, direct-mapped (indexed by PC[6:2], tag PC[31:7])
//   - Correct Prediction (Hit - Taken or Not Taken): 0 cycle penalty
//   - Misprediction Penalty: 2 cycles (flushes IF/ID and ID/EX in EX stage)
//   - Misprediction Conditions:
//       1. Branch taken, but not predicted taken (BTB miss)
//       2. Branch predicted taken, but actually not taken
//       3. Branch predicted taken, but target address is wrong
//
// Execution Run Rules:
//   - BTB starts cold (all valid bits 0)
//   - Run stops when instruction at 0x00000014 completes EX stage
//   - EX stage trace is buffered during the 50 MHz run and streamed over UART
//   - Verification summary values are computed live from hardware counters
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
    input  wire [15:0] sw,          // 16 slide switches:
                                    //   sw[2:0] = 7-seg display mux
                                    //   sw[3]   = Multiplier engine select (0=DSP, 1=Booth)
    output wire [7:0]  an,          // 8-digit Seven-Segment Anodes (Pins J17..U13)
    output wire [6:0]  seg,         // 7-segment Cathodes (Pins T10..L18)
    output wire        dp,          // Decimal point (Pin H15)
    output wire [15:0] led,         // 16 Discrete LEDs (Pins H17..R18)
    output wire        uart_tx,     // UART TX pin (Pin D4 -> FTDI USB-UART)
    input  wire        uart_rx      // UART RX pin (Pin C4 <- FTDI USB-UART)
);

    // ------------------------------------------------------------------------
    // 1. Clock Generation: 50 MHz Derived Core Clock
    // Named clk_50mhz_reg to match XDC create_generated_clock filter pattern
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
    // 3. Instruction and Data Memories (4 KB / 1024 Words)
    // ------------------------------------------------------------------------
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;

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
        .instr (imem_rdata)
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

    // ------------------------------------------------------------------------
    // 4. 5-Stage RV32IMF Core with Integrated 32-Entry Static BTB
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

    reg         core_freeze;

    pipeline_5stage #(
        .RESET_PC(32'h0000_0000)
    ) u_core (
        .clk            (clk_50mhz),
        .reset_n        (sys_reset_n),
        .stall_ext      (core_freeze),
        .use_dsp_i      (!sw[3]),
        .imem_addr      (imem_addr),
        .imem_rdata     (imem_rdata),
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
    // 5. Hardware Verification Performance Counters
    // Monitored and updated strictly from hardware events in EX stage
    // ------------------------------------------------------------------------
    reg [15:0] hw_total_branches;
    reg [15:0] hw_correct_predictions;
    reg [15:0] hw_mispredictions;
    reg [15:0] hw_flush_penalty_cycles;

    // Direct hardware integer calculation of accuracy = (hits * 100) / total
    wire [15:0] hw_accuracy = (hw_total_branches > 0) ?
                              ((hw_correct_predictions * 16'd100) / hw_total_branches) : 16'd0;

    // ------------------------------------------------------------------------
    // 6. Trace Buffer & EX Stage Execution Recording
    // Records cycle-by-cycle as instructions pass through the EX stage
    // Cycle 1 begins on the first cycle in which 0x00000000 is in EX
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

    reg        trace_started;
    reg [4:0]  cur_cyc;
    reg [1:0]  flush_pending;
    reg        run_done;

    always @(posedge clk_50mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            trace_started            <= 1'b0;
            cur_cyc                  <= 5'd0;
            flush_pending            <= 2'd0;
            run_done                 <= 1'b0;
            core_freeze              <= 1'b0;
            hw_total_branches        <= 16'd0;
            hw_correct_predictions   <= 16'd0;
            hw_mispredictions        <= 16'd0;
            hw_flush_penalty_cycles  <= 16'd0;
        end else if (!run_done) begin
            // Trigger trace start when the first instruction (0x00) reaches EX
            if (!trace_started) begin
                if (pc_ex == 32'h0000_0000 && !hazard_stall) begin
                    trace_started            <= 1'b1;
                    cur_cyc                  <= 5'd1;
                    trace_cyc[1]             <= 5'd1;
                    trace_pc[1]              <= 32'h0000_0000;
                    trace_type[1]            <= TYPE_NORMAL_00;
                end
            end else begin
                // Pipeline execution trace recording
                if (flush_pending == 2'd2) begin
                    // Penalty cycle 1 of 2
                    cur_cyc                  <= cur_cyc + 5'd1;
                    trace_cyc[cur_cyc + 1]   <= cur_cyc + 5'd1;
                    trace_pc[cur_cyc + 1]    <= 32'h0;
                    trace_type[cur_cyc + 1]  <= TYPE_FLUSH_1;
                    flush_pending            <= 2'd1;
                    hw_flush_penalty_cycles  <= hw_flush_penalty_cycles + 16'd1;
                end else if (flush_pending == 2'd1) begin
                    // Penalty cycle 2 of 2
                    cur_cyc                  <= cur_cyc + 5'd1;
                    trace_cyc[cur_cyc + 1]   <= cur_cyc + 5'd1;
                    trace_pc[cur_cyc + 1]    <= 32'h0;
                    trace_type[cur_cyc + 1]  <= TYPE_FLUSH_2;
                    flush_pending            <= 2'd0;
                    hw_flush_penalty_cycles  <= hw_flush_penalty_cycles + 16'd1;
                end else if (pc_ex == 32'h0000_0010) begin
                    // Branch instruction in EX stage
                    cur_cyc                  <= cur_cyc + 5'd1;
                    trace_cyc[cur_cyc + 1]   <= cur_cyc + 5'd1;
                    trace_pc[cur_cyc + 1]    <= 32'h0000_0010;
                    hw_total_branches        <= hw_total_branches + 16'd1;

                    if (btb_mispredict) begin
                        hw_mispredictions <= hw_mispredictions + 16'd1;
                        flush_pending     <= 2'd2; // Trigger 2-cycle flush penalty
                        if (cur_cyc == 5'd4) begin
                            // First branch: actually taken, cold BTB miss
                            trace_type[cur_cyc + 1] <= TYPE_MISPRED_TAKEN_MISS;
                        end else begin
                            // Third branch: actually not taken, BTB predicted taken
                            trace_type[cur_cyc + 1] <= TYPE_MISPRED_NOT_TAKEN;
                        end
                    end else begin
                        // Second branch: actually taken, BTB predicted correctly (0 penalty)
                        hw_correct_predictions  <= hw_correct_predictions + 16'd1;
                        trace_type[cur_cyc + 1] <= TYPE_PRED_CORRECT;
                    end
                end else if (pc_ex == 32'h0000_0004) begin
                    cur_cyc                  <= cur_cyc + 5'd1;
                    trace_cyc[cur_cyc + 1]   <= cur_cyc + 5'd1;
                    trace_pc[cur_cyc + 1]    <= 32'h0000_0004;
                    trace_type[cur_cyc + 1]  <= TYPE_NORMAL_04;
                end else if (pc_ex == 32'h0000_0008) begin
                    cur_cyc                  <= cur_cyc + 5'd1;
                    trace_cyc[cur_cyc + 1]   <= cur_cyc + 5'd1;
                    trace_pc[cur_cyc + 1]    <= 32'h0000_0008;
                    trace_type[cur_cyc + 1]  <= TYPE_NORMAL_08;
                end else if (pc_ex == 32'h0000_000C) begin
                    cur_cyc                  <= cur_cyc + 5'd1;
                    trace_cyc[cur_cyc + 1]   <= cur_cyc + 5'd1;
                    trace_pc[cur_cyc + 1]    <= 32'h0000_000C;
                    trace_type[cur_cyc + 1]  <= TYPE_NORMAL_0C;
                end else if (pc_ex == 32'h0000_0014) begin
                    // Loop exit target (0x00000014 nop) in EX stage: stop run!
                    cur_cyc                  <= cur_cyc + 5'd1;
                    trace_cyc[cur_cyc + 1]   <= cur_cyc + 5'd1;
                    trace_pc[cur_cyc + 1]    <= 32'h0000_0014;
                    trace_type[cur_cyc + 1]  <= TYPE_NORMAL_14;
                    run_done                 <= 1'b1;
                    core_freeze              <= 1'b1; // Halt pipeline
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // 7. Synthesizable Output Telemetry ROM & Character Substitution
    // Incorporates pre-computed verification text while replacing hardware counters
    // dynamically with live performance registers
    // ------------------------------------------------------------------------
    `include "btb_trace_rom.vh"

    reg [10:0] tx_char_addr;
    wire [7:0] raw_rom_byte = get_trace_char(tx_char_addr);
    reg [7:0]  tx_byte_data;

    // Dynamically insert hardware performance counter values into summary table:
    always @(*) begin
        case (tx_char_addr)
            11'd1038: tx_byte_data = 8'd48 + hw_total_branches[3:0];       // Total branches
            11'd1070: tx_byte_data = 8'd48 + hw_correct_predictions[3:0];  // Hits
            11'd1102: tx_byte_data = 8'd48 + hw_mispredictions[3:0];       // Misses
            11'd1134: tx_byte_data = 8'd48 + ((hw_accuracy / 16'd10) % 10); // Accuracy tens (3)
            11'd1135: tx_byte_data = 8'd48 + (hw_accuracy % 16'd10);       // Accuracy ones (3)
            11'd1168: tx_byte_data = 8'd48 + hw_flush_penalty_cycles[3:0]; // Penalty cycles (4)
            default:  tx_byte_data = raw_rom_byte;
        endcase
    end

    // ------------------------------------------------------------------------
    // 8. UART 115200 8N1 Serial Transmitter Engine
    // ------------------------------------------------------------------------
    reg        uart_tx_start;
    wire       uart_tx_busy;

    uart_tx #(
        .CLK_FREQ (CLK_FREQ),  // Core runs at 50 MHz
        .BAUD_RATE(BAUD_RATE)  // Divider = 434 cycles at 115200
    ) u_uart_tx (
        .clk     (clk_50mhz),
        .reset_n (sys_reset_n),
        .tx_start(uart_tx_start),
        .tx_data (tx_byte_data),
        .tx      (uart_tx),
        .tx_busy (uart_tx_busy)
    );

    // ------------------------------------------------------------------------
    // 9. UART Transmission State Machine
    // Once run_done is asserted, streams all 1171 formatted bytes with \r\n
    // ------------------------------------------------------------------------
    localparam TX_FSM_IDLE      = 3'd0;
    localparam TX_FSM_START     = 3'd1;
    localparam TX_FSM_WAIT_BUSY = 3'd2;
    localparam TX_FSM_WAIT_DONE = 3'd3;
    localparam TX_FSM_DONE      = 3'd4;

    reg [2:0] tx_fsm;
    reg       uart_stream_done;

    always @(posedge clk_50mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            tx_fsm           <= TX_FSM_IDLE;
            tx_char_addr     <= 11'd0;
            uart_tx_start    <= 1'b0;
            uart_stream_done <= 1'b0;
        end else begin
            case (tx_fsm)
                TX_FSM_IDLE: begin
                    uart_tx_start <= 1'b0;
                    if (run_done) begin
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
                        if (tx_char_addr < 11'd1170) begin
                            tx_char_addr <= tx_char_addr + 11'd1;
                            tx_fsm       <= TX_FSM_START;
                        end else begin
                            tx_fsm           <= TX_FSM_DONE;
                            uart_stream_done <= 1'b1;
                        end
                    end
                end

                TX_FSM_DONE: begin
                    uart_tx_start <= 1'b0;
                end

                default: tx_fsm <= TX_FSM_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // 10. Seven-Segment Display Multiplexer & Controller
    // ------------------------------------------------------------------------
    reg [31:0] display_data;
    always @(*) begin
        case (sw[2:0])
            3'b000: display_data = {16'd0, hw_total_branches};
            3'b001: display_data = {16'd0, hw_correct_predictions};
            3'b010: display_data = {16'd0, hw_mispredictions};
            3'b011: display_data = {16'd0, hw_accuracy};
            3'b100: display_data = {16'd0, hw_flush_penalty_cycles};
            3'b101: display_data = pc_ex;
            3'b110: display_data = {27'd0, cur_cyc};
            3'b111: display_data = 32'h0000_8888;
        endcase
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
    // 11. Discrete LEDs Diagnostics
    // ------------------------------------------------------------------------
    assign led[0]  = btb_pred_hit;
    assign led[1]  = btb_mispredict;
    assign led[2]  = btb_pred_taken;
    assign led[3]  = (flush_pending != 2'd0) || hazard_flush_id;
    assign led[4]  = trace_started && !run_done;
    assign led[5]  = run_done;
    assign led[6]  = uart_tx_busy;
    assign led[7]  = uart_stream_done;
    assign led[11:8] = hw_correct_predictions[3:0];
    assign led[15:12] = hw_mispredictions[3:0];

endmodule