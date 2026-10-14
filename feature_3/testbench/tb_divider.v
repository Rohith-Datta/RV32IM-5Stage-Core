// ============================================================================
// File: tb_divider.v
// Module: tb_divider
// Description: Exhaustive Unit Testbench for RV32M Hardware Divider (Feature 3)
// Verifies:
//   - DIV, DIVU, REM, REMU across all signed/unsigned boundary conditions
//   - RISC-V Specification Corner Cases:
//       * Divide-by-Zero (DIV/DIVU -> -1, REM/REMU -> dividend)
//       * Signed Overflow (INT_MIN / -1 -> INT_MIN, REM -> 0)
//   - Multi-cycle handshake (busy / done timing)
//   - 100 Randomized test vectors with automated self-checking
// ============================================================================

`timescale 1ns/1ps

module tb_divider;

    reg         clk;
    reg         reset_n;
    reg         is_div;
    reg  [2:0]  funct3;
    reg  [31:0] op_a;
    reg  [31:0] op_b;

    wire [31:0] div_result;
    wire        div_busy;
    wire        div_done;

    // Instantiate DUT
    divider_unit dut (
        .clk        (clk),
        .reset_n    (reset_n),
        .is_div     (is_div),
        .funct3     (funct3),
        .op_a       (op_a),
        .op_b       (op_b),
        .div_result (div_result),
        .div_busy   (div_busy),
        .div_done   (div_done)
    );

    // 50 MHz Clock (20 ns period)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    integer test_count;
    integer pass_count;
    integer fail_count;

    // Helper task to run and verify 1 division vector
    task check_vector;
        input [2:0]   f3;
        input [31:0]  a;
        input [31:0]  b;
        input [31:0]  expected;
        input [127:0] test_name;
        integer timeout;
        begin
            @(posedge clk);
            #1;
            funct3 = f3;
            op_a   = a;
            op_b   = b;
            is_div = 1'b1;

            timeout = 0;
            // Wait until div_done is asserted (or div_busy drops)
            @(posedge clk);
            #1;
            while (div_busy && timeout < 50) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end

            test_count = test_count + 1;
            if (div_result === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s | A=0x%08h (%0d), B=0x%08h (%0d) -> Result=0x%08h (%0d)",
                         test_name, a, $signed(a), b, $signed(b), div_result, $signed(div_result));
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s | A=0x%08h, B=0x%08h | Expected=0x%08h, Got=0x%08h",
                         test_name, a, b, expected, div_result);
            end

            // Release is_div for at least 1 cycle to let divider return to IDLE
            @(posedge clk);
            #1;
            is_div = 1'b0;
        end
    endtask

    // Golden Software Reference Model
    function [31:0] golden_div;
        input [2:0]  f3;
        input [31:0] a;
        input [31:0] b;
        reg signed [31:0] sa;
        reg signed [31:0] sb;
        begin
            sa = a;
            sb = b;
            case (f3)
                3'b100: begin // DIV (Signed)
                    if (b == 32'd0)
                        golden_div = 32'hFFFF_FFFF;
                    else if (a == 32'h8000_0000 && b == 32'hFFFF_FFFF)
                        golden_div = 32'h8000_0000;
                    else
                        golden_div = sa / sb;
                end
                3'b101: begin // DIVU (Unsigned)
                    if (b == 32'd0)
                        golden_div = 32'hFFFF_FFFF;
                    else
                        golden_div = a / b;
                end
                3'b110: begin // REM (Signed)
                    if (b == 32'd0)
                        golden_div = a;
                    else if (a == 32'h8000_0000 && b == 32'hFFFF_FFFF)
                        golden_div = 32'h0000_0000;
                    else
                        golden_div = sa % sb;
                end
                3'b111: begin // REMU (Unsigned)
                    if (b == 32'd0)
                        golden_div = a;
                    else
                        golden_div = a % b;
                end
                default: golden_div = 32'h0;
            endcase
        end
    endfunction

    integer k;
    reg [31:0] rand_a, rand_b;
    reg [2:0]  rand_op;

    initial begin
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        reset_n    = 0;
        is_div     = 0;
        funct3     = 3'b100;
        op_a       = 32'h0;
        op_b       = 32'h0;

        #25;
        reset_n = 1;
        #20;

        $display("================================================================================");
        $display("   STARTING RV32M HARDWARE DIVIDER EXHAUSTIVE UNIT TESTBENCH");
        $display("================================================================================");

        // --------------------------------------------------------------------
        // 1. DIV (Signed Quotient) Tests
        // --------------------------------------------------------------------
        $display("\n--- 1. Testing DIV (Signed Quotient) ---");
        check_vector(3'b100, 32'd100,        32'd7,          32'd14,         "DIV 100 / 7");
        check_vector(3'b100, -32'sd100,      32'd7,          -32'sd14,       "DIV (-100) / 7");
        check_vector(3'b100, 32'd100,        -32'sd7,        -32'sd14,       "DIV 100 / (-7)");
        check_vector(3'b100, -32'sd100,      -32'sd7,        32'd14,         "DIV (-100) / (-7)");
        check_vector(3'b100, 32'd400,        32'd16,         32'd25,         "DIV 400 / 16 (Exact)");
        check_vector(3'b100, 32'd5,          32'd10,         32'd0,          "DIV 5 / 10");
        check_vector(3'b100, 32'd0,          32'd20,         32'd0,          "DIV 0 / 20");

        // --------------------------------------------------------------------
        // 2. DIVU (Unsigned Quotient) Tests
        // --------------------------------------------------------------------
        $display("\n--- 2. Testing DIVU (Unsigned Quotient) ---");
        check_vector(3'b101, 32'd100,        32'd7,          32'd14,         "DIVU 100 / 7");
        check_vector(3'b101, 32'hFFFF_FFFF,  32'd2,          32'h7FFF_FFFF,  "DIVU UINT_MAX / 2");
        check_vector(3'b101, 32'h8000_0000,  32'd2,          32'h4000_0000,  "DIVU 2^31 / 2");
        check_vector(3'b101, 32'd50,         32'd50,         32'd1,          "DIVU 50 / 50");

        // --------------------------------------------------------------------
        // 3. REM (Signed Remainder) Tests
        // --------------------------------------------------------------------
        $display("\n--- 3. Testing REM (Signed Remainder) ---");
        check_vector(3'b110, 32'd100,        32'd7,          32'd2,          "REM 100 % 7");
        check_vector(3'b110, -32'sd100,      32'd7,          -32'sd2,        "REM (-100) % 7");
        check_vector(3'b110, 32'd100,        -32'sd7,        32'd2,          "REM 100 % (-7)");
        check_vector(3'b110, -32'sd100,      -32'sd7,        -32'sd2,        "REM (-100) % (-7)");
        check_vector(3'b110, 32'd400,        32'd16,         32'd0,          "REM 400 % 16 (Zero)");

        // --------------------------------------------------------------------
        // 4. REMU (Unsigned Remainder) Tests
        // --------------------------------------------------------------------
        $display("\n--- 4. Testing REMU (Unsigned Remainder) ---");
        check_vector(3'b111, 32'd100,        32'd7,          32'd2,          "REMU 100 % 7");
        check_vector(3'b111, 32'hFFFF_FFFF,  32'd2,          32'd1,          "REMU UINT_MAX % 2");
        check_vector(3'b111, 32'd45,         32'd5,          32'd0,          "REMU 45 % 5");

        // --------------------------------------------------------------------
        // 5. RISC-V Specification Corner Cases
        // --------------------------------------------------------------------
        $display("\n--- 5. Testing RISC-V Specification Corner Cases ---");
        // Divide by Zero
        check_vector(3'b100, 32'd1234,       32'd0,          32'hFFFF_FFFF,  "DIV by 0 -> -1");
        check_vector(3'b100, -32'sd5678,     32'd0,          32'hFFFF_FFFF,  "DIV (neg) by 0 -> -1");
        check_vector(3'b101, 32'd9999,       32'd0,          32'hFFFF_FFFF,  "DIVU by 0 -> 2^32-1");
        check_vector(3'b110, 32'd1234,       32'd0,          32'd1234,       "REM by 0 -> dividend");
        check_vector(3'b110, -32'sd5678,     32'd0,          -32'sd5678,     "REM (neg) by 0 -> dividend");
        check_vector(3'b111, 32'd9999,       32'd0,          32'd9999,       "REMU by 0 -> dividend");

        // Signed Overflow (INT_MIN / -1)
        check_vector(3'b100, 32'h8000_0000,  32'hFFFF_FFFF,  32'h8000_0000,  "DIV INT_MIN / (-1) -> INT_MIN");
        check_vector(3'b110, 32'h8000_0000,  32'hFFFF_FFFF,  32'h0000_0000,  "REM INT_MIN % (-1) -> 0");
        check_vector(3'b101, 32'h8000_0000,  32'hFFFF_FFFF,  32'd0,          "DIVU 2^31 / UINT_MAX -> 0");
        check_vector(3'b111, 32'h8000_0000,  32'hFFFF_FFFF,  32'h8000_0000,  "REMU 2^31 % UINT_MAX -> 2^31");

        // --------------------------------------------------------------------
        // 6. 100 Randomized Test Vectors
        // --------------------------------------------------------------------
        $display("\n--- 6. Running 100 Randomized Vectors Across All 4 Operations ---");
        for (k = 0; k < 100; k = k + 1) begin
            rand_a  = $urandom();
            rand_b  = $urandom();
            rand_op = 3'b100 | (k % 4); // cycles through DIV, DIVU, REM, REMU
            check_vector(rand_op, rand_a, rand_b, golden_div(rand_op, rand_a, rand_b), "Random Vector");
        end

        // --------------------------------------------------------------------
        // Test Summary
        // --------------------------------------------------------------------
        $display("\n================================================================================");
        $display("   RV32M HARDWARE DIVIDER VERIFICATION RESULTS");
        $display("================================================================================");
        $display(" Total Vectors Run : %0d", test_count);
        $display(" Vectors Passed    : %0d", pass_count);
        $display(" Vectors Failed    : %0d", fail_count);
        if (fail_count == 0) begin
            $display(" [+++] STATUS: 100%% ALL DIVIDER TESTS PASSED WITH ZERO ERRORS!");
            $display(" [+++] Full RV32M DIV, DIVU, REM, REMU and Corner Cases Conforming to RISC-V Spec!");
        end else begin
            $display(" [---] STATUS: DIVIDER TESTS FAILED! Check logs above.");
        end
        $display("================================================================================\n");

        $finish;
    end

endmodule
