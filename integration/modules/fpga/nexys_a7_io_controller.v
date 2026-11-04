// ============================================================================
// File: nexys_a7_io_controller.v
// Module: nexys_a7_io_controller
// Description: Complete Synthesizable Nexys A7 Display & LED Controller Module
// Target Device: Digilent Nexys A7-100T (Artix-7 XC7A100T-1CSG324C)
// Drives:
//   - 8-digit multiplexed Seven-Segment Display (Live 32-bit PC or WB Data)
//   - 16 Status LEDs with 20ms pulse-stretchers for 1-cycle pipeline events
// ============================================================================

`timescale 1ns / 1ps

module nexys_a7_io_controller (
    input  wire        clk_40mhz,
    input  wire        rst_n,
    // Pipeline & Architectural Snoop Signals
    input  wire [31:0] current_pc,
    input  wire [31:0] wb_write_data,
    input  wire        sw_show_wb_on_seg7, // SW[10]: 0 = Show PC, 1 = Show WB Data
    input  wire        pipeline_stall,
    input  wire        load_use_hazard,
    input  wire        dcache_miss_busy,
    input  wire        icache_miss_busy,
    input  wire        btb_mispredict_flush,
    input  wire        fpu_busy,
    input  wire        muldiv_busy,
    input  wire        wb_reg_commit,
    input  wire        fpu_exc_nv,
    input  wire        fpu_exc_dz,
    input  wire        fpu_exc_of,
    input  wire        fpu_exc_uf,
    input  wire        fpu_exc_nx,
    input  wire        zbb_active,
    input  wire        uart_tx_active,
    input  wire        demo_complete,
    // Physical Nexys A7 Outputs
    output wire [15:0] led,
    output reg  [7:0]  an,
    output reg  [6:0]  seg,
    output reg         dp
);

    // -------------------------------------------------------------------------
    // 1. Pulse Stretcher for 1-Cycle Pipeline Events (2,000,000 cycles = 20ms at 100MHz)
    // Ensures single-cycle hazards, flushes, and Zbb ops are visible on LEDs
    // -------------------------------------------------------------------------
    wire [13:0] raw_events = {
        pipeline_stall,       // [13] -> LED[15]
        load_use_hazard,      // [12] -> LED[14]
        dcache_miss_busy,     // [11] -> LED[13]
        icache_miss_busy,     // [10] -> LED[12]
        btb_mispredict_flush, // [9]  -> LED[11]
        fpu_busy,             // [8]  -> LED[10]
        muldiv_busy,          // [7]  -> LED[9]
        wb_reg_commit,        // [6]  -> LED[8]
        fpu_exc_nv,           // [5]  -> LED[7]
        fpu_exc_dz,           // [4]  -> LED[6]
        fpu_exc_of,           // [3]  -> LED[5]
        fpu_exc_uf,           // [2]  -> LED[4]
        fpu_exc_nx,           // [1]  -> LED[3]
        zbb_active            // [0]  -> LED[2]
    };

    // Stage 1 Input Register: Isolates CPU pipeline events from 21-bit counter timing
    reg [13:0] raw_events_q;
    reg [20:0] stretch_cnt [0:13];
    reg [13:0] stretched_leds;
    integer i;

    always @(posedge clk_40mhz or negedge rst_n) begin
        if (!rst_n) begin
            raw_events_q   <= 14'b0;
            stretched_leds <= 14'b0;
            for (i = 0; i < 14; i = i + 1) stretch_cnt[i] <= 21'd0;
        end else begin
            raw_events_q <= raw_events;
            for (i = 0; i < 14; i = i + 1) begin
                if (raw_events_q[i]) begin
                    stretched_leds[i] <= 1'b1;
                    stretch_cnt[i]    <= 21'd800000; // 20 ms hold at 40MHz
                end else if (stretch_cnt[i] > 21'd0) begin
                    stretch_cnt[i]    <= stretch_cnt[i] - 1'b1;
                    stretched_leds[i] <= 1'b1;
                end else begin
                    stretched_leds[i] <= 1'b0;
                end
            end
        end
    end

    assign led[15:2] = stretched_leds;
    assign led[1]    = uart_tx_active;
    assign led[0]    = demo_complete;

    // -------------------------------------------------------------------------
    // 2. 8-Digit 7-Segment Display Controller (32-bit Hex PC / WB Data)
    // -------------------------------------------------------------------------
    reg [19:0] refresh_counter;
    always @(posedge clk_40mhz or negedge rst_n) begin
        if (!rst_n) refresh_counter <= 20'd0;
        else        refresh_counter <= refresh_counter + 1'b1;
    end

    wire [2:0]  digit_sel   = refresh_counter[18:16]; // ~610 Hz refresh per digit at 40MHz
    reg  [31:0] display_val;
    always @(posedge clk_40mhz or negedge rst_n) begin
        if (!rst_n) display_val <= 32'd0;
        else        display_val <= sw_show_wb_on_seg7 ? wb_write_data : current_pc;
    end
    reg  [3:0]  hex_nibble;

    always @(*) begin
        an = 8'b1111_1111;
        an[digit_sel] = 1'b0; // Active-low anode enable
        case (digit_sel)
            3'd0: begin hex_nibble = display_val[3:0];   dp = ~wb_reg_commit;  end
            3'd1: begin hex_nibble = display_val[7:4];   dp = 1'b1;            end
            3'd2: begin hex_nibble = display_val[11:8];  dp = 1'b1;            end
            3'd3: begin hex_nibble = display_val[15:12]; dp = 1'b1;            end
            3'd4: begin hex_nibble = display_val[19:16]; dp = 1'b1;            end
            3'd5: begin hex_nibble = display_val[23:20]; dp = 1'b1;            end
            3'd6: begin hex_nibble = display_val[27:24]; dp = 1'b1;            end
            3'd7: begin hex_nibble = display_val[31:28]; dp = ~pipeline_stall; end
        endcase
    end

    // Active-low Cathodes: {CG, CF, CE, CD, CC, CB, CA}
    always @(*) begin
        case (hex_nibble)
            4'h0: seg = 7'b1000000;
            4'h1: seg = 7'b1111001;
            4'h2: seg = 7'b0100100;
            4'h3: seg = 7'b0110000;
            4'h4: seg = 7'b0011001;
            4'h5: seg = 7'b0010010;
            4'h6: seg = 7'b0000010;
            4'h7: seg = 7'b1111000;
            4'h8: seg = 7'b0000000;
            4'h9: seg = 7'b0010000;
            4'hA: seg = 7'b0001000;
            4'hB: seg = 7'b0000011;
            4'hC: seg = 7'b1000110;
            4'hD: seg = 7'b0100001;
            4'hE: seg = 7'b0000110;
            4'hF: seg = 7'b0001110;
            default: seg = 7'b1111111;
        endcase
    end

endmodule
