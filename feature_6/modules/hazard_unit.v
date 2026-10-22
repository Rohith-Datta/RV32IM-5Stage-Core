// ============================================================================
// File: hazard_unit.v
// Description: Centralized Hazard Detection, Forwarding, & Multi-Cycle Stall Unit
// Project: Pipelined RV32IMF RISC-V Core (Feature 6: L1 Harvard Caches)
// Supports:
//   - EX/MEM and MEM/WB Data Forwarding
//   - Load-Use Hazard Interlock
//   - Branch/Jump Control Hazard Flushing (with I-Cache flush)
//   - Multi-Cycle Math Interlocks (32-Cycle Divider & Multi-Cycle FPU)
//   - 10-Cycle L1 I-Cache Read Miss Stall
//   - 10-Cycle L1 D-Cache Read Miss Stall
// ============================================================================

`timescale 1ns/1ps

module hazard_unit (
    // Instruction specifiers from ID stage
    input  wire [4:0]  id_rs1,
    input  wire [4:0]  id_rs2,
    input  wire        id_rs1_used,
    input  wire        id_rs2_used,

    // Instruction specifiers & flags from EX stage
    input  wire [4:0]  id_ex_rs1,
    input  wire [4:0]  id_ex_rs2,
    input  wire [4:0]  id_ex_rd,
    input  wire        id_ex_mem_read,
    input  wire        id_ex_branch,
    input  wire        id_ex_jal,
    input  wire        id_ex_jalr,
    input  wire        ex_branch_taken,
    input  wire        div_busy,
    input  wire        fpu_busy,

    // Instruction specifiers from MEM stage
    input  wire [4:0]  ex_mem_rd,
    input  wire        ex_mem_reg_write,

    // Instruction specifiers from WB stage
    input  wire [4:0]  mem_wb_rd,
    input  wire        mem_wb_reg_write,

    // Cache stall inputs
    input  wire        icache_stall_i,  // Feature 6: L1 I-Cache Stall
    input  wire        dcache_stall_i,  // Feature 5/6: L1 D-Cache Stall

    // Forwarding Control Outputs to EX stage
    output reg  [1:0]  forward_a,
    output reg  [1:0]  forward_b,

    // Pipeline Control Outputs
    output wire        stall_if,
    output wire        stall_if_id,
    output wire        stall_id_ex,
    output wire        stall_ex_mem,
    output wire        flush_if_id,
    output wire        flush_id_ex,
    output wire        flush_ex_mem,
    output wire        flush_mem_wb
);

    `include "opcode.vh"

    // ------------------------------------------------------------------------
    // 1. Data Forwarding Logic (ALU Operands in EX stage)
    // ------------------------------------------------------------------------
    // Forwarding for Operand A (RS1)
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
    // 3. Multi-Cycle Math Engine Busy (Hardware Divider or FPU)
    // ------------------------------------------------------------------------
    wire math_busy = div_busy || fpu_busy;

    // ------------------------------------------------------------------------
    // 4. Control Hazard Detection (Branch & Jump Resolution in EX)
    // ------------------------------------------------------------------------
    wire branch_or_jump_taken = (id_ex_branch && ex_branch_taken) || id_ex_jal || id_ex_jalr;

    // ------------------------------------------------------------------------
    // 5. Centralized Pipeline Stall and Flush Generation
    // ------------------------------------------------------------------------
    // Priority:
    // 1. D-Cache miss (MEM stage) freezes all upstream stages (PC, IF/ID, ID/EX, EX/MEM)
    //    and flushes MEM/WB so WB executes a bubble until data is ready.
    // 2. Math busy (EX stage DIV or FPU) freezes PC, IF/ID, ID/EX and injects bubble into EX/MEM.
    // 3. I-Cache miss (IF stage) freezes PC only; IF/ID captures NOP and downstream drains naturally.
    //    If branch/jump redirects PC in EX, PC updates to branch target immediately.
    // 4. Load-use hazard freezes PC and IF/ID, injecting bubble into ID/EX.
    // 5. Branch/Jump flushes IF/ID and ID/EX (2-cycle branch penalty).

    assign stall_if     = dcache_stall_i || math_busy ||
                          (!branch_or_jump_taken && (icache_stall_i || load_use_hazard));
    assign stall_if_id  = dcache_stall_i || math_busy || (load_use_hazard && !branch_or_jump_taken);
    assign stall_id_ex  = dcache_stall_i || math_busy;
    assign stall_ex_mem = dcache_stall_i;

    assign flush_if_id  = !dcache_stall_i && !math_busy && branch_or_jump_taken;
    assign flush_id_ex  = !dcache_stall_i && !math_busy && (branch_or_jump_taken || load_use_hazard);
    assign flush_ex_mem = !dcache_stall_i && math_busy;
    assign flush_mem_wb = dcache_stall_i;

endmodule
