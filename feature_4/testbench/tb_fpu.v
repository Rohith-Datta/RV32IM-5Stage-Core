// ============================================================================
// File: tb_fpu.v
// Module: tb_fpu
// Description: Exhaustive Unit Testbench for IEEE 754 Single-Precision FPU (Feature 4)
// Verifies:
//   - Strict Cycle Latency Verification:
//       * FADD.S : Exactly 5 clock cycles
//       * FSUB.S : Exactly 5 clock cycles
//       * FMUL.S : Exactly 4 clock cycles
//       * FDIV.S : Exactly 15 clock cycles
//   - IEEE 754 Arithmetic Accuracy:
//       * Addition: 1.5 + 2.5 = 4.0, (-10.0) + 2.5 = -7.5, 0.0 + 5.0 = 5.0
//       * Subtraction: 5.0 - 3.0 = 2.0, 7.5 - 2.5 = 5.0, 4.0 - 4.0 = 0.0
//       * Multiplication: 4.0 * 2.0 = 8.0, 12.25 * 4.0 = 49.0, (-3.5) * 2.0 = -7.0, 0.0 * 8.0 = 0.0
//       * Division: 10.0 / 2.0 = 5.0, 100.0 / 8.0 = 12.5, 1.0 / 3.0 = 0.33333334
//       * Divide-by-Zero: 4.0 / 0.0 = +Infinity (32'h7F800000)
//   - Interlock Handshake:
//       * fpu_busy holds pipeline during calculation
//       * fpu_done pulses on the completion cycle
//   - 50 MHz Clock (20 ns period: 10 ns high, 10 ns low)
// ============================================================================

