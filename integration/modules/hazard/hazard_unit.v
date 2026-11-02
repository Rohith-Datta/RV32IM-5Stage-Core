// ============================================================================
// File: hazard_unit.v
// Module: hazard_unit
// Description: Fully Integrated Hazard Detection, Data Forwarding & Stall Control Unit
//              Resolves:
//                1. RAW Data Hazards (0-cycle forwarding from EX/MEM and MEM/WB)
//                2. Load-Use Data Hazards (1-cycle bubble stall)
//                3. Multi-Cycle Math Interlocks (Divider 32c, FPU 4-15c)
//                4. L1 D-Cache & L1 I-Cache Miss Stalls (Priority arbitration)
//                5. Control Hazards & BTB Misprediction Recovery Flushes
// ============================================================================

`timescale 1ns/1ps

module hazard_unit (
    // Decode Stage (ID) Register Specifiers & Usage
    input  wire [4:0] id_rs1,
    input  wire [4:0] id_rs2,
    input  wire       id_rs1_used,
    input  wire       id_rs2_used,

    // Execute Stage (ID/EX) Register Specifiers & Flags
    input  wire [4:0] id_ex_rd,
    input  wire       id_ex_mem_read,
    input  wire [4:0] ex_rs1,
    input  wire [4:0] ex_rs2,

    // Memory Stage (EX/MEM) Register Specifiers & Flags
    input  wire [4:0] ex_mem_rd,
    input  wire       ex_mem_reg_write,

    // Writeback Stage (MEM/WB) Register Specifiers & Flags
    input  wire [4:0] mem_wb_rd,
    input  wire       mem_wb_reg_write,

    // Multi-Cycle Execution Units & Cache Miss Status
    input  wire       div_busy,
    input  wire       fpu_busy,
    input  wire       icache_stall,
    input  wire       dcache_stall,

    // Feature 7 BTB Branch Prediction Resolution
    input  wire       mispredict,

    // Forwarding Controls to Execute Stage Multiplexers
    output reg  [1:0] forward_a,
    output reg  [1:0] forward_b,

    // Pipeline Synchronous Stall Enables (Active-High Freeze)
    output wire       stall_if,
    output wire       stall_if_id,
    output wire       stall_id_ex,
    output wire       stall_ex_mem,

    // Pipeline Synchronous Flush Enables (Active-High Bubble Injection)
    output wire       flush_if_id,
    output wire       flush_id_ex,
    output wire       flush_ex_mem,
    output wire       flush_mem_wb
);

    `include "opcode.vh"

    // ------------------------------------------------------------------------
    // 1. Data Forwarding Logic (RAW Hazard Resolution with 0 Cycles Penalty)
    // ------------------------------------------------------------------------
    // Operand A (RS1) Forwarding: EX/MEM has priority over MEM/WB
    always @(*) begin
        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == ex_rs1)) begin
            forward_a = FWD_MEM; // 2'b10
        end else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == ex_rs1)) begin
            forward_a = FWD_WB;  // 2'b01
        end else begin
            forward_a = FWD_NONE;// 2'b00
        end
    end

    // Operand B (RS2) Forwarding: EX/MEM has priority over MEM/WB
    always @(*) begin
        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == ex_rs2)) begin
            forward_b = FWD_MEM; // 2'b10
        end else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == ex_rs2)) begin
            forward_b = FWD_WB;  // 2'b01
        end else begin
            forward_b = FWD_NONE;// 2'b00
        end
    end

    // ------------------------------------------------------------------------
    // 2. Load-Use Data Hazard Detection
    // ------------------------------------------------------------------------
    // If instruction in ID uses rs1 or rs2 which matches destination of a load in EX:
    wire load_use_hazard = id_ex_mem_read && (id_ex_rd != 5'd0) &&
                           ((id_rs1_used && (id_ex_rd == id_rs1)) ||
                            (id_rs2_used && (id_ex_rd == id_rs2)));

    // Combined multi-cycle math stall
    wire math_busy = div_busy || fpu_busy;

    // ------------------------------------------------------------------------
    // 3. Centralized Priority Stall and Flush Generation (Deadlock-Free)
    // ------------------------------------------------------------------------
    // Pipeline freeze hierarchy (highest to lowest priority):
    //   - dcache_stall freezes the entire pipeline up to MEM stage
    //   - math_busy freezes PC, IF/ID, and ID/EX while math calculates
    //   - load_use_hazard freezes PC and IF/ID to allow load to reach MEM
    //   - icache_stall freezes PC and IF/ID input while instruction line refills
    assign stall_if     = dcache_stall || math_busy || load_use_hazard || (icache_stall && !mispredict);
    assign stall_if_id  = dcache_stall || math_busy || load_use_hazard;
    assign stall_id_ex  = dcache_stall || math_busy;
    assign stall_ex_mem = dcache_stall;

    // Pipeline flush / bubble injection hierarchy:
    //   - flushes must NEVER corrupt an in-flight multi-cycle math or cache operation!
    assign flush_if_id  = mispredict && !math_busy && !dcache_stall;
    assign flush_id_ex  = (load_use_hazard || mispredict) && !math_busy && !dcache_stall;
    assign flush_ex_mem = math_busy && !dcache_stall;
    assign flush_mem_wb = dcache_stall;

endmodule
