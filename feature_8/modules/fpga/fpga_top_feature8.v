// ============================================================================
// File: fpga_top_feature8.v
// Module: fpga_top_feature8
// Description: Synthesizable FPGA Top-Level Module for Feature 8
//              (RV32IMF Core with Passive CSRs & Hardware Performance Counters)
// Target Device: Xilinx Artix-7 XC7A100T-1CSG324C (Digilent Nexys A7-100T Board)
//
// Key Features Mapped to Board Peripherals:
// 1. 8-Digit Seven-Segment Display (Multiplexed via sw[2:0]):
//    - sw[2:0] = 3'b000: Shows 32-bit Program Counter Fetch Address (pc_if).
//    - sw[2:0] = 3'b001: Shows 32-bit Machine Instruction Code (imem_rdata).
//    - sw[2:0] = 3'b010: Lower 32 bits of CSR cycle counter (0xC00).
//    - sw[2:0] = 3'b011: Lower 32 bits of CSR instret counter (0xC02).
//    - sw[2:0] = 3'b100: Lower 32 bits of CSR hpmcounter3 stall counter (0xC03).
//    - sw[2:0] = 3'b101: Lower 32 bits of CSR hpmcounter4 branch counter (0xC04).
//    - sw[2:0] = 3'b110: Final Return Result a0 (x10).
// 2. Hardware Engine Selection (Switch sw[3]):
//    - sw[3] = 0: DSP48E1 Multiplier Mode
//    - sw[3] = 1: Radix-4 Booth Multiplier Mode
// 3. LED Hardware Diagnostics:
//    - LED[0]: Hazard Stall Active (Load-use, DIV, FPU stall)
//    - LED[1]: Data Forwarding Active (Operand bypass into ALU/MUL/DIV/FPU)
//    - LED[2]: Branch Pipeline Flush (hazard_flush_id)
//    - LED[3]: Instruction Writeback Commit (wb_reg_write)
//    - LED[4]: Multiplier Unit Active Indicator (mul_active in EX)
//    - LED[5]: Divider Unit Active Indicator (div_active in EX)
//    - LED[6]: FPU Unit Active Indicator (fpu_active in EX)
//    - LED[7]: Program Execution Completed (prog_done)
//    - LED[8]: CSR Instruction Access Indicator (Stretched)
//    - LED[15:9]: Low bits of committed register result or return value
// 4. Clocking & Execution Controls:
//    - sw[1] = 1 Hz Slow Clock mode for live visual observation
//    - sw[15] = Step mode (0 = Continuous UART-paced run, 1 = Manual Single-Step via btnc)
//    - cpu_resetn: Active-low synchronous reset button (Pin C12)
// 5. USB-UART Serial Telemetry (115,200 Baud on Pin D4):
//    - Real-time zero-lag stream of fetched instructions and CSR telemetry
// ============================================================================

