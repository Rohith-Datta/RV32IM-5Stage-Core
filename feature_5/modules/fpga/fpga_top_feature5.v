// ============================================================================
// File: fpga_top_feature5.v
// Description: Dedicated Top-Level Synthesizable FPGA Implementation for Feature 5
//              (RV32IMF Core with Direct-Mapped L1 D-Cache & Real-Time UART Telemetry)
// Target Device: Xilinx Artix-7 XC7A100T-1CSG324C (Digilent Nexys A7-100T Board)
//
// Key Features Mapped to Board Peripherals:
// 1. 8-Digit Seven-Segment Display:
//    - sw[2] = 0: Shows 32-bit Program Counter Fetch Address (pc_if).
//    - sw[2] = 1: Shows 32-bit Machine Instruction Code (imem_rdata).
// 2. Hardware Engine Selection (Switch sw[3]):
//    - sw[3] = 0: DSP48E1 Multiplier Mode
//    - sw[3] = 1: Radix-4 Booth Multiplier Mode
// 3. LED Hardware Diagnostics:
//    - LED[0]: Hazard Stall Active (Load-use, DIV, FPU, or L1 D-Cache miss)
//    - LED[1]: Data Forwarding Active (Operand bypass into ALU/MUL/DIV/FPU)
//    - LED[2]: Branch / Speculative Flush
//    - LED[3]: Instruction Writeback Commit (wb_reg_write)
//    - LED[4]: Multiplier Unit Active Indicator (mul_active in EX)
//    - LED[5]: Divider Unit Active Indicator (div_active in EX)
//    - LED[6]: FPU Unit Active Indicator (fpu_active in EX)
//    - LED[7]: Program Execution Completed (prog_done)
//    - LED[8]: L1 D-Cache Hit Pulse Indicator
//    - LED[9]: L1 D-Cache Miss Pulse Indicator
//    - LED[15:10]: Low bits of committed result
// 4. Clocking & Execution Controls:
//    - Standard 50 MHz core clock derived from 100 MHz board oscillator
//    - sw[0] = 0, sw[1] = 0: Paced real-time streaming with UART
//    - sw[0] = 0, sw[1] = 1: 1 Hz Slow Clock mode for live visual observation
//    - sw[0] = 1: Manual Single-Step mode via Center Pushbutton (btnc)
//    - cpu_resetn: Active-low synchronous reset button (Pin C12)
// 5. USB-UART Serial Telemetry (115,200 Baud on Pin D4):
//    - Real-time zero-lag stream of fetched instructions and cache/hazard telemetry
// ============================================================================