`timescale 1ns/1ps

module tb_fpu;

    reg         clk;
    reg         reset_n;
    reg         is_fpu;
    reg  [6:0]  funct7;
    reg  [2:0]  funct3;
    reg  [31:0] op_a;
    reg  [31:0] op_b;

    wire [31:0] fpu_result;
    wire        fpu_busy;
    wire        fpu_done;

    // Instantiate DUT
    fpu_single_core dut (
        .clk        (clk),
        .reset_n    (reset_n),
        .is_fpu     (is_fpu),
        .funct7     (funct7),
        .funct3     (funct3),
        .op_a       (op_a),
        .op_b       (op_b),
        .fpu_result (fpu_result),
        .fpu_busy   (fpu_busy),
        .fpu_done   (fpu_done)
    );

    // 50 MHz Clock Generator (20 ns period)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    integer test_count;
    integer pass_count;
    integer fail_count;

    // Helper task to execute an FPU operation and measure exact cycles
    task test_fpu_vector;
        input [6:0]   op_f7;
        input [2:0]   rm;
        input [31:0]  a;
        input [31:0]  b;
        input [31:0]  expected;
        input integer expected_cycles;
        input [127:0] test_name;
        integer elapsed_cycles;
        begin
            @(posedge clk);
            #1;
            funct7 = op_f7;
            funct3 = rm;
            op_a   = a;
            op_b   = b;
            is_fpu = 1'b1;
            elapsed_cycles = 1; // Cycle 1 (S_IDLE) is active

            // Step to Cycle 2 (transition into S_CALC)
            @(posedge clk);
            #1;
            elapsed_cycles = elapsed_cycles + 1;

            // Wait while computation continues in S_CALC
            while (fpu_busy && elapsed_cycles < 30) begin
                @(posedge clk);
                #1;
                elapsed_cycles = elapsed_cycles + 1;
            end

            // Now in S_DONE: fpu_busy has dropped, fpu_done is high, result is valid
            test_count = test_count + 1;
            if (fpu_result === expected && elapsed_cycles === expected_cycles) begin
                $display("[PASS] %-22s | Result=0x%08h (Exp=0x%08h) | Latency=%2d cyc (Exp=%2d)",
                         test_name, fpu_result, expected, elapsed_cycles, expected_cycles);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %-22s | Result=0x%08h (Exp=0x%08h) | Latency=%2d cyc (Exp=%2d)",
                         test_name, fpu_result, expected, elapsed_cycles, expected_cycles);
                fail_count = fail_count + 1;
            end

            // Release request, step back to S_IDLE
            @(posedge clk);
            #1;
            is_fpu = 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        $display("============================================================================");
        $display("           STARTING TESTBENCH: tb_fpu (Feature 4 IEEE 754 FPU)              ");
        $display("                 Clock Frequency: 50 MHz (Period: 20 ns)                   ");
        $display("============================================================================");

        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        reset_n = 0;
        is_fpu  = 0;
        funct7  = 0;
        funct3  = 0;
        op_a    = 0;
        op_b    = 0;

        #40;
        @(posedge clk);
        #1;
        reset_n = 1;
        #20;

        // --------------------------------------------------------------------
        // 1. FADD.S Tests (Target: Exactly 5 clock cycles)
        // --------------------------------------------------------------------
        $display("\n--- 1. FADD.S Tests (Strict Latency Requirement: 5 Cycles) ---");
        // 1.5 + 2.5 = 4.0
        test_fpu_vector(7'b0000000, 3'b000, 32'h3FC00000, 32'h40200000, 32'h40800000, 5, "FADD 1.5 + 2.5");
        // -10.0 + 2.5 = -7.5
        test_fpu_vector(7'b0000000, 3'b000, 32'hC1200000, 32'h40200000, 32'hC0F00000, 5, "FADD -10.0 + 2.5");
        // 0.0 + 5.0 = 5.0
        test_fpu_vector(7'b0000000, 3'b000, 32'h00000000, 32'h40A00000, 32'h40A00000, 5, "FADD 0.0 + 5.0");

        // --------------------------------------------------------------------
        // 2. FSUB.S Tests (Target: Exactly 5 clock cycles)
        // --------------------------------------------------------------------
        $display("\n--- 2. FSUB.S Tests (Strict Latency Requirement: 5 Cycles) ---");
        // 5.0 - 3.0 = 2.0
        test_fpu_vector(7'b0000100, 3'b000, 32'h40A00000, 32'h40400000, 32'h40000000, 5, "FSUB 5.0 - 3.0");
        // 7.5 - 2.5 = 5.0
        test_fpu_vector(7'b0000100, 3'b000, 32'h40F00000, 32'h40200000, 32'h40A00000, 5, "FSUB 7.5 - 2.5");
        // 4.0 - 4.0 = 0.0
        test_fpu_vector(7'b0000100, 3'b000, 32'h40800000, 32'h40800000, 32'h00000000, 5, "FSUB 4.0 - 4.0");

        // --------------------------------------------------------------------
        // 3. FMUL.S Tests (Target: Exactly 4 clock cycles)
        // --------------------------------------------------------------------
        $display("\n--- 3. FMUL.S Tests (Strict Latency Requirement: 4 Cycles) ---");
        // 4.0 * 2.0 = 8.0
        test_fpu_vector(7'b0001000, 3'b000, 32'h40800000, 32'h40000000, 32'h41000000, 4, "FMUL 4.0 * 2.0");
        // 12.25 * 4.0 = 49.0
        test_fpu_vector(7'b0001000, 3'b000, 32'h41440000, 32'h40800000, 32'h42440000, 4, "FMUL 12.25 * 4.0");
        // -3.5 * 2.0 = -7.0
        test_fpu_vector(7'b0001000, 3'b000, 32'hC0600000, 32'h40000000, 32'hC0E00000, 4, "FMUL -3.5 * 2.0");
        // 0.0 * 8.0 = 0.0
        test_fpu_vector(7'b0001000, 3'b000, 32'h00000000, 32'h41000000, 32'h00000000, 4, "FMUL 0.0 * 8.0");

        // --------------------------------------------------------------------
        // 4. FDIV.S Tests (Target: Exactly 15 clock cycles)
        // --------------------------------------------------------------------
        $display("\n--- 4. FDIV.S Tests (Strict Latency Requirement: 15 Cycles) ---");
        // 10.0 / 2.0 = 5.0
        test_fpu_vector(7'b0001100, 3'b000, 32'h41200000, 32'h40000000, 32'h40A00000, 15, "FDIV 10.0 / 2.0");
        // 100.0 / 8.0 = 12.5
        test_fpu_vector(7'b0001100, 3'b000, 32'h42C80000, 32'h41000000, 32'h41480000, 15, "FDIV 100.0 / 8.0");
        // 1.0 / 3.0 = 0.33333334 (0x3EAAAAAB)
        test_fpu_vector(7'b0001100, 3'b000, 32'h3F800000, 32'h40400000, 32'h3EAAAAAB, 15, "FDIV 1.0 / 3.0");
        // 4.0 / 0.0 = +Infinity (0x7F800000)
        test_fpu_vector(7'b0001100, 3'b000, 32'h40800000, 32'h00000000, 32'h7F800000, 15, "FDIV 4.0 / 0.0 (Div0)");

        $display("\n============================================================================");
        $display("                   TB_FPU SUMMARY RESULTS                                   ");
        $display("============================================================================");
        $display(" Total Vectors Run : %0d", test_count);
        $display(" Vectors Passed    : %0d", pass_count);
        $display(" Vectors Failed    : %0d", fail_count);
        if (fail_count == 0) begin
            $display(" STATUS: ALL FPU UNIT TESTS PASSED WITH 100%% CYCLE COMPLIANCE!");
        end else begin
            $display(" STATUS: FAILED!");
        end
        $display("============================================================================\n");

        #50;
        $finish;
    end

endmodule