`timescale 1ns/1ps

module fpga_top_feature8 #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  wire        clk_100mhz,  // 100 MHz onboard oscillator (Pin E3)
    input  wire        cpu_resetn,  // Active-low CPU reset push button (Pin C12)
    input  wire        btnc,        // Center push button: manual single step (Pin N17)
    input  wire [15:0] sw,          // 16 slide switches:
                                    //   sw[2:0] = 7-seg display mux
                                    //   sw[3]   = Multiplier engine select (0=DSP, 1=Booth)
                                    //   sw[1]   = 1 Hz Slow Clock mode
                                    //   sw[15]  = Step mode (0=Continuous, 1=Manual step via btnc)
    output wire [7:0]  an,          // 8-digit Seven-Segment Anodes (Pins J17..U13)
    output wire [6:0]  seg,         // 7-segment Cathodes (Pins T10..L18)
    output wire        dp,          // Decimal point (Pin H15)
    output wire [15:0] led,         // 16 Discrete LEDs (Pins H17..R18)
    output wire        uart_tx,     // UART TX pin (Pin D4 -> FTDI USB-UART)
    input  wire        uart_rx      // UART RX pin (Pin C4 <- FTDI USB-UART)
);

    // ------------------------------------------------------------------------
    // Reset Synchronizer
    // ------------------------------------------------------------------------
    reg [2:0] rst_sync;
    always @(posedge clk_100mhz or negedge cpu_resetn) begin
        if (!cpu_resetn)
            rst_sync <= 3'b000;
        else
            rst_sync <= {rst_sync[1:0], 1'b1};
    end
    wire sys_reset_n = rst_sync[2];

    // ------------------------------------------------------------------------
    // Single-Step Button Debouncer & Edge Detector (btnc)
    // ------------------------------------------------------------------------
    reg [19:0] btn_debounce_cnt;
    reg        btn_state;
    reg        btn_prev;
    wire       btn_pulse;

    always @(posedge clk_100mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            btn_debounce_cnt <= 20'd0;
            btn_state        <= 1'b0;
            btn_prev         <= 1'b0;
        end else begin
            btn_prev <= btn_state;
            if (btnc != btn_state) begin
                btn_debounce_cnt <= btn_debounce_cnt + 20'd1;
                if (btn_debounce_cnt == 20'hF_FFFF)
                    btn_state <= btnc;
            end else begin
                btn_debounce_cnt <= 20'd0;
            end
        end
    end
    assign btn_pulse = btn_state && !btn_prev;

    // ------------------------------------------------------------------------
    // Slow Clock Generator (1 Hz for visual debug)
    // ------------------------------------------------------------------------
    reg [26:0] slow_div_cnt;
    reg        slow_step_pulse;
    always @(posedge clk_100mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            slow_div_cnt    <= 27'd0;
            slow_step_pulse <= 1'b0;
        end else if (slow_div_cnt == 27'd99_999_999) begin
            slow_div_cnt    <= 27'd0;
            slow_step_pulse <= 1'b1;
        end else begin
            slow_div_cnt    <= slow_div_cnt + 27'd1;
            slow_step_pulse <= 1'b0;
        end
    end

    // ------------------------------------------------------------------------
    // Telemetry & Completion Wires
    // ------------------------------------------------------------------------
    wire uart_busy_w;
    wire banner_done_w;
    reg  prog_done;
    reg  saw_ret;
    reg  [2:0] drain_cnt;
    reg  [31:0] final_ret_pc;

    // ------------------------------------------------------------------------
    // Auto-stream step generator paced by UART (sw[15]=0, sw[1]=0)
    // ------------------------------------------------------------------------
    reg auto_step_pending;
    reg auto_step_pulse;
    always @(posedge clk_100mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            auto_step_pending <= 1'b0;
            auto_step_pulse   <= 1'b0;
        end else if (!sw[15] && !sw[1]) begin
            if (!uart_busy_w && banner_done_w && !prog_done && !auto_step_pending) begin
                auto_step_pulse   <= 1'b1;
                auto_step_pending <= 1'b1;
            end else begin
                auto_step_pulse <= 1'b0;
                if (uart_busy_w)
                    auto_step_pending <= 1'b0;
            end
        end else begin
            auto_step_pending <= 1'b0;
            auto_step_pulse   <= 1'b0;
        end
    end

    // Core step multiplexer
    wire core_step_pulse = sw[15] ? btn_pulse :
                          (sw[1]  ? slow_step_pulse : auto_step_pulse);

    wire core_clk = core_step_pulse && !prog_done;

    // ------------------------------------------------------------------------
    // Memories (BRAM Models for 4 KB IMEM & 4 KB DMEM)
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
    ) u_instr_mem (
        .clk   (core_clk),
        .pc    (imem_addr),
        .instr (imem_rdata)
    );

    data_mem #(
        .HEX_FILE("dmem.hex"),
        .WORDS(1024)
    ) u_data_mem (
        .clk   (core_clk),
        .re    (dmem_re),
        .raddr (dmem_addr),
        .rdata (dmem_rdata),
        .we    (dmem_we),
        .waddr (dmem_addr),
        .wdata (dmem_wdata),
        .wstrb (dmem_wstrb)
    );

    // ------------------------------------------------------------------------
    // RV32IMF 5-Stage Core Instance with Passive Performance CSRs
    // ------------------------------------------------------------------------
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

    // Feature 8 CSR telemetry buses
    wire [63:0] csr_cycle_count;
    wire [63:0] csr_instret_count;
    wire [63:0] csr_stall_count;
    wire [63:0] csr_branch_count;

    // Feed NOP into core once RET instruction has been fetched
    wire [31:0] imem_rdata_core = saw_ret ? 32'h0000_0013 : imem_rdata;

    pipeline_5stage #(
        .RESET_PC(32'h0000_0000)
    ) u_core (
        .clk              (core_clk),
        .reset_n          (sys_reset_n),
        .stall_ext        (prog_done),
        .use_dsp_i        (!sw[3]),
        .imem_addr        (imem_addr),
        .imem_rdata       (imem_rdata_core),
        .dmem_addr        (dmem_addr),
        .dmem_wdata       (dmem_wdata),
        .dmem_wstrb       (dmem_wstrb),
        .dmem_we          (dmem_we),
        .dmem_re          (dmem_re),
        .dmem_rdata       (dmem_rdata),
        .pc_if            (pc_if),
        .pc_id            (pc_id),
        .pc_ex            (pc_ex),
        .pc_mem           (pc_mem),
        .pc_wb            (pc_wb),
        .wb_reg_write     (wb_reg_write),
        .wb_dest_reg      (wb_dest_reg),
        .wb_data          (wb_data),
        .hazard_stall     (hazard_stall),
        .hazard_flush_id  (hazard_flush_id),
        .hazard_flush_ex  (hazard_flush_ex),
        .forward_a        (forward_a),
        .forward_b        (forward_b),
        .mul_active       (mul_active),
        .div_active       (div_active),
        .div_busy         (div_busy),
        .fpu_active       (fpu_active),
        .fpu_busy         (fpu_busy),
        .exception        (exception),
        .csr_cycle_count  (csr_cycle_count),
        .csr_instret_count(csr_instret_count),
        .csr_stall_count  (csr_stall_count),
        .csr_branch_count (csr_branch_count)
    );

    // ------------------------------------------------------------------------
    // Program Execution Complete Detector
    // Detects RET (32'h00008067), drains pipeline, then halts
    // ------------------------------------------------------------------------
    always @(posedge clk_100mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            saw_ret      <= 1'b0;
            drain_cnt    <= 3'd0;
            prog_done    <= 1'b0;
            final_ret_pc <= 32'd0;
        end else begin
            if (imem_rdata == 32'h0000_8067 && pc_if != 32'h0 && core_step_pulse && !hazard_stall) begin
                saw_ret      <= 1'b1;
                final_ret_pc <= pc_if;
            end
            if (saw_ret && core_step_pulse && !prog_done) begin
                if (!hazard_stall) begin
                    if (drain_cnt < 3'd4)
                        drain_cnt <= drain_cnt + 3'd1;
                    else
                        prog_done <= 1'b1;
                end
            end
        end
    end

    // Latch final return value a0 (x10) when committed
    reg [31:0] final_result_a0;
    always @(posedge clk_100mhz or negedge sys_reset_n) begin
        if (!sys_reset_n)
            final_result_a0 <= 32'd0;
        else if (core_step_pulse && wb_reg_write && wb_dest_reg == 5'd10)
            final_result_a0 <= wb_data;
    end

    // ------------------------------------------------------------------------
    // Dedicated UART Subsystem with Boot Banner & Real-Time Telemetry
    // ------------------------------------------------------------------------
    wire [31:0] uart_fetch_pc   = (saw_ret || prog_done) ? final_ret_pc : pc_if;
    wire [31:0] uart_fetch_inst = (saw_ret || prog_done) ? 32'h0000_8067 : imem_rdata;

    wire [31:0] mmio_rdata;
    wire        mmio_match;

    uart_unit #(
        .CLK_FREQ   (100_000_000),
        .BAUD_RATE  (115_200),
        .FIFO_DEPTH (64)
    ) u_uart (
        .clk             (clk_100mhz),
        .reset_n         (sys_reset_n),
        .dmem_addr       (dmem_addr),
        .dmem_wdata      (dmem_wdata),
        .dmem_we         (dmem_we),
        .dmem_re         (dmem_re),
        .uart_rdata      (mmio_rdata),
        .uart_addr_match (mmio_match),
        .fetch_pc        (uart_fetch_pc),
        .fetch_inst      (uart_fetch_inst),
        .hazard_stall    (hazard_stall),
        .step_trigger    (core_step_pulse && !prog_done),
        .uart_tx         (uart_tx),
        .uart_busy       (uart_busy_w),
        .banner_done_o   (banner_done_w),
        .prog_done       (prog_done),
        .stat_cycles     (csr_cycle_count[31:0]),
        .stat_insts      (csr_instret_count[31:0]),
        .stat_stalls     (csr_stall_count[31:0]),
        .stat_result     (final_result_a0)
    );

    // ------------------------------------------------------------------------
    // Pulse Stretchers for Visual LED Indicators (~40 ms at 100 MHz)
    // ------------------------------------------------------------------------
    wire fwd_active = (forward_a != 2'b00) || (forward_b != 2'b00);

    reg [22:0] hazard_stretch_cnt;
    reg [22:0] fwd_stretch_cnt;
    reg [22:0] flush_stretch_cnt;
    reg [22:0] mul_stretch_cnt;
    reg [22:0] div_stretch_cnt;
    reg [22:0] fpu_stretch_cnt;
    reg [22:0] csr_stretch_cnt;

    always @(posedge clk_100mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            hazard_stretch_cnt <= 23'd0;
            fwd_stretch_cnt    <= 23'd0;
            flush_stretch_cnt  <= 23'd0;
            mul_stretch_cnt    <= 23'd0;
            div_stretch_cnt    <= 23'd0;
            fpu_stretch_cnt    <= 23'd0;
            csr_stretch_cnt    <= 23'd0;
        end else begin
            if (hazard_stall)   hazard_stretch_cnt <= 23'd4_000_000;
            else if (hazard_stretch_cnt > 0) hazard_stretch_cnt <= hazard_stretch_cnt - 23'd1;

            if (fwd_active)     fwd_stretch_cnt    <= 23'd4_000_000;
            else if (fwd_stretch_cnt > 0) fwd_stretch_cnt <= fwd_stretch_cnt - 23'd1;

            if (hazard_flush_id) flush_stretch_cnt  <= 23'd4_000_000;
            else if (flush_stretch_cnt > 0) flush_stretch_cnt <= flush_stretch_cnt - 23'd1;

            if (mul_active)     mul_stretch_cnt    <= 23'd4_000_000;
            else if (mul_stretch_cnt > 0) mul_stretch_cnt <= mul_stretch_cnt - 23'd1;

            if (div_active || div_busy) div_stretch_cnt <= 23'd4_000_000;
            else if (div_stretch_cnt > 0) div_stretch_cnt <= div_stretch_cnt - 23'd1;

            if (fpu_active || fpu_busy) fpu_stretch_cnt <= 23'd4_000_000;
            else if (fpu_stretch_cnt > 0) fpu_stretch_cnt <= fpu_stretch_cnt - 23'd1;

            if (u_core.id_ex_is_csr) csr_stretch_cnt <= 23'd4_000_000;
            else if (csr_stretch_cnt > 0) csr_stretch_cnt <= csr_stretch_cnt - 23'd1;
        end
    end

    // ------------------------------------------------------------------------
    // LED Output Mapping
    // ------------------------------------------------------------------------
    assign led[0]  = (hazard_stretch_cnt > 0);
    assign led[1]  = (fwd_stretch_cnt > 0);
    assign led[2]  = (flush_stretch_cnt > 0);
    assign led[3]  = wb_reg_write;
    assign led[4]  = (mul_stretch_cnt > 0);
    assign led[5]  = (div_stretch_cnt > 0);
    assign led[6]  = (fpu_stretch_cnt > 0);
    assign led[7]  = prog_done;
    assign led[8]  = (csr_stretch_cnt > 0);
    assign led[15:9] = prog_done ? final_result_a0[6:0] : wb_data[6:0];

    // ------------------------------------------------------------------------
    // 8-Digit Seven-Segment Display Multiplexer
    // ------------------------------------------------------------------------
    reg [31:0] display_data;
    always @(*) begin
        case (sw[2:0])
            3'b000: display_data = pc_if;
            3'b001: display_data = imem_rdata;
            3'b010: display_data = csr_cycle_count[31:0];
            3'b011: display_data = csr_instret_count[31:0];
            3'b100: display_data = csr_stall_count[31:0];
            3'b101: display_data = csr_branch_count[31:0];
            3'b110: display_data = final_result_a0;
            default: display_data = pc_if;
        endcase
    end

    seven_seg_controller u_seven_seg (
        .clk       (clk_100mhz),
        .reset_n   (sys_reset_n),
        .data_in   (display_data),
        .an        (an),
        .seg       (seg),
        .dp        (dp)
    );

endmodule
