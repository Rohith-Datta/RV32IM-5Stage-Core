// ============================================================================
// File: execute_stage.v
// Module: execute_stage (Feature 9: Zbb Bit-Manipulation Extension)
// Description: Execution Stage with Base ALU, Multiplier, Divider, FPU, BTB & Zbb
// All 18 Zbb instructions complete in exactly 1 cycle with 0 pipeline stalls.
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
    // 2. Subtractions for Comparisons (Branch, SLT, SLTU, and Zbb min/max)
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
    // 7. Zbb Bit Manipulation Logic (1 Cycle Combinational)
    // ------------------------------------------------------------------------
    // (a) Bitwise Rotations (ROL, ROR, RORI)
    wire [63:0] rol_double  = {alu_in1, alu_in1};
    wire [63:0] rol_shifted = rol_double << alu_in2[4:0];
    wire [31:0] rol_result  = rol_shifted[63:32];

    wire [63:0] ror_double  = {alu_in1, alu_in1};
    wire [63:0] ror_shifted = ror_double >> alu_in2[4:0];
    wire [31:0] ror_result  = ror_shifted[31:0];

    // (b) Byte Reverse (REV8)
    wire [31:0] rev8_result = {alu_in1[7:0], alu_in1[15:8], alu_in1[23:16], alu_in1[31:24]};

    // (c) OR Combine (ORC.B)
    wire [31:0] orc_b_result = {
        (|alu_in1[31:24]) ? 8'hFF : 8'h00,
        (|alu_in1[23:16]) ? 8'hFF : 8'h00,
        (|alu_in1[15:8])  ? 8'hFF : 8'h00,
        (|alu_in1[7:0])   ? 8'hFF : 8'h00
    };

    // (d) Count Leading Zeros (CLZ)
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

    // (e) Count Trailing Zeros (CTZ)
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

    // (f) Population Count (CPOP)
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
    // 8. Execution Result Multiplexer
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
                ADD: begin
                    alu_result_o = (arithsubtype_i && !immediate_sel_i) ? (alu_in1 - alu_in2) : (alu_in1 + alu_in2);
                end

                SLL: begin
                    if (immediate_sel_i && (imm_i[11:0] == IMM12_CLZ)) begin
                        // clz (I-type: imm12=0x600, funct3=1)
                        alu_result_o = count_leading_zeros(alu_in1);
                    end else if (immediate_sel_i && (imm_i[11:0] == IMM12_CTZ)) begin
                        // ctz (I-type: imm12=0x601, funct3=1)
                        alu_result_o = count_trailing_zeros(alu_in1);
                    end else if (immediate_sel_i && (imm_i[11:0] == IMM12_CPOP)) begin
                        // cpop (I-type: imm12=0x602, funct3=1)
                        alu_result_o = count_ones(alu_in1);
                    end else if (immediate_sel_i && (imm_i[11:0] == IMM12_SEXTB)) begin
                        // sext.b (I-type: imm12=0x604, funct3=1)
                        alu_result_o = {{24{alu_in1[7]}}, alu_in1[7:0]};
                    end else if (immediate_sel_i && (imm_i[11:0] == IMM12_SEXTH)) begin
                        // sext.h (I-type: imm12=0x605, funct3=1)
                        alu_result_o = {{16{alu_in1[15]}}, alu_in1[15:0]};
                    end else if (!immediate_sel_i && (funct7_i == FUNCT7_ZBB_ROT)) begin
                        // rol (R-type: funct7=0x30, funct3=1)
                        alu_result_o = rol_result;
                    end else begin
                        // Base sll / slli
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
                        // xnor (R-type: funct7=0x20, funct3=4)
                        alu_result_o = ~(alu_in1 ^ alu_in2);
                    end else if (!immediate_sel_i && (funct7_i == FUNCT7_ZBB_MINMAX)) begin
                        // min (R-type: funct7=0x05, funct3=4)
                        alu_result_o = sub_signed[32] ? alu_in1 : alu_in2;
                    end else if (!immediate_sel_i && (funct7_i == FUNCT7_ZBB_PACK)) begin
                        // zext.h (R-type: funct7=0x04, funct3=4, rs2=x0)
                        alu_result_o = {16'h0000, alu_in1[15:0]};
                    end else begin
                        // Base xor / xori
                        alu_result_o = alu_in1 ^ alu_in2;
                    end
                end

                SR: begin
                    if (immediate_sel_i && (imm_i[11:0] == IMM12_REV8)) begin
                        // rev8 (I-type: imm12=0x698, funct3=5)
                        alu_result_o = rev8_result;
                    end else if (immediate_sel_i && (imm_i[11:0] == IMM12_ORCB)) begin
                        // orc.b (I-type: imm12=0x287, funct3=5)
                        alu_result_o = orc_b_result;
                    end else if (funct7_i == FUNCT7_ZBB_ROT) begin
                        // ror (R-type: funct7=0x30, funct3=5) or rori (I-type: funct7=0x30, funct3=5)
                        alu_result_o = ror_result;
                    end else if (!immediate_sel_i && (funct7_i == FUNCT7_ZBB_MINMAX)) begin
                        // minu (R-type: funct7=0x05, funct3=5)
                        alu_result_o = sub_unsigned[32] ? alu_in1 : alu_in2;
                    end else begin
                        // Base srl / srli / sra / srai
                        alu_result_o = arithsubtype_i ? ($signed(alu_in1) >>> alu_in2[4:0]) : (alu_in1 >> alu_in2[4:0]);
                    end
                end

                OR: begin
                    if (!immediate_sel_i && (funct7_i == FUNCT7_ZBB_LOGIC)) begin
                        // orn (R-type: funct7=0x20, funct3=6)
                        alu_result_o = alu_in1 | (~alu_in2);
                    end else if (!immediate_sel_i && (funct7_i == FUNCT7_ZBB_MINMAX)) begin
                        // max (R-type: funct7=0x05, funct3=6)
                        alu_result_o = sub_signed[32] ? alu_in2 : alu_in1;
                    end else begin
                        // Base or / ori
                        alu_result_o = alu_in1 | alu_in2;
                    end
                end

                AND: begin
                    if (!immediate_sel_i && (funct7_i == FUNCT7_ZBB_LOGIC)) begin
                        // andn (R-type: funct7=0x20, funct3=7)
                        alu_result_o = alu_in1 & (~alu_in2);
                    end else if (!immediate_sel_i && (funct7_i == FUNCT7_ZBB_MINMAX)) begin
                        // maxu (R-type: funct7=0x05, funct3=7)
                        alu_result_o = sub_unsigned[32] ? alu_in2 : alu_in1;
                    end else begin
                        // Base and / andi
                        alu_result_o = alu_in1 & alu_in2;
                    end
                end

                default: alu_result_o = 32'h0;
            endcase
        end
    end

endmodule
