// ============================================================================
// File: seven_seg_controller.v
// Description: 8-Digit Seven-Segment Display Controller for Digilent Nexys A7
// Target: Artix-7 XC7A100T FPGA
// Purpose: Displays the 32-bit Fetch PC Address (pc_if[31:0]) on the 8 seven-segment
//          display digits located directly above the user LEDs.
// ============================================================================

`timescale 1ns/1ps

module seven_seg_controller (
    input  wire        clk,        // 100 MHz board clock
    input  wire        reset_n,    // Active-low synchronous reset
    input  wire [31:0] data_in,    // 32-bit value to display (Fetch PC: pc_if[31:0])
    input  wire        show_dashes,// 1: Show "--------" across all 8 digits when halted
    output reg  [7:0]  an,         // Active-low digit anodes (AN7 down to AN0)
    output reg  [6:0]  seg,        // Active-low segment cathodes: {cg, cf, ce, cd, cc, cb, ca}
    output wire        dp          // Active-low decimal point
);

    // ------------------------------------------------------------------------
    // Refresh Counter (17 bits)
    // 100 MHz / 2^17 = 762.9 Hz total scan rate (~95 Hz per digit refresh)
    // Flicker-free display for human vision.
    // ------------------------------------------------------------------------
    reg [16:0] refresh_counter;
    wire [2:0] active_digit = refresh_counter[16:14];

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            refresh_counter <= 17'd0;
        else
            refresh_counter <= refresh_counter + 17'd1;
    end

    // ------------------------------------------------------------------------
    // Digit Multiplexer & Nibble Extractor
    // Digit 0 (rightmost) displays data_in[3:0]
    // Digit 7 (leftmost) displays data_in[31:28]
    // ------------------------------------------------------------------------
    reg [3:0] hex_digit;

    always @(*) begin
        case (active_digit)
            3'd0: begin
                an        = 8'b1111_1110; // Digit 0 (Rightmost)
                hex_digit = data_in[3:0];
            end
            3'd1: begin
                an        = 8'b1111_1101; // Digit 1
                hex_digit = data_in[7:4];
            end
            3'd2: begin
                an        = 8'b1111_1011; // Digit 2
                hex_digit = data_in[11:8];
            end
            3'd3: begin
                an        = 8'b1111_0111; // Digit 3
                hex_digit = data_in[15:12];
            end
            3'd4: begin
                an        = 8'b1110_1111; // Digit 4
                hex_digit = data_in[19:16];
            end
            3'd5: begin
                an        = 8'b1101_1111; // Digit 5
                hex_digit = data_in[23:20];
            end
            3'd6: begin
                an        = 8'b1011_1111; // Digit 6
                hex_digit = data_in[27:24];
            end
            3'd7: begin
                an        = 8'b0111_1111; // Digit 7 (Leftmost)
                hex_digit = data_in[31:28];
            end
            default: begin
                an        = 8'b1111_1111;
                hex_digit = 4'h0;
            end
        endcase
    end

    // ------------------------------------------------------------------------
    // Hex-to-Seven-Segment Active-Low Decoder
    // Mapping: seg[0]=CA, seg[1]=CB, seg[2]=CC, seg[3]=CD, seg[4]=CE, seg[5]=CF, seg[6]=CG
    // When show_dashes is 1, lights up segment G alone (middle horizontal bar '-')
    // ------------------------------------------------------------------------
    always @(*) begin
        if (show_dashes) begin
            seg = 7'b011_1111; // Dash '-' (CG active, CA..CF inactive)
        end else begin
            case (hex_digit)
                4'h0: seg = 7'b100_0000; // '0'
                4'h1: seg = 7'b111_1001; // '1'
                4'h2: seg = 7'b010_0100; // '2'
                4'h3: seg = 7'b011_0000; // '3'
                4'h4: seg = 7'b001_1001; // '4'
                4'h5: seg = 7'b001_0010; // '5'
                4'h6: seg = 7'b000_0010; // '6'
                4'h7: seg = 7'b111_1000; // '7'
                4'h8: seg = 7'b000_0000; // '8'
                4'h9: seg = 7'b001_0000; // '9'
                4'hA: seg = 7'b000_1000; // 'A'
                4'hB: seg = 7'b000_0011; // 'b'
                4'hC: seg = 7'b100_0110; // 'C'
                4'hD: seg = 7'b010_0001; // 'd'
                4'hE: seg = 7'b000_0110; // 'E'
                4'hF: seg = 7'b000_1110; // 'F'
                default: seg = 7'b111_1111; // Off
            endcase
        end
    end

    // Turn on decimal point on digit 4 as a visual separator between upper and lower halfwords
    // When showing dashes, turn decimal point off
    assign dp = (show_dashes) ? 1'b1 : ((active_digit == 3'd4) ? 1'b0 : 1'b1);

endmodule
