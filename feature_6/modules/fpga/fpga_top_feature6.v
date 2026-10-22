// ============================================================================
// File: fpga_top_feature6.v
// Module: fpga_top_feature6
// Description: Synthesizable FPGA Top-Level Module for Feature 6 (L1 Harvard Caches)
//              Target Board: Digilent Nexys A7-100T (Xilinx Artix-7 XC7A100T-1CSG324C)
//              Features:
//              - 50 MHz Core Clock Derived from 100 MHz Oscillator
//              - RV32IMF Core with 2 KB L1 I-Cache & 2 KB L1 D-Cache
//              - 115200 Baud UART Subsystem (Boot Banner, Telemetry, MMIO)
//              - 8-Digit Multiplexed 7-Segment Display with Multiple Diagnostic Modes
//              - Real-Time Cache Hit/Miss Pulse Stretchers on Diagnostic LEDs
// ============================================================================

`timescale 1ns/1ps

module fpga_top_feature6 (
    input  wire        CLK100MHZ,      // 100 MHz onboard oscillator
    input  wire        CPU_RESETN,     // Active-low CPU reset push button
    input  wire        BTNC,           // Center push button: diagnostic counter reset
    input  wire [15:0] SW,             // Slide switches
    output wire [15:0] LED,            // Status and diagnostic LEDs
    output wire [7:0]  AN,             // 7-segment digit anodes (active low)
    output wire [6:0]  SEG,            // 7-segment cathode segments (active low)
    output wire        DP,             // 7-segment decimal point
    output wire        UART_TXD_IN     // Serial TX to FTDI USB-UART bridge
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

    // Synchronize center push button
    reg [2:0] btnc_sync = 3'b000;
    always @(posedge clk_50mhz) begin
        btnc_sync <= {btnc_sync[1:0], BTNC};
    end
    wire btnc_pressed = btnc_sync[2];

    // ========================================================================
    // 2. Memory Bus Interconnects
    // ========================================================================
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;
    wire        imem_req;

    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we;
    wire        dmem_req;
    wire [31:0] dmem_rdata;

    wire [31:0] mmio_addr;
    wire [31:0] mmio_wdata;
    wire        mmio_we;
    wire        mmio_re;
    wire [31:0] mmio_rdata;
    wire        mmio_match;

    // Pipeline telemetry
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

    // Cache Diagnostics
    wire        icache_stall;
    wire        icache_hit;
    wire        icache_miss;
    wire [31:0] icache_hit_count;
    wire [31:0] icache_miss_count;

    wire        dcache_stall;
    wire        dcache_hit;
    wire        dcache_miss;
    wire [31:0] dcache_hit_count;
    wire [31:0] dcache_miss_count;

    wire        uart_tx;
    wire        uart_busy;
    wire        banner_done;

    // ========================================================================
    // 3. Backing Memories (4 KB IMEM & 4 KB DMEM)
    // ========================================================================
    instr_mem #(
        .HEX_FILE ("imem.hex"),
        .WORDS    (1024)
    ) u_backing_imem (
        .clk   (clk_50mhz),
        .pc    (imem_addr),
        .instr (imem_rdata)
    );

    data_mem #(
        .HEX_FILE ("dmem.hex"),
        .WORDS    (1024)
    ) u_backing_dmem (
        .clk   (clk_50mhz),
        .re    (dmem_req),
        .raddr (dmem_addr),
        .rdata (dmem_rdata),
        .we    (dmem_we),
        .waddr (dmem_addr),
        .wdata (dmem_wdata),
        .wstrb (dmem_wstrb)
    );

    // ========================================================================
    // 4. Pipelined RV32IMF Core with L1 Harvard Caches
    // ========================================================================
    pipeline_5stage #(
        .RESET_PC(32'h0000_0000)
    ) u_core (
        .clk               (clk_50mhz),
        .reset_n           (reset_n),
        .stall_ext         (~SW[0]),          // SW[0] = 1 enables free-running pipeline
        .use_dsp_i         (SW[2]),           // SW[2] = 1 selects DSP multiplier
        .icache_bypass_i   (SW[1]),           // SW[1] = 1 enables I-Cache bypass mode
        .imem_addr         (imem_addr),
        .imem_rdata        (imem_rdata),
        .imem_req          (imem_req),
        .dmem_addr         (dmem_addr),
        .dmem_wdata        (dmem_wdata),
        .dmem_wstrb        (dmem_wstrb),
        .dmem_we           (dmem_we),
        .dmem_req          (dmem_req),
        .dmem_rdata        (dmem_rdata),
        .mmio_addr_o       (mmio_addr),
        .mmio_wdata_o      (mmio_wdata),
        .mmio_we_o         (mmio_we),
        .mmio_re_o         (mmio_re),
        .mmio_rdata_i      (mmio_rdata),
        .mmio_match_i      (mmio_match),
        .pc_if             (pc_if),
        .pc_id             (pc_id),
        .pc_ex             (pc_ex),
        .pc_mem            (pc_mem),
        .pc_wb             (pc_wb),
        .wb_reg_write      (wb_reg_write),
        .wb_dest_reg       (wb_dest_reg),
        .wb_data           (wb_data),
        .hazard_stall      (hazard_stall),
        .hazard_flush_id   (hazard_flush_id),
        .hazard_flush_ex   (hazard_flush_ex),
        .forward_a         (forward_a),
        .forward_b         (forward_b),
        .mul_active        (mul_active),
        .div_active        (div_active),
        .div_busy          (div_busy),
        .fpu_active        (fpu_active),
        .fpu_busy          (fpu_busy),
        .exception         (exception),
        .icache_stall      (icache_stall),
        .icache_hit        (icache_hit),
        .icache_miss       (icache_miss),
        .icache_hit_count  (icache_hit_count),
        .icache_miss_count (icache_miss_count),
        .dcache_stall      (dcache_stall),
        .dcache_hit        (dcache_hit),
        .dcache_miss       (dcache_miss),
        .dcache_hit_count  (dcache_hit_count),
        .dcache_miss_count (dcache_miss_count)
    );

    // ========================================================================
    // 5. Dedicated UART Subsystem
    // ========================================================================
    uart_unit #(
        .CLK_FREQ   (50_000_000),
        .BAUD_RATE  (115_200),
        .FIFO_DEPTH (64)
    ) u_uart (
        .clk             (clk_50mhz),
        .reset_n         (reset_n),
        .dmem_addr       (mmio_addr),
        .dmem_wdata      (mmio_wdata),
        .dmem_we         (mmio_we),
        .dmem_re         (mmio_re),
        .uart_rdata      (mmio_rdata),
        .uart_addr_match (mmio_match),
        .fetch_pc        (pc_if),
        .fetch_inst      (imem_rdata),
        .hazard_stall    (hazard_stall),
        .step_trigger    (SW[0]),
        .uart_tx         (uart_tx),
        .uart_busy       (uart_busy),
        .banner_done_o   (banner_done)
    );

    assign UART_TXD_IN = uart_tx;

    // ========================================================================
    // 6. Pulse Stretchers for Cache Hit/Miss Observation on LEDs
    // ========================================================================
    reg [21:0] icache_hit_timer  = 22'd0;
    reg [21:0] icache_miss_timer = 22'd0;
    reg [21:0] dcache_hit_timer  = 22'd0;
    reg [21:0] dcache_miss_timer = 22'd0;

    localparam STRETCH_CYCLES = 22'd2_500_000; // ~50 ms pulse at 50 MHz

    always @(posedge clk_50mhz or negedge reset_n) begin
        if (!reset_n) begin
            icache_hit_timer  <= 22'd0;
            icache_miss_timer <= 22'd0;
            dcache_hit_timer  <= 22'd0;
            dcache_miss_timer <= 22'd0;
        end else begin
            if (icache_hit)
                icache_hit_timer <= STRETCH_CYCLES;
            else if (icache_hit_timer != 0)
                icache_hit_timer <= icache_hit_timer - 1'b1;

            if (icache_miss)
                icache_miss_timer <= STRETCH_CYCLES;
            else if (icache_miss_timer != 0)
                icache_miss_timer <= icache_miss_timer - 1'b1;

            if (dcache_hit)
                dcache_hit_timer <= STRETCH_CYCLES;
            else if (dcache_hit_timer != 0)
                dcache_hit_timer <= dcache_hit_timer - 1'b1;

            if (dcache_miss)
                dcache_miss_timer <= STRETCH_CYCLES;
            else if (dcache_miss_timer != 0)
                dcache_miss_timer <= dcache_miss_timer - 1'b1;
        end
    end

    // Heartbeat counter (flashes LED[15] ~1.5 Hz)
    reg [24:0] heartbeat_cnt = 25'd0;
    always @(posedge clk_50mhz) heartbeat_cnt <= heartbeat_cnt + 1'b1;

    // Assign Diagnostic LEDs
    assign LED[7:0]   = pc_wb[9:2];                             // Retired PC word index
    assign LED[8]     = (icache_hit_timer != 0);                // I-Cache Hit pulse (Green)
    assign LED[9]     = (icache_miss_timer != 0);               // I-Cache Miss pulse (Orange)
    assign LED[10]    = (dcache_hit_timer != 0);                // D-Cache Hit pulse
    assign LED[11]    = (dcache_miss_timer != 0);               // D-Cache Miss pulse
    assign LED[12]    = div_busy || fpu_busy;                   // Math engine busy
    assign LED[13]    = hazard_stall;                           // Pipeline stall active
    assign LED[14]    = uart_busy;                              // UART transmitter active
    assign LED[15]    = heartbeat_cnt[24];                      // Core alive heartbeat

    // ========================================================================
    // 7. Seven-Segment Multiplexed Display Controller
    // ========================================================================
    reg [31:0] display_data;
    always @(*) begin
        case (SW[5:3])
            3'b000: display_data = pc_wb;                                     // Mode 0: Retired PC
            3'b001: display_data = wb_data;                                   // Mode 1: Writeback Data
            3'b010: display_data = {16'h0, icache_hit_count[15:0]};           // Mode 2: I-Cache Hit Count
            3'b011: display_data = {16'h0, icache_miss_count[15:0]};          // Mode 3: I-Cache Miss Count
            3'b100: display_data = {16'h0, dcache_hit_count[15:0]};           // Mode 4: D-Cache Hit Count
            3'b101: display_data = {16'h0, dcache_miss_count[15:0]};          // Mode 5: D-Cache Miss Count
            3'b110: display_data = imem_rdata;                                // Mode 6: Fetched Instruction
            3'b111: display_data = {27'h0, wb_dest_reg};                      // Mode 7: Writeback Destination Reg
        endcase
    end

    seven_seg_controller u_seven_seg (
        .clk        (clk_50mhz),
        .reset_n    (reset_n),
        .data_in    (display_data),
        .point_in   (8'h00),
        .anode_o    (AN),
        .segment_o  (SEG),
        .dp_o       (DP)
    );

endmodule
