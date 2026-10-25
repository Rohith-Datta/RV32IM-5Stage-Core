// ============================================================================
// File: divider_unit.v
// Description: RV32M 32-Cycle Multi-Cycle Hardware Divider & Remainder Unit
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
//   - Exactly 32 clock cycles latency in EX stage for standard division
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
                     S_CALC = 2'b01;

    reg [1:0]  state;
    reg [4:0]  count;
    reg [63:0] rem_quot;
    reg [31:0] divisor;
    reg        neg_quot;
    reg        neg_rem;
    reg [2:0]  saved_funct3;

    // Corner Case Detections
    wire is_signed_op   = (funct3 == F3_DIV) || (funct3 == F3_REM);
    wire is_div_by_zero = (op_b == 32'd0);
    wire is_overflow    = is_signed_op && (op_a == 32'h8000_0000) && (op_b == 32'hFFFF_FFFF);
    wire is_corner_case = is_div && (is_div_by_zero || is_overflow);

    wire [31:0] corner_result = is_div_by_zero ? (funct3[1] ? op_a : 32'hFFFF_FFFF) :
                                (funct3[1] ? 32'h0000_0000 : 32'h8000_0000);

    // Operand Absolute Values and Signs
    wire sign_a = is_signed_op && op_a[31];
    wire sign_b = is_signed_op && op_b[31];
    wire [31:0] abs_a = sign_a ? (-op_a) : op_a;
    wire [31:0] abs_b = sign_b ? (-op_b) : op_b;

    // Iteration 1 Logic (Evaluated combinationally in S_IDLE on Cycle 1)
    wire [31:0] init_rem    = {31'd0, abs_a[31]};
    wire        init_sub    = (init_rem >= abs_b);
    wire [31:0] sub_rem_1   = init_sub ? (init_rem - abs_b) : init_rem;
    wire [31:0] step_quot_1 = {abs_a[30:0], init_sub};

    // Subsequent Iterations Logic (Iterations 2 to 32)
    wire [31:0] next_rem   = rem_quot[62:31];
    wire [31:0] next_quot  = {rem_quot[30:0], 1'b0};
    wire        can_sub    = (next_rem >= divisor);
    wire [31:0] sub_rem    = can_sub ? (next_rem - divisor) : next_rem;
    wire [31:0] step_quot  = can_sub ? {next_quot[31:1], 1'b1} : next_quot;

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
        end else begin
            case (state)
                S_IDLE: begin
                    if (is_div && !is_corner_case) begin
                        // Latch configuration and output of Iteration 1
                        saved_funct3 <= funct3;
                        neg_quot     <= is_signed_op && (sign_a ^ sign_b);
                        neg_rem      <= is_signed_op && sign_a;
                        divisor      <= abs_b;
                        rem_quot     <= {sub_rem_1, step_quot_1};
                        count        <= 5'd30; // 30 remaining iterations (count = 30 down to 1)
                        state        <= S_CALC;
                    end
                end

                S_CALC: begin
                    if (count == 5'd0) begin
                        // Completed 32nd iteration, return to IDLE
                        state <= S_IDLE;
                    end else begin
                        rem_quot <= {sub_rem, step_quot};
                        count    <= count - 5'd1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // Result Formation
    // On Cycle 32 (state == S_CALC && count == 0), the 32nd bit is active on {sub_rem, step_quot}
    wire [31:0] active_quot = (state == S_CALC && count == 5'd0) ? step_quot : rem_quot[31:0];
    wire [31:0] active_rem  = (state == S_CALC && count == 5'd0) ? sub_rem   : rem_quot[63:32];

    wire [31:0] adj_quot = neg_quot ? (-active_quot) : active_quot;
    wire [31:0] adj_rem  = neg_rem  ? (-active_rem)  : active_rem;

    wire [2:0]  active_funct3 = (state == S_IDLE) ? funct3 : saved_funct3;
    wire [31:0] calc_result   = active_funct3[1] ? adj_rem : adj_quot;

    assign div_result = is_corner_case ? corner_result : calc_result;

    // div_busy: High while division is calculating; drops on Cycle 32 when count == 0
    wire is_last_calc = (state == S_CALC) && (count == 5'd0);
    assign div_busy = is_div && !is_corner_case && !is_last_calc;
    assign div_done = is_div && (is_corner_case || is_last_calc);

endmodule