`timescale 1ns/1ps

module fpga_top_feature5 (
    input  wire        clk_100mhz,  // 100 MHz primary oscillator (Pin E3)
    input  wire        cpu_resetn,  // Active-low CPU reset pushbutton (Pin C12)
    input  wire        btnc,        // Center pushbutton for single-stepping (Pin N17)
    input  wire [3:0]  sw,          // Slide switches:
                                    //   sw[0] = Step mode (0=Continuous, 1=Manual step via btnc)
                                    //   sw[1] = 1Hz slow clock (0=Auto-paced, 1=1Hz)
                                    //   sw[2] = Display select (0=PC Address, 1=Instruction Code)
                                    //   sw[3] = Multiplier select (0=DSP48E1, 1=Booth Radix-4)
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
    // 50 MHz Synchronous Core Clock Generator (Derived from 100 MHz Oscillator)
    // ------------------------------------------------------------------------
    (* keep = "true" *) reg clk_50mhz;
    always @(posedge clk_100mhz or negedge sys_reset_n) begin
        if (!sys_reset_n)
            clk_50mhz <= 1'b0;
        else
            clk_50mhz <= ~clk_50mhz;
    end

    // ------------------------------------------------------------------------
    // Slow Clock Generator (1 Hz for visual debug) & Step Clock Arbiter
    // ------------------------------------------------------------------------
    reg [24:0] slow_clk_div;
    reg        slow_clk_tick;
    always @(posedge clk_50mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            slow_clk_div  <= 25'd0;
            slow_clk_tick <= 1'b0;
        end else if (slow_clk_div == 25'd24_999_999) begin
            slow_clk_div  <= 25'd0;
            slow_clk_tick <= 1'b1;
        end else begin
            slow_clk_div  <= slow_clk_div + 25'd1;
            slow_clk_tick <= 1'b0;
        end
    end

    // Clock enable gating for execution pacing
    reg core_clk_en;
    always @(*) begin
        if (sw[0])
            core_clk_en = btn_pulse;
        else if (sw[1])
            core_clk_en = slow_clk_tick;
        else
            core_clk_en = 1'b1;
    end

    wire stall_from_clock = !core_clk_en;

    // ------------------------------------------------------------------------
    // Memories (BRAM Models for 4 KB IMEM & 4 KB DMEM)
    // ------------------------------------------------------------------------
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;

    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we;
    wire        dmem_req;
    wire [31:0] dmem_rdata;

    instr_mem #(
        .HEX_FILE("imem.hex"),
        .WORDS(1024)
    ) u_instr_mem (
        .clk   (clk_50mhz),
        .pc    (imem_addr),
        .instr (imem_rdata)
    );

    data_mem #(
        .HEX_FILE("dmem.hex"),
        .WORDS(1024)
    ) u_data_mem (
        .clk   (clk_50mhz),
        .re    (dmem_req),
        .raddr (dmem_addr),
        .rdata (dmem_rdata),
        .we    (dmem_we),
        .waddr (dmem_addr),
        .wdata (dmem_wdata),
        .wstrb (dmem_wstrb)
    );

    // ------------------------------------------------------------------------
    // RV32IMF 5-Stage Core Instance with L1 D-Cache
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

    wire        dcache_stall;
    wire        dcache_hit;
    wire        dcache_miss;
    wire [31:0] dcache_hit_count;
    wire [31:0] dcache_miss_count;

    wire [31:0] mmio_addr;
    wire [31:0] mmio_wdata;
    wire        mmio_we;
    wire        mmio_re;
    wire [31:0] mmio_rdata;
    wire        mmio_match;

    pipeline_5stage #(
        .RESET_PC(32'h0000_0000)
    ) u_core (
        .clk              (clk_50mhz),
        .reset_n          (sys_reset_n),
        .stall_ext        (stall_from_clock),
        .use_dsp_i        (!sw[3]),
        .imem_addr        (imem_addr),
        .imem_rdata       (imem_rdata),
        .dmem_addr        (dmem_addr),
        .dmem_wdata       (dmem_wdata),
        .dmem_wstrb       (dmem_wstrb),
        .dmem_we          (dmem_we),
        .dmem_req         (dmem_req),
        .dmem_rdata       (dmem_rdata),
        .mmio_addr_o      (mmio_addr),
        .mmio_wdata_o     (mmio_wdata),
        .mmio_we_o        (mmio_we),
        .mmio_re_o        (mmio_re),
        .mmio_rdata_i     (mmio_rdata),
        .mmio_match_i     (mmio_match),
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
        .dcache_stall     (dcache_stall),
        .dcache_hit       (dcache_hit),
        .dcache_miss      (dcache_miss),
        .dcache_hit_count (dcache_hit_count),
        .dcache_miss_count(dcache_miss_count)
    );

    // ------------------------------------------------------------------------
    // Dedicated UART Subsystem with Boot Banner & Real-Time Telemetry
    // ------------------------------------------------------------------------
    wire uart_busy_w;
    wire banner_done_w;

    uart_unit #(
        .CLK_FREQ   (100_000_000),
        .BAUD_RATE  (115_200),
        .FIFO_DEPTH (64)
    ) u_uart (
        .clk             (clk_100mhz),
        .reset_n         (sys_reset_n),
        .dmem_addr       (mmio_addr),
        .dmem_wdata      (mmio_wdata),
        .dmem_we         (mmio_we),
        .dmem_re         (mmio_re),
        .uart_rdata      (mmio_rdata),
        .uart_addr_match (mmio_match),
        .fetch_pc        (pc_if),
        .fetch_inst      (imem_rdata),
        .hazard_stall    (hazard_stall),
        .step_trigger    (core_clk_en),
        .uart_tx         (uart_tx),
        .uart_busy       (uart_busy_w),
        .banner_done_o   (banner_done_w)
    );

    // ------------------------------------------------------------------------
    // Pulse Stretchers for D-Cache Hit/Miss LED Indicators
    // ------------------------------------------------------------------------
    reg [21:0] hit_stretch_cnt;
    reg        hit_led_reg;
    always @(posedge clk_50mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            hit_stretch_cnt <= 22'd0;
            hit_led_reg     <= 1'b0;
        end else if (dcache_hit) begin
            hit_stretch_cnt <= 22'h3F_FFFF;
            hit_led_reg     <= 1'b1;
        end else if (hit_stretch_cnt > 0) begin
            hit_stretch_cnt <= hit_stretch_cnt - 22'd1;
            hit_led_reg     <= 1'b1;
        end else begin
            hit_led_reg     <= 1'b0;
        end
    end

    reg [21:0] miss_stretch_cnt;
    reg        miss_led_reg;
    always @(posedge clk_50mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            miss_stretch_cnt <= 22'd0;
            miss_led_reg     <= 1'b0;
        end else if (dcache_miss) begin
            miss_stretch_cnt <= 22'h3F_FFFF;
            miss_led_reg     <= 1'b1;
        end else if (miss_stretch_cnt > 0) begin
            miss_stretch_cnt <= miss_stretch_cnt - 22'd1;
            miss_led_reg     <= 1'b1;
        end else begin
            miss_led_reg     <= 1'b0;
        end
    end

    // ------------------------------------------------------------------------
    // Program Execution Complete Detector
    // ------------------------------------------------------------------------
    reg prog_done;
    always @(posedge clk_50mhz or negedge sys_reset_n) begin
        if (!sys_reset_n)
            prog_done <= 1'b0;
        else if (imem_rdata == 32'h00008067 && !hazard_stall)
            prog_done <= 1'b1;
    end

    // ------------------------------------------------------------------------
    // Discrete LED Output Mapping
    // ------------------------------------------------------------------------
    assign led[0]     = hazard_stall;
    assign led[1]     = (forward_a != 2'b00) || (forward_b != 2'b00);
    assign led[2]     = hazard_flush_id || hazard_flush_ex;
    assign led[3]     = wb_reg_write;
    assign led[4]     = mul_active;
    assign led[5]     = div_active || div_busy;
    assign led[6]     = fpu_active || fpu_busy;
    assign led[7]     = prog_done;
    assign led[8]     = hit_led_reg;
    assign led[9]     = miss_led_reg;
    assign led[15:10] = wb_data[5:0];

    // ------------------------------------------------------------------------
    // 8-Digit Seven-Segment Multiplexed Controller
    // ------------------------------------------------------------------------
    wire [31:0] display_value = sw[2] ? imem_rdata : pc_if;

    seven_seg_controller u_seven_seg (
        .clk         (clk_100mhz),
        .reset_n     (sys_reset_n),
        .display_num (display_value),
        .an          (an),
        .seg         (seg),
        .dp          (dp)
    );

endmodule
