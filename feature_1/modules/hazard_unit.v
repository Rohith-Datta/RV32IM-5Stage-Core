// ============================================================================
// File: hazard_unit.v
// Description: Hazard Detection & Data Forwarding Unit for 5-Stage RV32I Core
// Project: Pipelined RV32IM RISC-V Core (Feature 1: 5-Stage Upgrade)
// ============================================================================

`timescale 1ns/1ps

module hazard_unit (
    // Instruction specifiers from ID stage
    input  wire [4:0]  id_rs1,
    input  wire [4:0]  id_rs2,
    input  wire        id_rs1_used,
    input  wire        id_rs2_used,

    // Instruction specifiers from EX stage
    input  wire [4:0]  id_ex_rs1,
    input  wire [4:0]  id_ex_rs2,
    input  wire [4:0]  id_ex_rd,
    input  wire        id_ex_mem_read,
    input  wire        id_ex_branch,
    input  wire        id_ex_jal,
    input  wire        id_ex_jalr,
    input  wire        ex_branch_taken,

    // Instruction specifiers from MEM stage
    input  wire [4:0]  ex_mem_rd,
    input  wire        ex_mem_reg_write,

    // Instruction specifiers from WB stage
    input  wire [4:0]  mem_wb_rd,
    input  wire        mem_wb_reg_write,

    // Forwarding Control Outputs to EX stage
    output reg  [1:0]  forward_a,
    output reg  [1:0]  forward_b,

    // Pipeline Control Outputs
    output wire        stall_if,
    output wire        stall_if_id,
    output wire        flush_if_id,
    output wire        flush_id_ex
);

    `include "opcode.vh"

    // ------------------------------------------------------------------------
    // 1. Data Forwarding Logic (ALU Operands in EX stage)
    // ------------------------------------------------------------------------
    // Forwarding for Operand A (RS1)
    // Priority: EX/MEM (most recent) > MEM/WB > Register File
    always @(*) begin
        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1)) begin
            forward_a = FWD_MEM; // 2'b10: Forward from EX/MEM stage
        end else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs1)) begin
            forward_a = FWD_WB;  // 2'b01: Forward from MEM/WB stage
        end else begin
            forward_a = FWD_NONE;// 2'b00: No forward (use ID/EX register data)
        end
    end

    // Forwarding for Operand B / Store Data (RS2)
    // Priority: EX/MEM (most recent) > MEM/WB > Register File
    always @(*) begin
        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2)) begin
            forward_b = FWD_MEM; // 2'b10: Forward from EX/MEM stage
        end else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs2)) begin
            forward_b = FWD_WB;  // 2'b01: Forward from MEM/WB stage
        end else begin
            forward_b = FWD_NONE;// 2'b00: No forward (use ID/EX register data)
        end
    end

    // ------------------------------------------------------------------------
    // 2. Load-Use Hazard Detection
    // ------------------------------------------------------------------------
    // Condition: Instruction in EX is a load (mem_read), and its destination
    // register is needed by the instruction currently in ID stage.
    wire load_use_hazard = id_ex_mem_read && (id_ex_rd != 5'd0) &&
                           ((id_rs1_used && (id_ex_rd == id_rs1)) ||
                            (id_rs2_used && (id_ex_rd == id_rs2)));

    // ------------------------------------------------------------------------
    // 3. Control Hazard Detection (Branch & Jump Resolution in EX)
    // ------------------------------------------------------------------------
    wire branch_or_jump_taken = (id_ex_branch && ex_branch_taken) || id_ex_jal || id_ex_jalr;

    // ------------------------------------------------------------------------
    // 4. Pipeline Stall and Flush Generation
    // ------------------------------------------------------------------------
    // On load-use hazard: freeze PC and IF/ID, insert 1 bubble cycle into ID/EX
    // On branch/jump: flush IF/ID and ID/EX (2-cycle penalty)
    assign stall_if    = load_use_hazard && !branch_or_jump_taken;
    assign stall_if_id = load_use_hazard && !branch_or_jump_taken;
    assign flush_if_id = branch_or_jump_taken;
    assign flush_id_ex = branch_or_jump_taken || load_use_hazard;

endmodule

// Note: Added EX hazard forwarding logic with x0 hardwire check

// Note: Added MEM hazard forwarding prioritizing younger EX/MEM instruction
