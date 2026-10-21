// ============================================================================
// File: booth_radix4_multiplier.v
// Module: booth_radix4_multiplier
// Description: Pure Radix-4 Modified Booth Multiplier RTL Architecture
// Features:
//   - Radix-4 Booth Recoding (halves partial product count from 34 to 17)
//   - Supports Signed x Signed, Signed x Unsigned, and Unsigned x Unsigned
//   - Dynamic 3-bit sliding window encoding {-2, -1, 0, +1, +2}
//   - Two's complement inversion and carry compensation for negative multiples
//   - Algorithmic alternative to dedicated DSP hard-macros
// ============================================================================

`timescale 1ns/1ps

module booth_radix4_multiplier (
    input  wire        signed_a,  // 1 = Operand A signed, 0 = unsigned
    input  wire        signed_b,  // 1 = Operand B signed, 0 = unsigned
    input  wire [31:0] op_a,      // 32-bit Multiplicand (X)
    input  wire [31:0] op_b,      // 32-bit Multiplier   (Y)
    output wire [63:0] product    // 64-bit Full Product
);

    // ------------------------------------------------------------------------
    // Sign Extension to 34 bits (even bit count for 17 radix-4 groups)
    // ------------------------------------------------------------------------
    wire signed [33:0] ext_x = signed_a ? {{2{op_a[31]}}, op_a} : {2'b00, op_a};
    wire signed [33:0] ext_y = signed_b ? {{2{op_b[31]}}, op_b} : {2'b00, op_b};

    // Multiplier augmented with y[-1] = 0 (35 bits total: bits [34:0])
    wire [34:0] y_aug = {ext_y, 1'b0};

    // ------------------------------------------------------------------------
    // Radix-4 Booth Recoding & Partial Product Generation (17 slices)
    // ------------------------------------------------------------------------
    reg signed [67:0] pp [0:16];
    integer i;

    always @(*) begin
        for (i = 0; i < 17; i = i + 1) begin
            case (y_aug[2*i +: 3])
                3'b000, 3'b111: begin
                    // Multiplier factor = 0
                    pp[i] = 68'sd0;
                end
                3'b001, 3'b010: begin
                    // Multiplier factor = +1 * X
                    pp[i] = $signed({{34{ext_x[33]}}, ext_x}) <<< (2 * i);
                end
                3'b011: begin
                    // Multiplier factor = +2 * X
                    pp[i] = $signed({{33{ext_x[33]}}, ext_x, 1'b0}) <<< (2 * i);
                end
                3'b100: begin
                    // Multiplier factor = -2 * X
                    pp[i] = $signed(-{{33{ext_x[33]}}, ext_x, 1'b0}) <<< (2 * i);
                end
                3'b101, 3'b110: begin
                    // Multiplier factor = -1 * X
                    pp[i] = $signed(-{{34{ext_x[33]}}, ext_x}) <<< (2 * i);
                end
                default: begin
                    pp[i] = 68'sd0;
                end
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // Sum of Partial Products
    // ------------------------------------------------------------------------
    wire signed [67:0] sum_pp = pp[0]  + pp[1]  + pp[2]  + pp[3]  +
                                pp[4]  + pp[5]  + pp[6]  + pp[7]  +
                                pp[8]  + pp[9]  + pp[10] + pp[11] +
                                pp[12] + pp[13] + pp[14] + pp[15] + pp[16];

    assign product = sum_pp[63:0];

endmodule
