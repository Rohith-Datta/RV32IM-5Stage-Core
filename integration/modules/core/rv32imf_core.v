// ============================================================================
// File: rv32imf_core.v
// Module: rv32imf_core
// Description: Top-Level RV32IMF Processor Core Wrapper
// Fully integrates:
//   - RV32I Base Integer Core
//   - RV32M Multiplier & 32-Cycle Restoring Divider
//   - RV32F IEEE 754 Single-Precision Floating-Point Unit
//   - RV32Zbb Bit-Manipulation Extension (All 18 operations)
//   - Feature 5 & 6 Direct-Mapped L1 Instruction & Data Caches
//   - Feature 7 Static 32-Entry Branch Target Buffer (BTB)
//   - Feature 8 Passive Hardware Performance Counters (64-Bit CSRs)
//   - Deadlock-Free Priority Bus Arbiter with D-Cache Priority
// ============================================================================

`timescale 1ns/1ps

module rv32imf_core #(
    parameter RESET_PC = 32'h0000_0000
)(
    input  wire        clk,
    input  wire        reset_n,
    input  wire        stall_ext,

    // Performance & Diagnostic Configuration Switches
    input  wire        use_dsp_i,        // 1: Hardware DSP multiplier, 0: Booth Radix-4
    input  wire        icache_bypass_i,  // 0: L1 I-Cache Active, 1: Bypass
    input  wire        dcache_bypass_i,  // 0: L1 D-Cache Active, 1: Bypass

    // Backing Unified Main Memory Interface (to Unified RAM model)
    output wire        main_mem_req,
    output wire [31:0] main_mem_addr,
    output wire        main_mem_we,
    output wire [31:0] main_mem_wdata,
    output wire [3:0]  main_mem_wstrb,
    input  wire [31:0] main_mem_rdata,

    // Pipeline Monitoring & Commitment Tracing
    output wire [31:0] pc_if,
    output wire [31:0] pc_id,
    output wire [31:0] pc_ex,
    output wire [31:0] pc_mem,
    output wire [31:0] pc_wb,
    output wire        wb_reg_write,
    output wire [4:0]  wb_dest_reg,
    output wire [31:0] wb_data,

    // Status & Diagnostics
    output wire        hazard_stall,
    output wire        btb_pred_hit,
    output wire        btb_pred_taken,
    output wire        btb_mispredict,
    output wire        icache_hit,
    output wire        icache_miss,
    output wire        dcache_hit,
    output wire        dcache_miss,
    output wire        div_busy,
    output wire        fpu_busy,

    // 64-Bit Hardware Performance Counter CSRs (Feature 8)
    output wire [63:0] cycle_count_o,
    output wire [63:0] instret_count_o,
    output wire [63:0] stall_count_o,
    output wire [63:0] branch_count_o,
    output wire [63:0] mispredict_count_o,

    // Memory-Mapped I/O (MMIO) Interface
    input  wire [15:0] sw_i,
    input  wire        uart_tx_busy_i,
    output wire        uart_tx_start_o,
    output wire [7:0]  uart_tx_data_o,
    output wire [31:0] seg7_override_o,
    output wire        demo_complete_o,

    // Architectural Snoop Outputs for Nexys A7 Controller
    output wire        load_use_hazard_o,
    output wire        dcache_miss_busy_o,
    output wire        icache_miss_busy_o,
    output wire        btb_mispredict_flush_o,
    output wire        muldiv_busy_o,
    output wire        wb_reg_commit_o,
    output wire        fpu_exc_nv_o,
    output wire        fpu_exc_dz_o,
    output wire        fpu_exc_of_o,
    output wire        fpu_exc_uf_o,
    output wire        fpu_exc_nx_o,
    output wire        zbb_active_o
);

    pipeline_5stage #(
        .RESET_PC (RESET_PC)
    ) u_pipeline (
        .clk                (clk),
        .reset_n            (reset_n),
        .stall_ext          (stall_ext),
        .use_dsp_i          (use_dsp_i),
        .icache_bypass_i    (icache_bypass_i),
        .dcache_bypass_i    (dcache_bypass_i),
        .main_mem_req       (main_mem_req),
        .main_mem_addr      (main_mem_addr),
        .main_mem_we        (main_mem_we),
        .main_mem_wdata     (main_mem_wdata),
        .main_mem_wstrb     (main_mem_wstrb),
        .main_mem_rdata     (main_mem_rdata),
        .pc_if              (pc_if),
        .pc_id              (pc_id),
        .pc_ex              (pc_ex),
        .pc_mem             (pc_mem),
        .pc_wb              (pc_wb),
        .wb_reg_write       (wb_reg_write),
        .wb_dest_reg        (wb_dest_reg),
        .wb_data            (wb_data),
        .hazard_stall       (hazard_stall),
        .hazard_flush_id    (),
        .hazard_flush_ex    (),
        .forward_a          (),
        .forward_b          (),
        .div_busy           (div_busy),
        .fpu_busy           (fpu_busy),
        .btb_pred_hit       (btb_pred_hit),
        .btb_pred_taken     (btb_pred_taken),
        .btb_mispredict     (btb_mispredict),
        .icache_hit         (icache_hit),
        .icache_miss        (icache_miss),
        .dcache_hit         (dcache_hit),
        .dcache_miss        (dcache_miss),
        .cycle_count_o      (cycle_count_o),
        .instret_count_o    (instret_count_o),
        .stall_count_o      (stall_count_o),
        .branch_count_o     (branch_count_o),
        .mispredict_count_o (mispredict_count_o),
        .sw_i               (sw_i),
        .uart_tx_busy_i     (uart_tx_busy_i),
        .uart_tx_start_o    (uart_tx_start_o),
        .uart_tx_data_o     (uart_tx_data_o),
        .seg7_override_o    (seg7_override_o),
        .demo_complete_o    (demo_complete_o),
        .load_use_hazard_o  (load_use_hazard_o),
        .dcache_miss_busy_o (dcache_miss_busy_o),
        .icache_miss_busy_o (icache_miss_busy_o),
        .btb_mispredict_flush_o (btb_mispredict_flush_o),
        .muldiv_busy_o      (muldiv_busy_o),
        .wb_reg_commit_o    (wb_reg_commit_o),
        .fpu_exc_nv_o       (fpu_exc_nv_o),
        .fpu_exc_dz_o       (fpu_exc_dz_o),
        .fpu_exc_of_o       (fpu_exc_of_o),
        .fpu_exc_uf_o       (fpu_exc_uf_o),
        .fpu_exc_nx_o       (fpu_exc_nx_o),
        .zbb_active_o       (zbb_active_o)
    );

endmodule
