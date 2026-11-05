// ============================================================================
// File: alu_zbb.v
// Module: alu_zbb
// Description: Integrated RV32I Arithmetic Logic Unit (ALU) + Full Zbb Extension
//              All 18 Zbb bit-manipulation operations execute in 1 clock cycle
//              with 0 pipeline stall cycles, sharing the execution datapath.
// ============================================================================

`timescale 1ns/1ps

module alu_zbb (
    input  wire [31:0] alu_in1,
    input  wire [31:0] alu_in2,
    input  wire [31:0] imm_i,
    input  wire [2:0]  alu_op_i,
    input  wire        arithsubtype_i,
    input  wire        immediate_sel_i,
    input  wire [6:0]  funct7_i,
    output reg  [31:0] alu_result_o
);

    `include "opcode.vh"

    // Subtractions for signed & unsigned comparisons
    wire [32:0] sub_signed   = {alu_in1[31], alu_in1} - {alu_in2[31], alu_in2};
    wire [32:0] sub_unsigned = {1'b0, alu_in1} - {1'b0, alu_in2};

    // ------------------------------------------------------------------------
    // Zbb Combinational Processing Blocks
    // ------------------------------------------------------------------------
    // 1. Bitwise Rotations (ROL, ROR, RORI)
    wire [63:0] rol_double  = {alu_in1, alu_in1};
    wire [63:0] rol_shifted = rol_double << alu_in2[4:0];
    wire [31:0] rol_result  = rol_shifted[63:32];

    wire [63:0] ror_double  = {alu_in1, alu_in1};
    wire [63:0] ror_shifted = ror_double >> alu_in2[4:0];
    wire [31:0] ror_result  = ror_shifted[31:0];

    // Resolve signed shift before the unsigned result-selection expression.
    // A mixed-signedness ternary can otherwise turn >>> into zero filling.
    wire [31:0] arithmetic_shift_result = $signed(alu_in1) >>> alu_in2[4:0];

    // 2. Byte Reverse (REV8)
    wire [31:0] rev8_result = {alu_in1[7:0], alu_in1[15:8], alu_in1[23:16], alu_in1[31:24]};

    // 3. OR Combine (ORC.B)
    wire [31:0] orc_b_result = {
        (|alu_in1[31:24]) ? 8'hFF : 8'h00,
        (|alu_in1[23:16]) ? 8'hFF : 8'h00,
        (|alu_in1[15:8])  ? 8'hFF : 8'h00,
        (|alu_in1[7:0])   ? 8'hFF : 8'h00
    };

    // 4. Count Leading Zeros (CLZ)
    function [31:0] count_leading_zeros;
        input [31:0] val;
        integer k;
        reg found;
        begin
            count_leading_zeros = 32'd32;
            found = 1'b0;
            for (k = 31; k >= 0; k = k - 1) begin
                if (!found && val[k]) begin
                    count_leading_zeros = 32'd31 - k;
                    found = 1'b1;
                end
            end
        end
    endfunction

    // 5. Count Trailing Zeros (CTZ)
    function [31:0] count_trailing_zeros;
        input [31:0] val;
        integer k;
        reg found;
        begin
            count_trailing_zeros = 32'd32;
            found = 1'b0;
            for (k = 0; k < 32; k = k + 1) begin
                if (!found && val[k]) begin
                    count_trailing_zeros = k;
                    found = 1'b1;
                end
            end
        end
    endfunction

    // 6. Population Count (CPOP)
    function [31:0] count_ones;
        input [31:0] val;
        integer k;
        reg [5:0] cnt;
        begin
            cnt = 6'd0;
            for (k = 0; k < 32; k = k + 1) begin
                cnt = cnt + val[k];
            end
            count_ones = {26'd0, cnt};
        end
    endfunction

    // ------------------------------------------------------------------------
    // Unified ALU Multiplexer
    // ------------------------------------------------------------------------
    always @(*) begin
        case (alu_op_i)
            ADD: begin
                // In R-type, arithsubtype_i selects SUB. In I-type (ADDI), always ADD.
                alu_result_o = (arithsubtype_i && !immediate_sel_i) ? (alu_in1 - alu_in2) : (alu_in1 + alu_in2);
            end

            SLL: begin
                if (immediate_sel_i && (imm_i[11:0] == IMM12_CLZ)) begin
                    alu_result_o = count_leading_zeros(alu_in1);
                end else if (immediate_sel_i && (imm_i[11:0] == IMM12_CTZ)) begin
                    alu_result_o = count_trailing_zeros(alu_in1);
                end else if (immediate_sel_i && (imm_i[11:0] == IMM12_CPOP)) begin
                    alu_result_o = count_ones(alu_in1);
                end else if (immediate_sel_i && (imm_i[11:0] == IMM12_SEXTB)) begin
                    alu_result_o = {{24{alu_in1[7]}}, alu_in1[7:0]};
                end else if (immediate_sel_i && (imm_i[11:0] == IMM12_SEXTH)) begin
                    alu_result_o = {{16{alu_in1[15]}}, alu_in1[15:0]};
                end else if (!immediate_sel_i && (funct7_i == FUNCT7_ZBB_ROT)) begin
                    alu_result_o = rol_result;
                end else begin
                    alu_result_o = alu_in1 << alu_in2[4:0];
                end
            end

            SLT: begin
                alu_result_o = {31'b0, sub_signed[32]};
            end

            SLTU: begin
                alu_result_o = {31'b0, sub_unsigned[32]};
            end

            XOR: begin
                if (!immediate_sel_i && (funct7_i == FUNCT7_ZBB_LOGIC)) begin
                    alu_result_o = ~(alu_in1 ^ alu_in2); // XNOR
                end else if (!immediate_sel_i && (funct7_i == FUNCT7_ZBB_MINMAX)) begin
                    alu_result_o = sub_signed[32] ? alu_in1 : alu_in2; // MIN
                end else if (!immediate_sel_i && (funct7_i == FUNCT7_ZBB_PACK)) begin
                    alu_result_o = {16'h0000, alu_in1[15:0]}; // ZEXT.H
                end else begin
                    alu_result_o = alu_in1 ^ alu_in2;
                end
            end

            SR: begin
                if (immediate_sel_i && (imm_i[11:0] == IMM12_REV8)) begin
                    alu_result_o = rev8_result;
                end else if (immediate_sel_i && (imm_i[11:0] == IMM12_ORCB)) begin
                    alu_result_o = orc_b_result;
                end else if (funct7_i == FUNCT7_ZBB_ROT) begin
                    alu_result_o = ror_result; // ROR or RORI
                end else if (!immediate_sel_i && (funct7_i == FUNCT7_ZBB_MINMAX)) begin
                    alu_result_o = sub_unsigned[32] ? alu_in1 : alu_in2; // MINU
                end else begin
                    alu_result_o = arithsubtype_i ? arithmetic_shift_result : (alu_in1 >> alu_in2[4:0]);
                end
            end

            OR: begin
                if (!immediate_sel_i && (funct7_i == FUNCT7_ZBB_LOGIC)) begin
                    alu_result_o = alu_in1 | (~alu_in2); // ORN
                end else if (!immediate_sel_i && (funct7_i == FUNCT7_ZBB_MINMAX)) begin
                    alu_result_o = sub_signed[32] ? alu_in2 : alu_in1; // MAX
                end else begin
                    alu_result_o = alu_in1 | alu_in2;
                end
            end

            AND: begin
                if (!immediate_sel_i && (funct7_i == FUNCT7_ZBB_LOGIC)) begin
                    alu_result_o = alu_in1 & (~alu_in2); // ANDN
                end else if (!immediate_sel_i && (funct7_i == FUNCT7_ZBB_MINMAX)) begin
                    alu_result_o = sub_unsigned[32] ? alu_in2 : alu_in1; // MAXU
                end else begin
                    alu_result_o = alu_in1 & alu_in2;
                end
            end

            default: alu_result_o = 32'h0;
        endcase
    end

endmodule
