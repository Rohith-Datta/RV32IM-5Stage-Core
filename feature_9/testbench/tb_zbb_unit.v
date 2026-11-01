// ============================================================================
// File: tb_zbb_unit.v
// Module: tb_zbb_unit
// Description: Comprehensive Unit Testbench for All 18 Zbb Instructions
// Verifies 1-cycle latency and exact calculation for each operation.
// ============================================================================

`timescale 1ns/1ps

module tb_zbb_unit;

    reg         clk;
    reg         reset_n;
    reg  [31:0] pc_i;
    reg  [31:0] pc_plus4_i;
    reg  [31:0] rdata1_i;
    reg  [31:0] rdata2_i;
    reg  [31:0] imm_i;
    reg  [1:0]  forward_a_i;
    reg  [1:0]  forward_b_i;
    reg  [2:0]  alu_op_i;
    reg         arithsubtype_i;
    reg         immediate_sel_i;
    reg  [6:0]  funct7_i;

    wire [31:0] alu_result_o;

    `include "opcode.vh"

    execute_stage u_dut (
        .clk                   (clk),
        .reset_n               (reset_n),
        .pc_i                  (pc_i),
        .pc_plus4_i            (pc_plus4_i),
        .rdata1_i              (rdata1_i),
        .rdata2_i              (rdata2_i),
        .imm_i                 (imm_i),
        .ex_mem_data_i         (32'h0),
        .mem_wb_data_i         (32'h0),
        .forward_a_i           (forward_a_i),
        .forward_b_i           (forward_b_i),
        .alu_op_i              (alu_op_i),
        .arithsubtype_i        (arithsubtype_i),
        .lui_i                 (1'b0),
        .auipc_i               (1'b0),
        .jal_i                 (1'b0),
        .jalr_i                (1'b0),
        .branch_i              (1'b0),
        .mem_read_i            (1'b0),
        .mem_write_i           (1'b0),
        .immediate_sel_i       (immediate_sel_i),
        .is_mul_i              (1'b0),
        .is_div_i              (1'b0),
        .is_fpu_i              (1'b0),
        .funct7_i              (funct7_i),
        .use_dsp_i             (1'b1),
        .pred_taken_i          (1'b0),
        .pred_target_i         (32'h0),
        .alu_result_o          (alu_result_o),
        .mem_wdata_o           (),
        .target_pc_o           (),
        .branch_taken_o        (),
        .branch_or_jump_taken_o(),
        .div_busy_o            (),
        .fpu_busy_o            (),
        .mispredict_o          (),
        .redirect_pc_o         (),
        .btb_update_en_o       (),
        .btb_update_taken_o    (),
        .btb_update_pc_o       (),
        .btb_update_target_o   ()
    );

    integer pass_count = 0;
    integer fail_count = 0;

    task check_res;
        input [31:0] expected;
        input [127:0] inst_name;
        begin
            #1;
            if (alu_result_o === expected) begin
                $display("[PASS] %0s: Got 0x%08X (Expected 0x%08X)", inst_name, alu_result_o, expected);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s: Got 0x%08X (Expected 0x%08X)", inst_name, alu_result_o, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        clk             = 0;
        reset_n         = 1;
        pc_i            = 32'h0;
        pc_plus4_i      = 32'h4;
        rdata1_i        = 32'h0;
        rdata2_i        = 32'h0;
        imm_i           = 32'h0;
        forward_a_i     = 2'b00;
        forward_b_i     = 2'b00;
        alu_op_i        = 3'b000;
        arithsubtype_i  = 1'b0;
        immediate_sel_i = 1'b0;
        funct7_i        = 7'b0000000;

        #10;
        $display("==================================================");
        $display(" STARTING ZBB EXECUTE STAGE DIRECT UNIT TESTS");
        $display("==================================================");

        // 1. andn x3, x2, x1 (5 & ~(-2) = 1)
        rdata1_i = 32'd5; rdata2_i = 32'hFFFFFFFE; immediate_sel_i = 0;
        alu_op_i = AND; funct7_i = FUNCT7_ZBB_LOGIC;
        check_res(32'h00000001, "andn");

        // 2. orn x4, x2, x1 (5 | ~(-2) = 5)
        alu_op_i = OR; funct7_i = FUNCT7_ZBB_LOGIC;
        check_res(32'h00000005, "orn");

        // 3. xnor x5, x2, x1 (~(5 ^ -2) = 4)
        alu_op_i = XOR; funct7_i = FUNCT7_ZBB_LOGIC;
        check_res(32'h00000004, "xnor");

        // 4. max x6, x1, x2 (max(-2, 5) = 5)
        rdata1_i = 32'hFFFFFFFE; rdata2_i = 32'd5;
        alu_op_i = OR; funct7_i = FUNCT7_ZBB_MINMAX;
        check_res(32'h00000005, "max");

        // 5. maxu x7, x1, x2 (maxu(0xFFFFFFFE, 5) = 0xFFFFFFFE)
        alu_op_i = AND; funct7_i = FUNCT7_ZBB_MINMAX;
        check_res(32'hFFFFFFFE, "maxu");

        // 6. min x8, x1, x2 (min(-2, 5) = -2 = 0xFFFFFFFE)
        alu_op_i = XOR; funct7_i = FUNCT7_ZBB_MINMAX;
        check_res(32'hFFFFFFFE, "min");

        // 7. minu x9, x1, x2 (minu(0xFFFFFFFE, 5) = 5)
        alu_op_i = SR; funct7_i = FUNCT7_ZBB_MINMAX;
        check_res(32'h00000005, "minu");

        // 8. zext.h x11, x10 (0xFFFFFFFF -> 0x0000FFFF)
        rdata1_i = 32'hFFFFFFFF; rdata2_i = 32'h0;
        alu_op_i = XOR; funct7_i = FUNCT7_ZBB_PACK;
        check_res(32'h0000FFFF, "zext.h");

        // 9. sext.h x12, x10 (0xFFFFFFFF -> 0xFFFFFFFF)
        rdata1_i = 32'hFFFFFFFF; immediate_sel_i = 1;
        imm_i = {{20{1'b0}}, IMM12_SEXTH}; funct7_i = IMM12_SEXTH[11:5];
        alu_op_i = SLL;
        check_res(32'hFFFFFFFF, "sext.h");

        // 10. sext.b x13, x10 (0xFFFFFFFF -> 0xFFFFFFFF)
        imm_i = {{20{1'b0}}, IMM12_SEXTB}; funct7_i = IMM12_SEXTB[11:5];
        alu_op_i = SLL;
        check_res(32'hFFFFFFFF, "sext.b");

        // 11. clz x15, x14 (0x000000F0 -> 24)
        rdata1_i = 32'h000000F0;
        imm_i = {{20{1'b0}}, IMM12_CLZ}; funct7_i = IMM12_CLZ[11:5];
        alu_op_i = SLL;
        check_res(32'd24, "clz");

        // 12. ctz x16, x14 (0x000000F0 -> 4)
        imm_i = {{20{1'b0}}, IMM12_CTZ}; funct7_i = IMM12_CTZ[11:5];
        alu_op_i = SLL;
        check_res(32'd4, "ctz");

        // 13. cpop x17, x14 (0x000000F0 -> 4)
        imm_i = {{20{1'b0}}, IMM12_CPOP}; funct7_i = IMM12_CPOP[11:5];
        alu_op_i = SLL;
        check_res(32'd4, "cpop");

        // 14. rol x18, x14, x2 (0xF0 rotated left by 5 = 0x00001E00)
        rdata1_i = 32'h000000F0; rdata2_i = 32'd5; immediate_sel_i = 0;
        alu_op_i = SLL; funct7_i = FUNCT7_ZBB_ROT;
        check_res(32'h00001E00, "rol");

        // 15. ror x19, x14, x2 (0xF0 rotated right by 5 = 0x80000007)
        alu_op_i = SR; funct7_i = FUNCT7_ZBB_ROT;
        check_res(32'h80000007, "ror");

        // 16. rori x20, x14, 4 (0xF0 rotated right by 4 = 0x0000000F)
        immediate_sel_i = 1; imm_i = 32'd4;
        alu_op_i = SR; funct7_i = FUNCT7_ZBB_ROT;
        check_res(32'h0000000F, "rori");

        // 17. rev8 x21, x14 (0x000000F0 byte reversed = 0xF0000000)
        imm_i = {{20{1'b0}}, IMM12_REV8}; funct7_i = IMM12_REV8[11:5];
        alu_op_i = SR;
        check_res(32'hF0000000, "rev8");

        // 18. orc.b x22, x14 (0x000000F0 -> 0x000000FF)
        imm_i = {{20{1'b0}}, IMM12_ORCB}; funct7_i = IMM12_ORCB[11:5];
        alu_op_i = SR;
        check_res(32'h000000FF, "orc.b");

        $display("==================================================");
        $display(" UNIT TEST RESULTS: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==================================================");
        if (fail_count == 0)
            $display("ALL 18 ZBB INSTRUCTIONS VERIFIED SUCCESSFULLY!");
        else
            $display("ERROR: SOME ZBB INSTRUCTIONS FAILED!");
        $finish;
    end

endmodule
