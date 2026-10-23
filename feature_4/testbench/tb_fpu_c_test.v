// ============================================================================
// File: tb_fpu_c_test.v
// Module: tb_fpu_c_test
// Description: Verification testbench for Compiled Bare-Metal C FPU & Special Cases
// Project: Pipelined RV32IMF Core on Nexys A7 FPGA (Feature 4: IEEE 754 FPU)
// ============================================================================

`timescale 1ns/1ps

module tb_fpu_c_test;

    reg clk;
    reg reset_n;

    // 50 MHz Core Clock
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // Interconnects
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we;
    wire        dmem_re;
    wire [31:0] dmem_rdata;

    wire [31:0] pc_if, pc_id, pc_ex, pc_mem, pc_wb;
    wire        wb_reg_write;
    wire [4:0]  wb_dest_reg;
    wire [31:0] wb_data;
    wire        hazard_stall, hazard_flush_id, hazard_flush_ex;
    wire [1:0]  forward_a, forward_b;
    wire        mul_active, div_active, div_busy, fpu_active, fpu_busy;
    wire        exception;

    // 4KB Instruction & Data Memory
    reg [31:0] imem [0:1023];
    reg [31:0] dmem [0:1023];

    assign imem_rdata = (imem_addr[11:2] < 1024) ? imem[imem_addr[11:2]] : 32'h0000_0013;
    assign dmem_rdata = (dmem_addr[11:2] < 1024) ? dmem[dmem_addr[11:2]] : 32'h0000_0000;

    always @(posedge clk) begin
        if (dmem_we) begin
            if (dmem_wstrb[0]) dmem[dmem_addr[11:2]][7:0]   <= dmem_wdata[7:0];
            if (dmem_wstrb[1]) dmem[dmem_addr[11:2]][15:8]  <= dmem_wdata[15:8];
            if (dmem_wstrb[2]) dmem[dmem_addr[11:2]][23:16] <= dmem_wdata[23:16];
            if (dmem_wstrb[3]) dmem[dmem_addr[11:2]][31:24] <= dmem_wdata[31:24];
        end
    end

    // Instantiate 5-Stage RV32IMF Core
    pipeline_5stage #(
        .RESET_PC(32'h0000_0000)
    ) dut (
        .clk             (clk),
        .reset_n         (reset_n),
        .stall_ext       (1'b0),
        .use_dsp_i       (1'b1),
        .imem_addr       (imem_addr),
        .imem_rdata      (imem_rdata),
        .dmem_addr       (dmem_addr),
        .dmem_wdata      (dmem_wdata),
        .dmem_wstrb      (dmem_wstrb),
        .dmem_we         (dmem_we),
        .dmem_re         (dmem_re),
        .dmem_rdata      (dmem_rdata),
        .pc_if           (pc_if),
        .pc_id           (pc_id),
        .pc_ex           (pc_ex),
        .pc_mem          (pc_mem),
        .pc_wb           (pc_wb),
        .wb_reg_write    (wb_reg_write),
        .wb_dest_reg     (wb_dest_reg),
        .wb_data         (wb_data),
        .hazard_stall    (hazard_stall),
        .hazard_flush_id (hazard_flush_id),
        .hazard_flush_ex (hazard_flush_ex),
        .forward_a       (forward_a),
        .forward_b       (forward_b),
        .mul_active      (mul_active),
        .div_active      (div_active),
        .div_busy        (div_busy),
        .fpu_active      (fpu_active),
        .fpu_busy        (fpu_busy),
        .exception       (exception)
    );

    integer pass_count = 0;
    integer fail_count = 0;
    integer i;

    initial begin
        $display("============================================================================");
        $display("   STARTING TESTBENCH: tb_fpu_c_test (Compiled C Code & Special Cases)     ");
        $display("                 Clock Frequency: 50 MHz (Period: 20 ns)                   ");
        $display("============================================================================");

        // Clear memory
        for (i = 0; i < 1024; i = i + 1) begin
            imem[i] = 32'h0000_0013; // NOP
            dmem[i] = 32'h0000_0000;
        end

        // Load compiled C code
        $readmemh("mem/imem.hex", imem);

        reset_n = 0;
        #50;
        @(posedge clk);
        #1;
        reset_n = 1;
        $display("[TB] Core released from reset at time %0t ns", $time);
    end

    // Monitor Writeback stage and verify arithmetic results
    always @(posedge clk) begin
        if (reset_n && wb_reg_write && (wb_dest_reg != 5'd0)) begin
            $display("Time=%7t ns | WB: PC=0x%08h | Reg x%02d <= 0x%08h", $time, pc_wb, wb_dest_reg, wb_data);

            case (wb_dest_reg)
                // Standard Arithmetic Checks
                5'd12: begin // FADD.S (1.5 + 2.5 = 4.0f -> 0x40800000)
                    if (wb_data === 32'h40800000) begin
                        $display("[PASS] 1. FADD.S (1.5 + 2.5): x12 = 0x%08h (4.0f)", wb_data);
                        pass_count = pass_count + 1;
                    end else begin
                        $display("[FAIL] 1. FADD.S (1.5 + 2.5): x12 = 0x%08h, Expected: 0x40800000", wb_data);
                        fail_count = fail_count + 1;
                    end
                end

                5'd13: begin // FSUB.S (4.0 - 1.5 = 2.5f -> 0x40200000)
                    if (wb_data === 32'h40200000) begin
                        $display("[PASS] 2. FSUB.S (4.0 - 1.5): x13 = 0x%08h (2.5f)", wb_data);
                        pass_count = pass_count + 1;
                    end else begin
                        $display("[FAIL] 2. FSUB.S (4.0 - 1.5): x13 = 0x%08h, Expected: 0x40200000", wb_data);
                        fail_count = fail_count + 1;
                    end
                end

                5'd14: begin // FMUL.S (2.0 * 2.5 = 5.0f -> 0x40A00000)
                    if (wb_data === 32'h40a00000) begin
                        $display("[PASS] 3. FMUL.S (2.0 * 2.5): x14 = 0x%08h (5.0f)", wb_data);
                        pass_count = pass_count + 1;
                    end else begin
                        $display("[FAIL] 3. FMUL.S (2.0 * 2.5): x14 = 0x%08h, Expected: 0x40A00000", wb_data);
                        fail_count = fail_count + 1;
                    end
                end

                5'd15: begin // FDIV.S (7.0 / 2.0 = 3.5f -> 0x40600000)
                    if (wb_data === 32'h40600000) begin
                        $display("[PASS] 4. FDIV.S (7.0 / 2.0): x15 = 0x%08h (3.5f, Newton-Raphson)", wb_data);
                        pass_count = pass_count + 1;
                    end else begin
                        $display("[FAIL] 4. FDIV.S (7.0 / 2.0): x15 = 0x%08h, Expected: 0x40600000", wb_data);
                        fail_count = fail_count + 1;
                    end
                end

                // Special Cases Checks
                5'd16: begin // Special Case 1: Div by Zero (2.0 / 0.0 -> +Inf, 0x7F800000)
                    if (wb_data === 32'h7f800000) begin
                        $display("[PASS] 5. [SPECIAL CASE 1] Div-By-Zero (2.0 / 0.0): x16 = 0x%08h (+Infinity)", wb_data);
                        pass_count = pass_count + 1;
                    end else begin
                        $display("[FAIL] 5. [SPECIAL CASE 1] Div-By-Zero: x16 = 0x%08h, Expected: 0x7F800000", wb_data);
                        fail_count = fail_count + 1;
                    end
                end

                5'd17: begin // Special Case 2: Negative Div by Zero (-2.0 / 0.0 -> -Inf, 0xFF800000)
                    if (wb_data === 32'hff800000) begin
                        $display("[PASS] 6. [SPECIAL CASE 2] Neg Div-By-Zero (-2.0 / 0.0): x17 = 0x%08h (-Infinity)", wb_data);
                        pass_count = pass_count + 1;
                    end else begin
                        $display("[FAIL] 6. [SPECIAL CASE 2] Neg Div-By-Zero: x17 = 0x%08h, Expected: 0xFF800000", wb_data);
                        fail_count = fail_count + 1;
                    end
                end

                5'd18: begin // Special Case 3: Zero Div Zero (0.0 / 0.0 -> qNaN, 0x7FC00000)
                    if (wb_data === 32'h7fc00000) begin
                        $display("[PASS] 7. [SPECIAL CASE 3] Zero/Zero (0.0 / 0.0): x18 = 0x%08h (qNaN)", wb_data);
                        pass_count = pass_count + 1;
                    end else begin
                        $display("[FAIL] 7. [SPECIAL CASE 3] Zero/Zero: x18 = 0x%08h, Expected: 0x7FC00000", wb_data);
                        fail_count = fail_count + 1;
                    end
                end

                5'd19: begin // Special Case 4: Inf Div Inf (+Inf / +Inf -> qNaN, 0x7FC00000)
                    if (wb_data === 32'h7fc00000) begin
                        $display("[PASS] 8. [SPECIAL CASE 4] Inf/Inf (+Inf / +Inf): x19 = 0x%08h (qNaN)", wb_data);
                        pass_count = pass_count + 1;
                    end else begin
                        $display("[FAIL] 8. [SPECIAL CASE 4] Inf/Inf: x19 = 0x%08h, Expected: 0x7FC00000", wb_data);
                        fail_count = fail_count + 1;
                    end
                end

                5'd20: begin // Special Case 5: Negative Division (-6.0 / 2.0 -> -3.0f, 0xC0400000)
                    if (wb_data === 32'hc0400000) begin
                        $display("[PASS] 9. [SPECIAL CASE 5] Negative Division (-6.0 / 2.0): x20 = 0x%08h (-3.0f)", wb_data);
                        pass_count = pass_count + 1;
                    end else begin
                        $display("[FAIL] 9. [SPECIAL CASE 5] Negative Division: x20 = 0x%08h, Expected: 0xC0400000", wb_data);
                        fail_count = fail_count + 1;
                    end
                end

                5'd21: begin // Special Case 6: Integer Div by Zero (10 / 0 -> 0xFFFFFFFF)
                    if (wb_data === 32'hffffffff) begin
                        $display("[PASS] 10. [SPECIAL CASE 6] Integer Div-By-Zero (10 / 0): x21 = 0x%08h (-1)", wb_data);
                        pass_count = pass_count + 1;
                    end else begin
                        $display("[FAIL] 10. [SPECIAL CASE 6] Integer Div-By-Zero: x21 = 0x%08h, Expected: 0xFFFFFFFF", wb_data);
                        fail_count = fail_count + 1;
                    end
                end

                5'd22: begin // Special Case 7: Integer Signed Overflow (INT_MIN / -1 -> INT_MIN, 0x80000000)
                    if (wb_data === 32'h80000000) begin
                        $display("[PASS] 11. [SPECIAL CASE 7] Integer Signed Overflow: x22 = 0x%08h (INT_MIN)", wb_data);
                        pass_count = pass_count + 1;
                    end else begin
                        $display("[FAIL] 11. [SPECIAL CASE 7] Integer Signed Overflow: x22 = 0x%08h, Expected: 0x80000000", wb_data);
                        fail_count = fail_count + 1;
                    end
                end

                5'd24: begin // Signature LUI/ADDI
                    if (wb_data === 32'hcafefeed) begin
                        $display("[PASS] 12. Signature Registered: x24 = 0x%08h (CAFEFEED)", wb_data);
                        pass_count = pass_count + 1;
                    end
                end
            endcase
        end
    end

    // Monitor Memory Stores
    always @(posedge clk) begin
        if (reset_n && dmem_we) begin
            $display("Time=%7t ns | DMEM WRITE: Addr=0x%08h Data=0x%08h", $time, dmem_addr, dmem_wdata);
            if (dmem_addr === 32'h0000022c && dmem_wdata === 32'hcafefeed) begin
                $display("\n>>> [MEM MATCH] C Program Signature 0xCAFEFEED successfully written to RAM[0x22C]! <<<");
            end
        end
    end

    // Simulation termination and summary
    initial begin
        // Wait for completion
        #5000;

        $display("\n============================================================================");
        $display("             BARE-METAL C TEST VERIFICATION SUMMARY                         ");
        $display("============================================================================");
        $display(" Total Checked Verifications : %0d", pass_count + fail_count);
        $display(" Passed Verifications        : %0d", pass_count);
        $display(" Failed Verifications        : %0d", fail_count);
        $display(" RAM Signature [0x22C]       : 0x%08h (Expected: 0xCAFEFEED)", dmem[128 + 11]);

        if (fail_count == 0 && pass_count >= 12 && dmem[128 + 11] === 32'hcafefeed) begin
            $display("\n >>> ALL ARITHMETIC OPERATIONS & SPECIAL CASES PASSED 100%! <<<");
        end else begin
            $display("\n >>> VERIFICATION FAILED! <<<");
        end
        $display("============================================================================\n");
        $finish;
    end

endmodule
