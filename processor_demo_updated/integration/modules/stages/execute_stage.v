// ============================================================================
// File: execute_stage.v
// Module: execute_stage
// Description: Execution Stage integrating Base ALU, Zbb Bit Manipulation,
//              RV32M Multiplier & Divider, IEEE-754 FPU, BTB Mispredict Resolution,
//              and CSR Performance Read Multiplexing.
// ============================================================================

`timescale 1ns/1ps

module execute_stage (
    input  wire        clk,
    input  wire        reset_n,

    // Operands and Immediates from ID/EX
    input  wire [31:0] pc_i,
    input  wire [31:0] pc_plus4_i,
    input  wire [31:0] rdata1_i,
    input  wire [31:0] rdata2_i,
    input  wire [31:0] imm_i,

    // Forwarded Data Buses from Memory & Writeback Stages
    input  wire [31:0] ex_mem_data_i,
    input  wire [31:0] mem_wb_data_i,
    input  wire [1:0]  forward_a_i,
    input  wire [1:0]  forward_b_i,

    // Control Signals from ID/EX
    input  wire [2:0]  alu_op_i,
    input  wire        arithsubtype_i,
    input  wire        lui_i,
    input  wire        auipc_i,
    input  wire        jal_i,
    input  wire        jalr_i,
    input  wire        branch_i,
    input  wire        mem_read_i,
    input  wire        mem_write_i,
    input  wire        immediate_sel_i,
    input  wire        is_mul_i,
    input  wire        is_div_i,
    input  wire        is_fpu_i,
    input  wire        is_csr_i,
    input  wire [6:0]  funct7_i,
    input  wire        use_dsp_i,

    // Feature 8 CSR Read Data Input
    input  wire [31:0] csr_rdata_i,
    input wire [2:0] frm_i,
    output wire [31:0] csr_operand_o,

    // Feature 7 BTB Predictions from ID/EX
    input  wire        pred_taken_i,
    input  wire [31:0] pred_target_i,

    // Outputs to Pipeline / Hazard Unit
    output reg  [31:0] alu_result_o,
    output wire [31:0] mem_wdata_o,
    output wire [31:0] target_pc_o,
    output reg         branch_taken_o,
    output wire        branch_or_jump_taken_o,
    output wire        div_busy_o,
    output wire        fpu_busy_o,
    output wire [4:0] fp_flags_o,
    output wire int_divzero_o,

    // Feature 7 BTB Resolution Outputs
    output wire        mispredict_o,
    output wire [31:0] redirect_pc_o,
    output wire        btb_update_en_o,
    output wire        btb_update_taken_o,
    output wire [31:0] btb_update_pc_o,
    output wire [31:0] btb_update_target_o
);

    `include "opcode.vh"

    // ------------------------------------------------------------------------
    // 1. Operand Forwarding Multiplexers (0-cycle RAW bypass)
    // ------------------------------------------------------------------------
    reg [31:0] forwarded_rdata1;
    reg [31:0] forwarded_rdata2;

    always @(*) begin
        case (forward_a_i)
            FWD_MEM: forwarded_rdata1 = ex_mem_data_i;
            FWD_WB:  forwarded_rdata1 = mem_wb_data_i;
            default: forwarded_rdata1 = rdata1_i;
        endcase
    end

    always @(*) begin
        case (forward_b_i)
            FWD_MEM: forwarded_rdata2 = ex_mem_data_i;
            FWD_WB:  forwarded_rdata2 = mem_wb_data_i;
            default: forwarded_rdata2 = rdata2_i;
        endcase
    end

    // ALU operand selection
    wire [31:0] alu_in1 = forwarded_rdata1;
    wire [31:0] alu_in2 = immediate_sel_i ? imm_i : forwarded_rdata2;

    assign mem_wdata_o = forwarded_rdata2;
    assign csr_operand_o = forwarded_rdata1;

    // Subtractions for comparisons
    wire [32:0] sub_signed   = {alu_in1[31], alu_in1} - {alu_in2[31], alu_in2};
    wire [32:0] sub_unsigned = {1'b0, alu_in1} - {1'b0, alu_in2};

    // ------------------------------------------------------------------------
    // 2. Branch Condition Evaluation
    // ------------------------------------------------------------------------
    always @(*) begin
        case (alu_op_i)
            BEQ:     branch_taken_o = (alu_in1 == forwarded_rdata2);
            BNE:     branch_taken_o = (alu_in1 != forwarded_rdata2);
            BLT:     branch_taken_o = sub_signed[32];
            BGE:     branch_taken_o = !sub_signed[32];
            BLTU:    branch_taken_o = sub_unsigned[32];
            BGEU:    branch_taken_o = !sub_unsigned[32];
            default: branch_taken_o = 1'b0;
        endcase
    end

    // Target PC calculation
    wire [31:0] branch_target = pc_i + imm_i;
    wire [31:0] jal_target    = pc_i + imm_i;
    wire [31:0] jalr_target   = (alu_in1 + imm_i) & ~32'b1;

    assign branch_or_jump_taken_o = (branch_i && branch_taken_o) || jal_i || jalr_i;
    assign target_pc_o            = jalr_i ? jalr_target : branch_target;

    // BTB Branch Resolution & Misprediction Recovery
    assign btb_update_en_o     = branch_i || jal_i || jalr_i;
    assign btb_update_taken_o  = branch_or_jump_taken_o;
    assign btb_update_pc_o     = pc_i;
    assign btb_update_target_o = target_pc_o;

    assign mispredict_o = btb_update_en_o &&
                          ((branch_or_jump_taken_o != pred_taken_i) ||
                           (branch_or_jump_taken_o && (target_pc_o != pred_target_i)));

    assign redirect_pc_o = branch_or_jump_taken_o ? target_pc_o : pc_plus4_i;

    // ------------------------------------------------------------------------
    // 3. Sub-Execution Units
    // ------------------------------------------------------------------------
    // (a) Integrated ALU + Zbb
    wire [31:0] alu_zbb_result;
    alu_zbb u_alu_zbb (
        .alu_in1         (alu_in1),
        .alu_in2         (alu_in2),
        .imm_i           (imm_i),
        .alu_op_i        (alu_op_i),
        .arithsubtype_i  (arithsubtype_i),
        .immediate_sel_i (immediate_sel_i),
        .funct7_i        (funct7_i),
        .alu_result_o    (alu_zbb_result)
    );

    // (b) RV32M Multiplier Unit
    wire [31:0] mul_result;
    multiplier_unit #(
        .USE_DSP(1)
    ) u_multiplier (
        .clk         (clk),
        .reset_n     (reset_n),
        .is_mul      (is_mul_i),
        .use_dsp_sel (use_dsp_i),
        .funct3      (alu_op_i),
        .op_a        (alu_in1),
        .op_b        (forwarded_rdata2),
        .mul_result  (mul_result),
        .mul_busy    ()
    );

    // (c) RV32M 32-Cycle Restoring Divider
    wire [31:0] div_result;
    wire        div_busy;
    wire        div_done;

    divider_unit u_divider (
        .clk        (clk),
        .reset_n    (reset_n),
        .is_div     (is_div_i),
        .funct3     (alu_op_i),
        .op_a       (alu_in1),
        .op_b       (forwarded_rdata2),
        .div_result (div_result),
        .div_busy   (div_busy),
        .div_done   (div_done)
    );

    assign div_busy_o = div_busy;
    assign int_divzero_o=is_div_i && !div_busy && forwarded_rdata2==0;

    // (d) IEEE 754 Floating-Point Unit (FADD/FSUB 5c, FMUL 4c, FDIV 15c)
    wire [31:0] fpu_result;
    wire        fpu_busy;
    wire        fpu_done;

    wire fp_arithmetic = funct7_i == FUNCT7_FADD || funct7_i == FUNCT7_FSUB || funct7_i == FUNCT7_FMUL || funct7_i == FUNCT7_FDIV;

    fpu_single_core u_fpu (
        .clk        (clk),
        .reset_n    (reset_n),
        .is_fpu     (is_fpu_i && fp_arithmetic),
        .funct7     (funct7_i),
        .funct3     (alu_op_i==7 ? frm_i : alu_op_i),
        .op_a       (alu_in1),
        .op_b       (forwarded_rdata2),
        .fpu_result (fpu_result),
        .fpu_busy   (fpu_busy),
        .fpu_done   (fpu_done),
        .flags_o(fp_flags_o)
    );

    assign fpu_busy_o = fpu_busy;
    function [31:0] int_to_float;
        input [31:0] bits;
        input uns;
        reg sign_bit, found, guard_bit, sticky_bit;
        reg [31:0] magnitude;
        reg [24:0] significand;
        reg [7:0] exponent;
        integer i, highest, shift;
        begin
            sign_bit = !uns && bits[31];
            magnitude = sign_bit ? -bits : bits;
            highest=0; found=0;
            for (i=31;i>=0;i=i-1) if(magnitude[i] && !found) begin highest=i; found=1; end
            exponent = 127+highest;
            guard_bit=0; sticky_bit=0;
            if(highest<=23) significand = {1'b0,magnitude << (23-highest)};
            else begin
                shift=highest-23;
                significand = magnitude >> shift;
                guard_bit=magnitude[shift-1];
                for(i=0;i<31;i=i+1) if(i<shift-1) sticky_bit=sticky_bit|magnitude[i];
                if(guard_bit && (sticky_bit || significand[0])) significand=significand+1;
                if(significand[24]) begin significand=significand>>1; exponent=exponent+1; end
            end
            int_to_float = magnitude==0 ? 0 : {sign_bit,exponent,significand[22:0]};
        end
    endfunction

    // ------------------------------------------------------------------------
    // 4. Execution Result Multiplexer with Full Feature Arbitration
    // ------------------------------------------------------------------------
    always @(*) begin
        if (is_csr_i) begin
            // Feature 8: CSR performance counter reading
            alu_result_o = csr_rdata_i;
        end else if (is_mul_i) begin
            alu_result_o = mul_result;
        end else if (is_div_i) begin
            alu_result_o = div_result;
        end else if (is_fpu_i) begin
            case(funct7_i)
                7'b1101000: alu_result_o = int_to_float(alu_in1, imm_i[0]);
                7'b1111000,7'b1110000: alu_result_o = alu_in1;
                7'b0010000: case(alu_op_i)
                    3'b000: alu_result_o={forwarded_rdata2[31],alu_in1[30:0]};
                    3'b001: alu_result_o={~forwarded_rdata2[31],alu_in1[30:0]};
                    default: alu_result_o={alu_in1[31]^forwarded_rdata2[31],alu_in1[30:0]};
                endcase
                default: alu_result_o = fpu_result;
            endcase
        end else if (lui_i) begin
            alu_result_o = imm_i;
        end else if (auipc_i) begin
            alu_result_o = pc_i + imm_i;
        end else if (jal_i || jalr_i) begin
            alu_result_o = pc_plus4_i; // Return address PC + 4
        end else if (mem_read_i || mem_write_i) begin
            alu_result_o = alu_in1 + imm_i; // Memory effective address
        end else begin
            alu_result_o = alu_zbb_result;
        end
    end

endmodule
