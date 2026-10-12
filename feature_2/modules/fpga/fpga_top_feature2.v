// ============================================================================
// File: fpga_top_feature2.v
// Description: Dedicated Top-Level Synthesizable FPGA Implementation for Feature 2
//              (RV32IM Multiplier Integrated Core with Real-Time UART Telemetry)
// Target Device: Xilinx Artix-7 XC7A100T-1CSG324C (Digilent Nexys A7-100T Board)
//
// Key Features Mapped to Board Peripherals:
// 1. 8-Digit Seven-Segment Display (Directly above LEDs):
//    - sw[2] = 0: Shows 32-bit Program Counter Fetch Address (pc_if, e.g. 00000028).
//    - sw[2] = 1: Shows 32-bit Machine Instruction Code (imem_rdata, e.g. 02F707B3 for MUL).
// 2. Hardware Multiplier Engine Selection (Switch sw[3]):
//    - sw[3] = 0: Xilinx Artix-7 DSP48E1 Slices (High-speed single-cycle DSP multiplication).
//    - sw[3] = 1: Radix-4 Modified Booth Multiplier RTL.
// 3. LED Hardware Diagnostics:
//    - LED[0]: Data Hazard Detected (Load-use stall freeze before multiplication).
//    - LED[1]: Data Forwarding Active (Operand bypass into multiplier).
//    - LED[2]: Branch / Speculative Flush.
//    - LED[3]: Instruction Writeback Commit (wb_reg_write).
//    - LED[4]: Multiplier Unit Active Indicator (is_mul in EX stage).
//    - LED[5]: DSP Hardware Mode Active (sw[3] == 0).
//    - LED[15:8]: Low byte of committed result (wb_data[7:0], e.g. 0x2A for 6x7=42, or 0x90 for 25x16=400).
// 4. Clocking & Execution Controls:
//    - sw[0] = 0, sw[1] = 0: Paced real-time streaming with UART
//    - sw[0] = 0, sw[1] = 1: 1 Hz Slow Clock mode for live visual observation
//    - sw[0] = 1: Manual Single-Step mode via Center Pushbutton (btnc)
//    - cpu_resetn: Active-low synchronous reset button (Pin C12).
// 5. USB-UART Serial Telemetry (115,200 Baud on Pin D4):
//    - Real-time zero-lag stream of each fetched instruction & hazard stalls
// ============================================================================

