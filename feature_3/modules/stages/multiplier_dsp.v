// ============================================================================
// File: multiplier_dsp.v
// Module: multiplier_dsp
// Description: DSP-Accelerated 32-bit Hardware Multiplier for RV32M Extension
// Target: Xilinx Artix-7 XC7A100T (DSP48E1 Slice Architecture)
// Features:
//   - Dedicated (* use_dsp = "yes" *) directive for Artix-7 DSP inference
//   - Handles Signed x Signed (MUL, MULH), Signed x Unsigned (MULHSU),
//     and Unsigned x Unsigned (MULHU) using 33-bit signed extension
//   - Zero-latency single-cycle combinational execution within EX stage
//   - Fits within the strict budget of <= 4 DSP slices
// ============================================================================

`timescale 1ns/1ps

module multiplier_dsp (
    input  wire        signed_a,  // 1 = Operand A is signed, 0 = unsigned
    input  wire        signed_b,  // 1 = Operand B is signed, 0 = unsigned
    input  wire [31:0] op_a,      // 32-bit Multiplicand
    input  wire [31:0] op_b,      // 32-bit Multiplier
    output wire [63:0] product    // 64-bit Full Product
);

    // ------------------------------------------------------------------------
    // 33-Bit Signed Extension
    // ------------------------------------------------------------------------
    // By extending both operands to 33 bits:
    //   - If signed:   ext_a = {op_a[31], op_a}  (2's complement sign-extended)
    //   - If unsigned: ext_a = {1'b0,     op_a}  (treated as non-negative signed)
    // A single 33x33 signed multiplication correctly yields the exact 64-bit
    // product for all four RISC-V signedness combinations!
    // ------------------------------------------------------------------------
    wire signed [32:0] ext_a = signed_a ? {op_a[31], op_a} : {1'b0, op_a};
    wire signed [32:0] ext_b = signed_b ? {op_b[31], op_b} : {1'b0, op_b};

    // ------------------------------------------------------------------------
    // DSP48E1 Inference
    // ------------------------------------------------------------------------
    // Vivado maps 33-bit x 33-bit signed multiplication into a 2x2 cascade of
    // 25x18 DSP48E1 slices on the Artix-7 FPGA (utilizing <= 4 DSP slices).
    // ------------------------------------------------------------------------
    (* use_dsp = "yes" *)
    wire signed [65:0] raw_product;

    assign raw_product = ext_a * ext_b;

    // Truncate to standard 64-bit product
    assign product = raw_product[63:0];

endmodule
