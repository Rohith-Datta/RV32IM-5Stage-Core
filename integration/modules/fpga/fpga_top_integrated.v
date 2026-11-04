// ============================================================================
// File: fpga_top_integrated.v
// Module: fpga_top_integrated
// Description: Synthesizable FPGA Top-Level SoC Module for Full-System
//              RV32IMF + Zbb + BTB + Caches + CSR Integrated Processor
// Target Device: Digilent Nexys A7-100T (Xilinx Artix-7 XC7A100T-1CSG324C)
//
// Hardware Features & I/O:
//   - Onboard Oscillator: 100 MHz (Pin E3) -> 50 MHz Core Clock
//   - 8-Digit Seven-Segment Multiplexed Display (Hex PC or WB Data via SW[10])
//   - 16 Discrete LEDs with 20ms pulse-stretchers for pipeline hazard observability
//   - 16 Slide Switches (Mode, Cache Enable, Verbose, Slow Mode, Seed/Fault)
//   - USB-UART FTDI Serial Interface (115200 Baud, 8N1)
// ============================================================================

`timescale 1ns/1ps

module fpga_top_integrated #(
    parameter CLK_FREQ   = 40_000_000,
    parameter BAUD_RATE  = 115_200,
    parameter RAM_WORDS  = 16384, // 64 KB Unified RAM (16K x 32-bit words)
    parameter HEX_FILE   = "avionics_demo.hex"
)(
    input  wire        clk_100mhz,  // 100 MHz onboard oscillator (Pin E3)
    input  wire        cpu_resetn,  // Active-low CPU reset push button (Pin C12)
    input  wire        btnc,        // Center push button: manual trigger
    input  wire [15:0] sw,          // 16 slide switches
    output wire [7:0]  an,          // 8-digit Seven-Segment Anodes (Pins J17..U13)
    output wire [6:0]  seg,         // 7-segment Cathodes (Pins T10..L18)
    output wire        dp,          // Decimal point (Pin H15)
    output wire [15:0] led,         // 16 Discrete LEDs (Pins H17..V11)
    output wire        uart_tx,     // UART TX pin (Pin D4 -> FTDI USB-UART)
    input  wire        uart_rx      // UART RX pin (Pin C4 <- FTDI USB-UART)
);

    // ------------------------------------------------------------------------
    // 1. Clock Generation: 40 MHz Derived Core Clock
    // ------------------------------------------------------------------------
`ifdef SIMULATION
    reg clk_40mhz_sim = 1'b0;
    initial begin
        clk_40mhz_sim = 1'b0;
        forever #12.5 clk_40mhz_sim = ~clk_40mhz_sim;
    end
    wire clk_40mhz = clk_40mhz_sim;
    wire mmcm_locked = 1'b1;
