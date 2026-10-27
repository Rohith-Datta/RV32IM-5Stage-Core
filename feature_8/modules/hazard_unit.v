// ============================================================================
// File: hazard_unit.v
// Module: hazard_unit (Feature 7: BTB Branch Prediction Aware)
// Description: Hazard Detection & Data Forwarding Unit for 5-Stage RV32IMF Core
// Supports:
//   - Data forwarding to ALU/Multiplier/Divider/FPU operands (MEM->EX, WB->EX)
//   - Load-use hazard detection and 1-cycle pipeline bubble insertion
//   - Multi-cycle divider pipeline stall interlock (div_busy)
//   - Multi-cycle FPU pipeline stall interlock (fpu_busy)
//   - BTB Misprediction Recovery: Flushes IF/ID and ID/EX ONLY on mispredictions
//     (Correctly predicted branches have ZERO penalty cycles!)
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
    input  wire        div_busy,        // Multi-cycle divider interlock stall
    input  wire        fpu_busy,        // Multi-cycle FPU interlock stall

    // Feature 7 BTB Misprediction Input
    input  wire        mispredict,      // 1 if actual branch != predicted branch

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
    output wire        stall_id_ex,
    output wire        flush_if_id,
    output wire        flush_id_ex,
    output wire        flush_ex_mem
);

    `include "opcode.vh"

    // ------------------------------------------------------------------------
    // 1. Data Forwarding Logic (ALU/Mul/Div/FPU Operands in EX stage)
    // ------------------------------------------------------------------------
    always @(*) begin
        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1)) begin
            forward_a = FWD_MEM; // 2'b10: Forward from EX/MEM stage
        end else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs1)) begin
            forward_a = FWD_WB;  // 2'b01: Forward from MEM/WB stage
        end else begin
            forward_a = FWD_NONE;// 2'b00: No forward (use ID/EX register data)
        end
    end

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
    wire load_use_hazard = id_ex_mem_read && (id_ex_rd != 5'd0) &&
                           ((id_rs1_used && (id_ex_rd == id_rs1)) ||
                            (id_rs2_used && (id_ex_rd == id_rs2)));

    // ------------------------------------------------------------------------
    // 3. Multi-Cycle Arithmetic Hold (Divider & FPU)
    // ------------------------------------------------------------------------
    wire math_busy = div_busy || fpu_busy;

    // ------------------------------------------------------------------------
    // 4. Pipeline Stall and Flush Generation with BTB Branch Prediction
    // ------------------------------------------------------------------------
    // - On load-use hazard: freeze PC and IF/ID, insert bubble into ID/EX
    // - On math_busy: freeze PC, IF/ID, and ID/EX; insert bubble into EX/MEM
    // - On branch: Flush ONLY if mispredict is asserted!
    assign stall_if     = load_use_hazard || math_busy;
    assign stall_if_id  = load_use_hazard || math_busy;
    assign stall_id_ex  = math_busy;

    // Flushes on misprediction:
    assign flush_if_id  = mispredict && !math_busy;
    assign flush_id_ex  = (load_use_hazard || mispredict) && !math_busy;
    assign flush_ex_mem = math_busy;

endmodule
