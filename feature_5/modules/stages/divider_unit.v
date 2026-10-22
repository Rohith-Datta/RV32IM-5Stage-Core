// ============================================================================
// File: divider_unit.v
// Description: RV32M Multi-Cycle Hardware Divider & Remainder Unit
// Project: Pipelined RV32IM RISC-V Core (Feature 3: Hardware Divider)
// Supports:
//   - DIV   (Signed Quotient)
//   - DIVU  (Unsigned Quotient)
//   - REM   (Signed Remainder)
//   - REMU  (Unsigned Remainder)
// Compliant with RISC-V Specification Corner Cases:
//   - Divide-by-Zero: DIV/DIVU -> -1 (32'hFFFF_FFFF), REM/REMU -> op_a
//   - Signed Overflow (INT_MIN / -1): DIV -> INT_MIN (32'h8000_0000), REM -> 0
// Execution:
//   - 32-cycle Radix-2 Restoring Divider FSM
//   - Early-out 1-cycle bypass on Divide-by-Zero and Signed Overflow
// ============================================================================

`timescale 1ns/1ps

module divider_unit (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        is_div,        // High when DIV/DIVU/REM/REMU in EX stage
    input  wire [2:0]  funct3,        // Instruction funct3 (DIV/DIVU/REM/REMU)
    input  wire [31:0] op_a,          // Dividend (rs1 forwarded)
    input  wire [31:0] op_b,          // Divisor (rs2 forwarded)
    output wire [31:0] div_result,    // Final computation result
    output wire        div_busy,      // Interlock stall signal to hazard unit
    output wire        div_done       // High when valid result is ready in EX
);

    `include "opcode.vh"

    // FSM States
    localparam [1:0] S_IDLE = 2'b00,
                     S_CALC = 2'b01,
                     S_DONE = 2'b10;

    reg [1:0]  state;
    reg [4:0]  count;
    reg [63:0] rem_quot;
    reg [31:0] divisor;
    reg        neg_quot;
    reg        neg_rem;
    reg [2:0]  saved_funct3;
    reg        early_done;
    reg [31:0] early_result;

    // Corner Case Detections
    wire is_signed_op = (funct3 == F3_DIV) || (funct3 == F3_REM);
    wire is_div_by_zero = (op_b == 32'd0);
    wire is_overflow = is_signed_op && (op_a == 32'h8000_0000) && (op_b == 32'hFFFF_FFFF);

    // Operand Absolute Values and Signs
    wire sign_a = is_signed_op && op_a[31];
    wire sign_b = is_signed_op && op_b[31];
    wire [31:0] abs_a = sign_a ? (-op_a) : op_a;
    wire [31:0] abs_b = sign_b ? (-op_b) : op_b;

    // Shift and Trial Subtraction Logic for 1 Radix-2 Iteration
    wire [31:0] next_rem  = rem_quot[62:31];
    wire [31:0] next_quot = {rem_quot[30:0], 1'b0};
    wire        can_sub   = (next_rem >= divisor);
    wire [31:0] sub_rem   = can_sub ? (next_rem - divisor) : next_rem;
    wire [31:0] step_quot = can_sub ? {next_quot[31:1], 1'b1} : next_quot;

    // FSM State Machine
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state        <= S_IDLE;
            count        <= 5'd0;
            rem_quot     <= 64'd0;
            divisor      <= 32'd0;
            neg_quot     <= 1'b0;
            neg_rem      <= 1'b0;
            saved_funct3 <= 3'b000;
            early_done   <= 1'b0;
            early_result <= 32'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (is_div) begin
                        saved_funct3 <= funct3;
                        if (is_div_by_zero) begin
                            // Divide by zero corner case:
                            // DIV/DIVU -> 32'hFFFF_FFFF, REM/REMU -> op_a
                            early_done   <= 1'b1;
                            early_result <= funct3[1] ? op_a : 32'hFFFF_FFFF;
                            state        <= S_DONE;
                        end else if (is_overflow) begin
                            // Signed overflow corner case (INT_MIN / -1):
                            // DIV -> 32'h8000_0000 (INT_MIN), REM -> 0
                            early_done   <= 1'b1;
                            early_result <= funct3[1] ? 32'h0000_0000 : 32'h8000_0000;
                            state        <= S_DONE;
                        end else begin
                            // Standard 32-cycle Radix-2 Restoring Division
                            early_done   <= 1'b0;
                            neg_quot     <= is_signed_op && (sign_a ^ sign_b);
                            neg_rem      <= is_signed_op && sign_a;
                            divisor      <= abs_b;
                            rem_quot     <= {32'd0, abs_a};
                            count        <= 5'd31;
                            state        <= S_CALC;
                        end
                    end
                end

                S_CALC: begin
                    rem_quot <= {sub_rem, step_quot};
                    if (count == 5'd0) begin
                        state <= S_DONE;
                    end else begin
                        count <= count - 5'd1;
                    end
                end

                S_DONE: begin
                    // Done cycle: result is valid, pipeline captures result, return to IDLE
                    state      <= S_IDLE;
                    early_done <= 1'b0;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // Result Formation and Sign Adjustment
    wire [31:0] raw_quot = rem_quot[31:0];
    wire [31:0] raw_rem  = rem_quot[63:32];

    wire [31:0] adj_quot = neg_quot ? (-raw_quot) : raw_quot;
    wire [31:0] adj_rem  = neg_rem  ? (-raw_rem)  : raw_rem;

    wire [31:0] calculated_result = saved_funct3[1] ? adj_rem : adj_quot;

    assign div_result = early_done ? early_result : calculated_result;
    assign div_busy   = is_div && (state != S_DONE);
    assign div_done   = is_div && (state == S_DONE);

endmodule
