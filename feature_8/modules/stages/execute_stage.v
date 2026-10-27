// ============================================================================
// File: execute_stage.v
// Module: execute_stage (Feature 7: BTB Branch Prediction Aware)
// Description: Execution Stage with Base ALU, Multiplier, Divider, FPU, & BTB Resolve
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

    // Forwarded Data Buses
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
    input  wire [6:0]  funct7_i,
    input  wire        use_dsp_i,

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
    // 1. Operand Forwarding Multiplexers
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

    // ALU input selection
    wire [31:0] alu_in1 = forwarded_rdata1;
    wire [31:0] alu_in2 = immediate_sel_i ? imm_i : forwarded_rdata2;

    assign mem_wdata_o = forwarded_rdata2;

    // ------------------------------------------------------------------------
    // 2. Subtractions for Branch Comparisons
    // ------------------------------------------------------------------------
    wire [32:0] sub_signed   = {alu_in1[31], alu_in1} - {forwarded_rdata2[31], forwarded_rdata2};
    wire [32:0] sub_unsigned = {1'b0, alu_in1} - {1'b0, forwarded_rdata2};

    // ------------------------------------------------------------------------
    // 3. Branch Condition Evaluation
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

    // Target PC computation
    wire [31:0] branch_target = pc_i + imm_i;
    wire [31:0] jal_target    = pc_i + imm_i;
    wire [31:0] jalr_target   = (alu_in1 + imm_i) & ~32'b1;

    assign branch_or_jump_taken_o = (branch_i && branch_taken_o) || jal_i || jalr_i;
    assign target_pc_o            = jalr_i ? jalr_target : branch_target;

    ////////////////////////////////////////////////////////////////////////////
    // TODO: Feature 7 BTB Branch Resolution & Misprediction Recovery
    //
    // Instructions:
    // 1. A branch/jump update to BTB is enabled whenever the EX stage instruction
    //    is a conditional branch, JAL, or JALR (branch_i || jal_i || jalr_i).
    // 2. A misprediction occurs IF:
    //    a) The actual branch decision != predicted decision:
    //       (branch_or_jump_taken_o != pred_taken_i)
    //    b) OR the branch was taken, but actual target PC != predicted target:
    //       (branch_or_jump_taken_o && (target_pc_o != pred_target_i))
    // 3. Recovery Redirect PC:
    //    - If actual was taken: redirect to target_pc_o
    //    - If actual was NOT taken: redirect to sequential pc_plus4_i
    ////////////////////////////////////////////////////////////////////////////

    assign btb_update_en_o     = branch_i || jal_i || jalr_i;
    assign btb_update_taken_o  = branch_or_jump_taken_o;
    assign btb_update_pc_o     = pc_i;
    assign btb_update_target_o = target_pc_o;

    assign mispredict_o = /* TODO: Detect misprediction */
                          btb_update_en_o &&
                          ((branch_or_jump_taken_o != pred_taken_i) ||
                           (branch_or_jump_taken_o && (target_pc_o != pred_target_i)));

    assign redirect_pc_o = /* TODO: Redirect to target_pc_o if taken, else pc_plus4_i */
                           branch_or_jump_taken_o ? target_pc_o : pc_plus4_i;

    // ------------------------------------------------------------------------
    // 4. Hardware Multiplier Execution Unit (DSP48E1 / Booth Radix-4)
    // ------------------------------------------------------------------------
    wire [31:0] mul_result;

    multiplier_unit #(
        .USE_DSP(1)
    ) u_multiplier (
        .clk         (1'b0),
        .reset_n     (1'b1),
        .is_mul      (is_mul_i),
        .use_dsp_sel (use_dsp_i),
        .funct3      (alu_op_i),
        .op_a        (alu_in1),
        .op_b        (forwarded_rdata2),
        .mul_result  (mul_result),
        .mul_busy    ()
    );

    // ------------------------------------------------------------------------
    // 5. Hardware Divider & Remainder Unit (32-Cycle Radix-2 Restoring)
    // ------------------------------------------------------------------------
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

    // ------------------------------------------------------------------------
    // 6. IEEE 754 Floating-Point Unit (FADD/FSUB 5c, FMUL 4c, FDIV 15c)
    // ------------------------------------------------------------------------
    wire [31:0] fpu_result;
    wire        fpu_busy;
    wire        fpu_done;

    fpu_single_core u_fpu (
        .clk        (clk),
        .reset_n    (reset_n),
        .is_fpu     (is_fpu_i),
        .funct7     (funct7_i),
        .funct3     (alu_op_i),
        .op_a       (alu_in1),
        .op_b       (forwarded_rdata2),
        .fpu_result (fpu_result),
        .fpu_busy   (fpu_busy),
        .fpu_done   (fpu_done)
    );

    assign fpu_busy_o = fpu_busy;

    // ------------------------------------------------------------------------
    // 7. Execution Result Multiplexer
    // ------------------------------------------------------------------------
    always @(*) begin
        if (is_mul_i) begin
            alu_result_o = mul_result;
        end else if (is_div_i) begin
            alu_result_o = div_result;
        end else if (is_fpu_i) begin
            alu_result_o = fpu_result;
        end else if (lui_i) begin
            alu_result_o = imm_i;
        end else if (auipc_i) begin
            alu_result_o = pc_i + imm_i;
        end else if (jal_i || jalr_i) begin
            alu_result_o = pc_plus4_i; // Return address PC + 4
        end else if (mem_read_i || mem_write_i) begin
            alu_result_o = alu_in1 + imm_i; // Memory effective address
        end else begin
            case (alu_op_i)
                ADD:  alu_result_o = (arithsubtype_i && !immediate_sel_i) ? (alu_in1 - alu_in2) : (alu_in1 + alu_in2);
                SLL:  alu_result_o = alu_in1 << alu_in2[4:0];
                SLT:  alu_result_o = {31'b0, sub_signed[32]};
                SLTU: alu_result_o = {31'b0, sub_unsigned[32]};
                XOR:  alu_result_o = alu_in1 ^ alu_in2;
                SR:   alu_result_o = arithsubtype_i ? ($signed(alu_in1) >>> alu_in2[4:0]) : (alu_in1 >> alu_in2[4:0]);
                OR:   alu_result_o = alu_in1 | alu_in2;
                AND:  alu_result_o = alu_in1 & alu_in2;
                default: alu_result_o = 32'h0;
            endcase
        end
    end

endmodule