`timescale 1ns/1ps

module fpga_top_feature2 (
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
    // 1 Hz slow step generator (sw[1]=1)
    // ------------------------------------------------------------------------
    reg [26:0] clk_div_cnt;
    reg        slow_step_pulse;
    always @(posedge clk_100mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            clk_div_cnt     <= 27'd0;
            slow_step_pulse <= 1'b0;
        end else if (clk_div_cnt == 27'd99_999_999) begin
            clk_div_cnt     <= 27'd0;
            slow_step_pulse <= 1'b1;
        end else begin
            clk_div_cnt     <= clk_div_cnt + 27'd1;
            slow_step_pulse <= 1'b0;
        end
    end

    // Multiplier hardware selection: sw[3]=0 -> DSP (1), sw[3]=1 -> Booth (0)
    wire use_dsp_mode = ~sw[3];

    // ------------------------------------------------------------------------
    // Core Interconnect Buses
    // ------------------------------------------------------------------------
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;

    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we;
    wire        dmem_re;
    wire [31:0] dmem_rdata;

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
    wire        exception;

    wire        uart_busy;
    wire        banner_done;

    // Automatic Halt on Program Completion:
    // When the C program executes `ret` (32'h00008067) from main, allows remaining
    // instructions in pipeline to drain through WB (CC=20: lw ra, CC=21: lw s0, CC=22: addi sp, CC=23: ret),
    // then halts cleanly so the processor does not loop infinitely.
    reg       saw_ret;
    reg [2:0] drain_cnt;
    reg       prog_done;
    wire      core_step_pulse;

    always @(posedge clk_100mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            saw_ret   <= 1'b0;
            drain_cnt <= 3'd0;
            prog_done <= 1'b0;
        end else begin
            if (imem_rdata == 32'h0000_8067 && imem_addr != 32'h0 && core_step_pulse && !hazard_stall)
                saw_ret <= 1'b1;
            if (saw_ret && core_step_pulse && !prog_done) begin
                if (!hazard_stall) begin
                    if (drain_cnt < 3'd3)
                        drain_cnt <= drain_cnt + 3'd1;
                    else
                        prog_done <= 1'b1;
                end
            end
        end
    end


    // Auto-stream step generator (sw[0]=0, sw[1]=0):
    // Advances the CPU by exactly 1 cycle each time UART finishes transmitting a line:
    reg auto_step_pending;
    reg auto_step_pulse;
    always @(posedge clk_100mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            auto_step_pending <= 1'b0;
            auto_step_pulse   <= 1'b0;
        end else if (!sw[0] && !sw[1]) begin // Auto continuous stream mode
            if (!uart_busy && banner_done && !prog_done && !auto_step_pending) begin
                auto_step_pulse   <= 1'b1;
                auto_step_pending <= 1'b1;
            end else begin
                auto_step_pulse <= 1'b0;
                if (uart_busy)
                    auto_step_pending <= 1'b0;
            end
        end else begin
            auto_step_pending <= 1'b0;
            auto_step_pulse   <= 1'b0;
        end
    end

    // Unified step pulse:
    // sw[0] = 1 : Manual step via Center Pushbutton (btnc)
    // sw[0] = 0, sw[1] = 1 : Slow 1 Hz auto-step
    // sw[0] = 0, sw[1] = 0 : Paced real-time streaming with UART
    assign core_step_pulse = (sw[0]) ? btn_pulse :
                             ((sw[1]) ? slow_step_pulse : auto_step_pulse);

    wire core_clk = core_step_pulse && !prog_done;

    // ------------------------------------------------------------------------
    // Final Return PC Latch & Telemetry Clamping
    // Latches the address of `ret` so UART and 7-seg never broadcast rodata
    // or branch flush addresses (0x00) during pipeline drain cycles (CC=20..22).
    // ------------------------------------------------------------------------
    reg [31:0] final_ret_pc;
    always @(posedge clk_100mhz or negedge sys_reset_n) begin
        if (!sys_reset_n)
            final_ret_pc <= 32'd0;
        else if (imem_rdata == 32'h0000_8067 && imem_addr != 32'h0)
            final_ret_pc <= imem_addr; // Latch 0x00000044
    end

    wire [31:0] uart_fetch_pc   = (saw_ret || prog_done) ? final_ret_pc : imem_addr;
    wire [31:0] uart_fetch_inst = (saw_ret || prog_done) ? 32'h0000_8067 : imem_rdata;

    // ------------------------------------------------------------------------
    // 5-Stage RV32IM Processor Core Instance (Feature 2)
    // ------------------------------------------------------------------------
    wire [31:0] imem_rdata_core = saw_ret ? 32'h0000_0013 : imem_rdata; // Feed NOP into pipeline during drain

    pipeline_5stage #(
        .RESET_PC(32'h0000_0000)
    ) u_core (
        .clk            (core_clk),
        .reset_n        (sys_reset_n),
        .stall_ext      (prog_done),
        .use_dsp_i      (use_dsp_mode),
        .imem_addr      (imem_addr),
        .imem_rdata     (imem_rdata_core),
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
        .exception      (exception)
    );

    // ------------------------------------------------------------------------
    // On-Chip Memories (IMEM & DMEM)
    // ------------------------------------------------------------------------
    instr_mem #(
        .HEX_FILE("imem.hex"),
        .WORDS(1024)
    ) u_imem (
        .clk  (core_clk),
        .pc   (imem_addr),
        .instr(imem_rdata)
    );

    // ------------------------------------------------------------------------
    // UART Subsystem (Memory-Mapped I/O + Telemetry + Boot Banner)
    // MMIO Address Range: 0x8000_0000 (TX Data), 0x8000_0004 (Status)
    // ------------------------------------------------------------------------
    wire [31:0] uart_rdata;
    wire        uart_addr_match;

    uart_unit #(
        .CLK_FREQ  (100_000_000), // Clocked by 100 MHz oscillator for rock-solid baud
        .BAUD_RATE (115_200),
        .FIFO_DEPTH(64)
    ) u_uart (
        .clk            (clk_100mhz),
        .reset_n        (sys_reset_n),
        .dmem_addr      (dmem_addr),
        .dmem_wdata     (dmem_wdata),
        .dmem_we        (dmem_we),
        .dmem_re        (dmem_re),
        .uart_rdata     (uart_rdata),
        .uart_addr_match(uart_addr_match),
        .fetch_pc       (uart_fetch_pc),
        .fetch_inst     (uart_fetch_inst),
        .hazard_stall   (hazard_stall),
        .step_trigger   (core_step_pulse && !prog_done),
        .uart_tx        (uart_tx),
        .uart_busy      (uart_busy),
        .banner_done_o  (banner_done)
    );

    // RAM vs MMIO Data Multiplexing
    wire [31:0] dmem_ram_rdata;
    assign dmem_rdata = uart_addr_match ? uart_rdata : dmem_ram_rdata;
    wire dmem_ram_we  = dmem_we && !uart_addr_match;
    wire dmem_ram_re  = dmem_re && !uart_addr_match;

    data_mem #(
        .HEX_FILE("dmem.hex"),
        .WORDS(1024)
    ) u_dmem (
        .clk  (core_clk),
        .re   (dmem_ram_re),
        .raddr(dmem_addr),
        .rdata(dmem_ram_rdata),
        .we   (dmem_ram_we),
        .waddr(dmem_addr),
        .wdata(dmem_wdata),
        .wstrb(dmem_wstrb)
    );

    // ------------------------------------------------------------------------
    // 8-Digit 7-Segment Display Controller
    // sw[2] = 0: Shows current Fetch PC Address (e.g. 00000028)
    // sw[2] = 1: Shows current 32-bit Machine Instruction (e.g. 02F707B3 for MUL)
    // ------------------------------------------------------------------------
    wire [31:0] display_pc   = (prog_done || saw_ret) ? final_ret_pc : imem_addr;
    wire [31:0] display_inst = (prog_done || saw_ret) ? 32'h0000_8067 : imem_rdata;
    wire [31:0] display_data = (sw[2]) ? display_inst : display_pc;

    // After the last instruction (ret) is fetched and moves to ID stage, display "--------"
    wire show_dashes = saw_ret || prog_done;

    seven_seg_controller u_seven_seg (
        .clk        (clk_100mhz),
        .reset_n    (sys_reset_n),
        .data_in    (display_data),
        .show_dashes(show_dashes),
        .an         (an),
        .seg        (seg),
        .dp         (dp)
    );

    // ------------------------------------------------------------------------
    // LED Indicators & Pulse Stretchers
    // Ensures single-cycle hazard stalls, forwarding, and multiplier operations
    // remain visible to the human eye on the FPGA LEDs (~50ms stretch).
    // ------------------------------------------------------------------------
    wire fwd_active = (forward_a != 2'b00) || (forward_b != 2'b00);

    reg [22:0] hazard_stretch_cnt;
    reg [22:0] fwd_stretch_cnt;
    reg [22:0] flush_stretch_cnt;
    reg [22:0] mul_stretch_cnt;

    always @(posedge clk_100mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            hazard_stretch_cnt <= 23'd0;
            fwd_stretch_cnt    <= 23'd0;
            flush_stretch_cnt  <= 23'd0;
            mul_stretch_cnt    <= 23'd0;
        end else begin
            // Hazard stall stretcher (~40 ms at 100MHz)
            if (hazard_stall)
                hazard_stretch_cnt <= 23'h40_0000;
            else if (hazard_stretch_cnt > 0)
                hazard_stretch_cnt <= hazard_stretch_cnt - 23'd1;

            // Forwarding stretcher (~40 ms)
            if (fwd_active)
                fwd_stretch_cnt <= 23'h40_0000;
            else if (fwd_stretch_cnt > 0)
                fwd_stretch_cnt <= fwd_stretch_cnt - 23'd1;

            // Branch flush stretcher
            if (hazard_flush_id)
                flush_stretch_cnt <= 23'h40_0000;
            else if (flush_stretch_cnt > 0)
                flush_stretch_cnt <= flush_stretch_cnt - 23'd1;

            // Multiplier active stretcher
            if (mul_active)
                mul_stretch_cnt <= 23'h40_0000;
            else if (mul_stretch_cnt > 0)
                mul_stretch_cnt <= mul_stretch_cnt - 23'd1;
        end
    end

    // Latch final return value a0 (x10) when it commits to register file
    reg [7:0] final_result_a0;
    always @(posedge clk_100mhz or negedge sys_reset_n) begin
        if (!sys_reset_n)
            final_result_a0 <= 8'd0;
        else if (wb_reg_write && wb_dest_reg == 5'd10) // a0 (x10)
            final_result_a0 <= wb_data[7:0];
    end

    // Direct or Stretched LED driving (Direct in step mode sw[0] or 1Hz slow mode sw[1]; stretched in auto mode)
    wire led_hazard = (sw[0] || sw[1]) ? hazard_stall     : (hazard_stretch_cnt > 0);
    wire led_fwd    = (sw[0] || sw[1]) ? fwd_active       : (fwd_stretch_cnt > 0);
    wire led_flush  = (sw[0] || sw[1]) ? hazard_flush_id  : (flush_stretch_cnt > 0);
    wire led_mul    = (sw[0] || sw[1]) ? mul_active       : (mul_stretch_cnt > 0);

    // LED Port Assignments
    assign led[0]    = led_hazard;            // LED[0]: Data Hazard Detected (Load-use stall)
    assign led[1]    = led_fwd;               // LED[1]: Data Forwarding Active into Multiplier
    assign led[2]    = led_flush;             // LED[2]: Branch / Speculative Flush
    assign led[3]    = wb_reg_write;          // LED[3]: Instruction Writeback Commit
    assign led[4]    = led_mul;               // LED[4]: Multiplier Unit Active!
    assign led[5]    = use_dsp_mode;          // LED[5]: DSP Mode Active (ON=DSP48E1, OFF=Booth)
    assign led[6]    = forward_b[0];          // LED[6]: Forward B Bit 0
    assign led[7]    = forward_b[1];          // LED[7]: Forward B Bit 1
    // Show live writeback data during execution (changes to 0x00 on CC=20, 21, 22),
    // and restore the final computation return value (0x2A = 42) when halted.
    assign led[15:8] = prog_done ? final_result_a0 : wb_data[7:0];

endmodule
