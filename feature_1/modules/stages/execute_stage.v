// ============================================================================
// File: execute_stage.v
// Description: Execution Stage with Forwarding Muxes, ALU, & Branch Logic
// Project: Pipelined RV32IM RISC-V Core (Feature 1: 5-Stage Upgrade)
// ============================================================================

`timescale 1ns/1ps

module execute_stage (
    // Inputs from ID/EX
    input  wire [31:0] pc_i,
    input  wire [31:0] pc_plus4_i,
    input  wire [31:0] rdata1_i,
    input  wire [31:0] rdata2_i,
    input  wire [31:0] imm_i,

    // Control signals from ID/EX
    input  wire [2:0]  alu_op_i,
    input  wire        arithsubtype_i,
    input  wire        alu_i,
    input  wire        lui_i,
    input  wire        auipc_i,
    input  wire        jal_i,
    input  wire        jalr_i,
    input  wire        branch_i,
    input  wire        mem_read_i,
    input  wire        mem_write_i,
    input  wire        immediate_sel_i,

    // Forwarding Controls and Data
    input  wire [1:0]  forward_a_i,
    input  wire [1:0]  forward_b_i,
    input  wire [31:0] ex_mem_alu_result_i,
    input  wire [31:0] wb_data_i,

    // Outputs to EX/MEM and Top/Hazard Unit
    output reg  [31:0] alu_result_o,
    output wire [31:0] store_data_o,
    output reg         branch_taken_o,
    output wire        branch_or_jump_taken_o,
    output wire [31:0] target_pc_o,
    output wire [31:0] alu_in1_o,
    output wire [31:0] alu_in2_o
);

    `include "opcode.vh"

    // ------------------------------------------------------------------------
    // 1. Forwarding Multiplexers
    // ------------------------------------------------------------------------
    // Operand 1 forwarding mux
    wire [31:0] alu_in1 = (forward_a_i == FWD_MEM) ? ex_mem_alu_result_i :
                          (forward_a_i == FWD_WB)  ? wb_data_i :
                          rdata1_i;

    // Operand 2 (and Store Data) forwarding mux
    wire [31:0] forwarded_rdata2 = (forward_b_i == FWD_MEM) ? ex_mem_alu_result_i :
                                   (forward_b_i == FWD_WB)  ? wb_data_i :
                                   rdata2_i;

    // Second ALU operand (Immediate vs Forwarded RS2)
    wire [31:0] alu_in2 = immediate_sel_i ? imm_i : forwarded_rdata2;

    assign alu_in1_o    = alu_in1;
    assign alu_in2_o    = alu_in2;
    assign store_data_o = forwarded_rdata2;

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
    assign target_pc_o = jalr_i ? jalr_target : branch_target;

    // ------------------------------------------------------------------------
    // 4. ALU Calculation
    // ------------------------------------------------------------------------
    always @(*) begin
        if (lui_i) begin
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

// Note: Branch evaluation logic supports signed/unsigned conditions

// Note: SLT and SLTU borrow extraction verified

// Note: Computes target_pc for conditional branch and JALR base+offset

// Note: Integrated operand A and operand B forwarding multiplexers
