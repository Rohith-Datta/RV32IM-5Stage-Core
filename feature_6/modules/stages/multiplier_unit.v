// ============================================================================
// File: multiplier_unit.v
// Module: multiplier_unit
// Description: Top-Level RV32M Hardware Multiplier Execution Unit
// Project: Pipelined RV32IMF RISC-V Core (Feature 2: Hardware Multiplier)
// Supported Instructions:
//   - MUL    (funct3 = 3'b000) : Signed x Signed, lower 32 bits [31:0]
//   - MULH   (funct3 = 3'b001) : Signed x Signed, upper 32 bits [63:32]
//   - MULHSU (funct3 = 3'b010) : Signed x Unsigned, upper 32 bits [63:32]
//   - MULHU  (funct3 = 3'b011) : Unsigned x Unsigned, upper 32 bits [63:32]
// Architecture Options:
//   - Parameter USE_DSP = 1 (Default): Inferred onto Artix-7 DSP48E1 slices
//   - Runtime selection via use_dsp_sel (switchable on FPGA via sw[3])
// ============================================================================

`timescale 1ns/1ps

module multiplier_unit
#(
    parameter USE_DSP = 1  // 1: Hardware DSP slices (Artix-7), 0: Booth Radix-4
)
(
    input  wire        clk,
    input  wire        reset_n,
    input  wire        is_mul,       // Multiplier operation enable from ID/EX
    input  wire        use_dsp_sel,  // Runtime architecture select (1: DSP, 0: Booth)
    input  wire [2:0]  funct3,       // F3_MUL, F3_MULH, F3_MULHSU, F3_MULHU
    input  wire [31:0] op_a,         // Hazard-forwarded Operand A
    input  wire [31:0] op_b,         // Hazard-forwarded Operand B
    output reg  [31:0] mul_result,   // Formatted 32-bit execution result
    output wire        mul_busy      // 0 for single-cycle execution
);

    // ------------------------------------------------------------------------
    // Signedness Decoding
    // ------------------------------------------------------------------------
    wire signed_a = (funct3 == 3'b011) ? 1'b0 : 1'b1;
    wire signed_b = (funct3 == 3'b010 || funct3 == 3'b011) ? 1'b0 : 1'b1;

    wire [63:0] product_dsp;
    wire [63:0] product_booth;
    wire [63:0] product;

    // ------------------------------------------------------------------------
    // Sub-Module Instantiations
    // ------------------------------------------------------------------------
    multiplier_dsp u_dsp_mult (
        .signed_a (signed_a),
        .signed_b (signed_b),
        .op_a     (op_a),
        .op_b     (op_b),
        .product  (product_dsp)
    );

    booth_radix4_multiplier u_booth_mult (
        .signed_a (signed_a),
        .signed_b (signed_b),
        .op_a     (op_a),
        .op_b     (op_b),
        .product  (product_booth)
    );

    // Dynamic runtime or static parameter selection
    assign product  = (use_dsp_sel) ? product_dsp : product_booth;
    assign mul_busy = 1'b0; // Single-cycle latency in EX stage

    // ------------------------------------------------------------------------
    // Output Formatting Multiplexer
    // ------------------------------------------------------------------------
    always @(*) begin
        case (funct3)
            3'b000:  mul_result = product[31:0];   // MUL:    low 32 bits
            3'b001:  mul_result = product[63:32];  // MULH:   high 32 bits (S x S)
            3'b010:  mul_result = product[63:32];  // MULHSU: high 32 bits (S x U)
            3'b011:  mul_result = product[63:32];  // MULHU:  high 32 bits (U x U)
            default: mul_result = product[31:0];
        endcase
    end

endmodule