`else
    wire clk_40mhz_unbuf;
    wire clkfb;
    wire mmcm_locked;

    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT_F    (10.000),      // VCO = 100 MHz * 10 = 1000 MHz (Valid: 600 - 1200 MHz)
        .CLKFBOUT_PHASE     (0.0),
        .CLKIN1_PERIOD      (10.000),      // 100 MHz onboard oscillator (10.000 ns)
        .CLKOUT0_DIVIDE_F   (25.000),      // 1000 MHz / 25 = 40.000 MHz (25.000 ns period)
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT0_PHASE      (0.0),
        .DIVCLK_DIVIDE      (1),
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE")
    ) u_mmcm_clk40 (
        .CLKOUT0            (clk_40mhz_unbuf),
        .CLKOUT0B           (),
        .CLKOUT1            (),
        .CLKOUT1B           (),
        .CLKOUT2            (),
        .CLKOUT2B           (),
        .CLKOUT3            (),
        .CLKOUT3B           (),
        .CLKOUT4            (),
        .CLKOUT5            (),
        .CLKOUT6            (),
        .CLKFBOUT           (clkfb),
        .CLKFBOUTB          (),
        .LOCKED             (mmcm_locked),
        .CLKIN1             (clk_100mhz),
        .PWRDWN             (1'b0),
        .RST                (~cpu_resetn),
        .CLKFBIN            (clkfb)
    );

    wire clk_40mhz;
    BUFG u_bufg_clk40 (
        .I (clk_40mhz_unbuf),
        .O (clk_40mhz)
    );
`endif

    // ------------------------------------------------------------------------
    // 2. Synchronous Reset De-assertion in 40 MHz Domain
    // ------------------------------------------------------------------------
    reg [2:0] rst_sync;
    always @(posedge clk_40mhz or negedge cpu_resetn) begin
        if (!cpu_resetn)
            rst_sync <= 3'b000;
        else if (mmcm_locked)
            rst_sync <= {rst_sync[1:0], 1'b1};
    end
    wire sys_reset_n = rst_sync[2];

    // ------------------------------------------------------------------------
    // 3. Execution Clock Throttle (SW[11] Slow Mode)
    // ------------------------------------------------------------------------
    // When SW[11] is ON, generate a 10 Hz step pulse to freeze the pipeline via stall_ext
    reg [22:0] slow_cnt;
    wire slow_mode = sw[11];
    wire step_pulse = (slow_cnt == 23'd4_000_000);

    always @(posedge clk_40mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            slow_cnt <= 23'd0;
        end else if (slow_mode) begin
            if (step_pulse)
                slow_cnt <= 23'd0;
            else
                slow_cnt <= slow_cnt + 23'd1;
        end else begin
            slow_cnt <= 23'd0;
        end
    end

    wire core_stall_ext = slow_mode ? !step_pulse : 1'b0;

    // ------------------------------------------------------------------------
    // 4. Unified Main Memory (64 KB Block RAM initialized with firmware)
    // ------------------------------------------------------------------------
    wire        main_mem_req;
    wire [31:0] main_mem_addr;
    wire        main_mem_we;
    wire [31:0] main_mem_wdata;
    wire [3:0]  main_mem_wstrb;
    reg  [31:0] main_mem_rdata;

    (* ram_style = "block" *) reg [31:0] ram [0:RAM_WORDS-1];
    wire [13:0] word_idx = main_mem_addr[15:2];

    initial begin
        $readmemh(HEX_FILE, ram);
    end

    always @(posedge clk_40mhz) begin
        if (main_mem_req) begin
            if (main_mem_we) begin
                if (main_mem_wstrb[0]) ram[word_idx][7:0]   <= main_mem_wdata[7:0];
                if (main_mem_wstrb[1]) ram[word_idx][15:8]  <= main_mem_wdata[15:8];
                if (main_mem_wstrb[2]) ram[word_idx][23:16] <= main_mem_wdata[23:16];
                if (main_mem_wstrb[3]) ram[word_idx][31:24] <= main_mem_wdata[31:24];
            end
            main_mem_rdata <= ram[word_idx];
        end else begin
            main_mem_rdata <= ram[word_idx];
        end
    end

    // ------------------------------------------------------------------------
    // 5. Hardware UART Serial Transmitter (115200 Baud, 8N1)
    // ------------------------------------------------------------------------
    wire       uart_tx_busy;
    wire       uart_tx_start;
    wire [7:0] uart_tx_data;

    uart_tx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart_tx (
        .clk       (clk_40mhz),
        .reset_n   (sys_reset_n),
        .tx_start  (uart_tx_start),
        .tx_data   (uart_tx_data),
        .tx        (uart_tx),
        .tx_busy   (uart_tx_busy)
    );

    // ------------------------------------------------------------------------
    // 6. Integrated RV32IMF Processor Core
    // ------------------------------------------------------------------------
    wire [31:0] pc_if, pc_id, pc_ex, pc_mem, pc_wb;
    wire        wb_reg_write;
    wire [4:0]  wb_dest_reg;
    wire [31:0] wb_data;

    wire        hazard_stall;
    wire        load_use_hazard;
    wire        dcache_miss_busy;
    wire        icache_miss_busy;
    wire        btb_mispredict_flush;
    wire        fpu_busy;
    wire        muldiv_busy;
    wire        wb_reg_commit;
    wire        fpu_exc_nv;
    wire        fpu_exc_dz;
    wire        fpu_exc_of;
    wire        fpu_exc_uf;
    wire        fpu_exc_nx;
    wire        zbb_active;

    wire [31:0] seg7_override;
    wire        demo_complete;

    // Cache enable switch: SW[13]=1 -> active (bypass=0), SW[13]=0 -> bypass=1
    wire cache_bypass = ~sw[13];

    rv32imf_core #(
        .RESET_PC (32'h0000_0000)
    ) u_core (
        .clk                    (clk_40mhz),
        .reset_n                (sys_reset_n),
        .stall_ext              (core_stall_ext),
        .use_dsp_i              (1'b1),
        .icache_bypass_i        (cache_bypass),
        .dcache_bypass_i        (cache_bypass),
        .main_mem_req           (main_mem_req),
        .main_mem_addr          (main_mem_addr),
        .main_mem_we            (main_mem_we),
        .main_mem_wdata         (main_mem_wdata),
        .main_mem_wstrb         (main_mem_wstrb),
        .main_mem_rdata         (main_mem_rdata),
        .pc_if                  (pc_if),
        .pc_id                  (pc_id),
        .pc_ex                  (pc_ex),
        .pc_mem                 (pc_mem),
        .pc_wb                  (pc_wb),
        .wb_reg_write           (wb_reg_write),
        .wb_dest_reg            (wb_dest_reg),
        .wb_data                (wb_data),
        .hazard_stall           (hazard_stall),
        .btb_pred_hit           (),
        .btb_pred_taken         (),
        .btb_mispredict         (),
        .icache_hit             (),
        .icache_miss            (),
        .dcache_hit             (),
        .dcache_miss            (),
        .div_busy               (),
        .fpu_busy               (fpu_busy),
        .cycle_count_o          (),
        .instret_count_o        (),
        .stall_count_o          (),
        .branch_count_o         (),
        .mispredict_count_o     (),

        // MMIO Interface
        .sw_i                   (sw),
        .uart_tx_busy_i         (uart_tx_busy),
        .uart_tx_start_o        (uart_tx_start),
        .uart_tx_data_o         (uart_tx_data),
        .seg7_override_o        (seg7_override),
        .demo_complete_o        (demo_complete),

        // Snoop Indicators
        .load_use_hazard_o      (load_use_hazard),
        .dcache_miss_busy_o     (dcache_miss_busy),
        .icache_miss_busy_o     (icache_miss_busy),
        .btb_mispredict_flush_o (btb_mispredict_flush),
        .muldiv_busy_o          (muldiv_busy),
        .wb_reg_commit_o        (wb_reg_commit),
        .fpu_exc_nv_o           (fpu_exc_nv),
        .fpu_exc_dz_o           (fpu_exc_dz),
        .fpu_exc_of_o           (fpu_exc_of),
        .fpu_exc_uf_o           (fpu_exc_uf),
        .fpu_exc_nx_o           (fpu_exc_nx),
        .zbb_active_o           (zbb_active)
    );

    // ------------------------------------------------------------------------
    // 7. Nexys A7 8-Digit 7-Segment Display & 16-LED Controller
    // ------------------------------------------------------------------------
    nexys_a7_io_controller u_io_ctrl (
        .clk_40mhz              (clk_40mhz),
        .rst_n                  (sys_reset_n),
        .current_pc             (pc_wb),
        .wb_write_data          (wb_data),
        .sw_show_wb_on_seg7     (sw[10]),
        .pipeline_stall         (hazard_stall),
        .load_use_hazard        (load_use_hazard),
        .dcache_miss_busy       (dcache_miss_busy),
        .icache_miss_busy       (icache_miss_busy),
        .btb_mispredict_flush   (btb_mispredict_flush),
        .fpu_busy               (fpu_busy),
        .muldiv_busy            (muldiv_busy),
        .wb_reg_commit          (wb_reg_commit),
        .fpu_exc_nv             (fpu_exc_nv),
        .fpu_exc_dz             (fpu_exc_dz),
        .fpu_exc_of             (fpu_exc_of),
        .fpu_exc_uf             (fpu_exc_uf),
        .fpu_exc_nx             (fpu_exc_nx),
        .zbb_active             (zbb_active),
        .uart_tx_active         (uart_tx_busy),
        .demo_complete          (demo_complete),
        .led                    (led),
        .an                     (an),
        .seg                    (seg),
        .dp                     (dp)
    );

endmodule
