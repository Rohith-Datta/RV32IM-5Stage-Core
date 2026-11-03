// ============================================================================
// File: pipeline_5stage.v
// Module: pipeline_5stage
// Description: Fully Integrated 5-Stage RV32IMF Processor Core Datapath
// Integrated Features:
//   - Feature 1: 5-Stage Pipeline Registers & Hazard Unit with Data Forwarding
//   - Feature 2: Hardware Multiplier (RV32M DSP48E1 / Booth Radix-4)
//   - Feature 3: 32-Cycle Radix-2 Hardware Divider & Remainder Unit (RV32M)
//   - Feature 4: IEEE 754 Single-Precision Floating-Point Unit (RV32F)
//   - Feature 5: Direct-Mapped 2 KB L1 Data Cache (Write-Through, No-Write-Allocate)
//   - Feature 6: Direct-Mapped 2 KB L1 Instruction Cache (Burst Refill)
//   - Feature 7: Static 32-Entry Direct-Mapped Branch Target Buffer (BTB)
//   - Feature 8: Passive Hardware Performance CSR Counters (64-bit cycle/instret/stalls)
//   - Feature 9: RISC-V Zbb Bit-Manipulation Extension (All 18 operations, 1-cycle)
//   - Memory Bus Arbiter: Strict D-Cache priority over I-Cache, Deadlock-Free
// ============================================================================

`timescale 1ns/1ps

module pipeline_5stage #(
    parameter RESET_PC = 32'h0000_0000
)(
    input  wire        clk,
    input  wire        reset_n,
    input  wire        stall_ext,        // External freeze (debug / testbench)
    input  wire        use_dsp_i,        // 1: DSP48E1, 0: Booth Radix-4

    // Cache Bypass Controls
    input  wire        icache_bypass_i,  // 0 = Normal L1 I-Cache, 1 = Bypass
    input  wire        dcache_bypass_i,  // 0 = Normal L1 D-Cache, 1 = Bypass

    // Unified Backing Main Memory Interface (from Memory Bus Arbiter)
    output wire        main_mem_req,
    output wire [31:0] main_mem_addr,
    output wire        main_mem_we,
    output wire [31:0] main_mem_wdata,
    output wire [3:0]  main_mem_wstrb,
    input  wire [31:0] main_mem_rdata,

    // Diagnostic Pipeline Observability Outputs
    output wire [31:0] pc_if,
    output wire [31:0] pc_id,
    output wire [31:0] pc_ex,
    output wire [31:0] pc_mem,
    output wire [31:0] pc_wb,
    output wire        wb_reg_write,
    output wire [4:0]  wb_dest_reg,
    output wire [31:0] wb_data,

    // Performance & Unit Status Signals
    output wire        hazard_stall,
    output wire        hazard_flush_id,
    output wire        hazard_flush_ex,
    output wire [1:0]  forward_a,
    output wire [1:0]  forward_b,
    output wire        div_busy,
    output wire        fpu_busy,
    output wire        btb_pred_hit,
    output wire        btb_pred_taken,
    output wire        btb_mispredict,
    output wire        icache_hit,
    output wire        icache_miss,
    output wire        dcache_hit,
    output wire        dcache_miss,

    // 64-bit Hardware Telemetry Outputs (from Feature 8 CSR unit)
    output wire [63:0] cycle_count_o,
    output wire [63:0] instret_count_o,
    output wire [63:0] stall_count_o,
    output wire [63:0] branch_count_o,
    output wire [63:0] mispredict_count_o,

    // Memory-Mapped I/O (MMIO) Interface
    input  wire [15:0] sw_i,
    input  wire        uart_tx_busy_i,
    output reg         uart_tx_start_o,
    output reg  [7:0]  uart_tx_data_o,
    output reg  [31:0] seg7_override_o,
    output reg         demo_complete_o,

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

    `include "opcode.vh"

    // ------------------------------------------------------------------------
    // Pipeline Interconnect Wires
    // ------------------------------------------------------------------------
    wire        stall_if;
    wire        stall_if_id;
    wire        stall_id_ex;
    wire        stall_ex_mem;
    wire        flush_if_id;
    wire        flush_id_ex;
    wire        flush_ex_mem;
    wire        flush_mem_wb;

    wire        icache_stall;
    wire        dcache_stall;
    wire        div_busy_wire;
    wire        fpu_busy_wire;

    assign div_busy = div_busy_wire;
    assign fpu_busy = fpu_busy_wire;

    assign hazard_stall    = stall_if || stall_id_ex || stall_ex_mem;
    assign hazard_flush_id = flush_if_id;
    assign hazard_flush_ex = flush_id_ex;

    // Feature 7 BTB Interconnects
    wire        ex_mispredict;
    wire [31:0] ex_redirect_pc;
    wire        ex_btb_update_en;
    wire        ex_btb_update_taken;
    wire [31:0] ex_btb_update_pc;
    wire [31:0] ex_btb_update_target;

    assign btb_mispredict = ex_mispredict;

    // ========================================================================
    // 1. INSTRUCTION FETCH (IF) STAGE & L1 I-CACHE
    // ========================================================================
    wire [31:0] if_pc;
    wire [31:0] if_pc_plus4;
    wire [31:0] if_instruction;
    wire        if_pred_hit;
    wire        if_pred_taken;
    wire [31:0] if_pred_target;

    wire [31:0] icache_cpu_addr;
    wire [31:0] icache_cpu_rdata;
    wire [31:0] icache_mem_addr;
    wire [31:0] icache_mem_rdata;
    wire        icache_mem_req;
    wire        icache_mem_grant;

    fetch_stage u_fetch_stage (
        .clk               (clk),
        .reset_n           (reset_n),
        .stall_if          (stall_if || stall_ext),
        .ex_mispredict     (ex_mispredict),
        .ex_redirect_pc    (ex_redirect_pc),
        .btb_update_en     (ex_btb_update_en),
        .btb_update_pc     (ex_btb_update_pc),
        .btb_update_target (ex_btb_update_target),
        .btb_update_taken  (ex_btb_update_taken),
        .icache_fetch_addr (icache_cpu_addr),
        .icache_rdata      (icache_cpu_rdata),
        .pc_o              (if_pc),
        .pc_plus4_o        (if_pc_plus4),
        .instruction_o     (if_instruction),
        .pred_hit_o        (if_pred_hit),
        .pred_taken_o      (if_pred_taken),
        .pred_target_o     (if_pred_target)
    );

    assign pc_if          = if_pc;
    assign btb_pred_hit   = if_pred_hit;
    assign btb_pred_taken = if_pred_taken;

    wire icache_miss_pulse;
    wire dcache_miss_pulse;

    // Direct-Mapped 2 KB L1 Instruction Cache
    icache_controller #(
        .NUM_LINES      (128),
        .WORDS_PER_LINE (4),
        .ADDR_WIDTH     (32),
        .TAG_WIDTH      (21),
        .INDEX_WIDTH    (7),
        .OFFSET_WIDTH   (2)
    ) u_icache (
        .clk             (clk),
        .reset_n         (reset_n),
        .flush_i         (ex_mispredict),
        .counter_reset_i (1'b0),
        .cache_bypass_i  (icache_bypass_i),
        .cpu_addr        (icache_cpu_addr),
        .cpu_rdata       (icache_cpu_rdata),
        .icache_stall    (icache_stall),
        .mem_addr        (icache_mem_addr),
        .mem_rdata       (icache_mem_rdata),
        .mem_req         (icache_mem_req),
        .mem_grant       (icache_mem_grant),
        .cache_hit       (icache_hit),
        .cache_miss      (icache_miss),
        .miss_pulse_o    (icache_miss_pulse),
        .hit_count       (),
        .miss_count      (),
        .state_o         (),
        .refill_cnt_o    (),
        .latched_pc_o    (),
        .just_refilled_o ()
    );

    // ========================================================================
    // IF/ID PIPELINE REGISTER
    // ========================================================================
    wire        if_valid = reset_n && !icache_stall;
    wire        id_valid;
    wire [31:0] id_pc;
    wire [31:0] id_pc_plus4;
    wire [31:0] id_instruction;
    wire        id_pred_hit;
    wire        id_pred_taken;
    wire [31:0] id_pred_target;

    if_id_reg u_if_id_reg (
        .clk           (clk),
        .reset_n       (reset_n),
        .stall         (stall_if_id || stall_ext),
        .flush         (flush_if_id),
        .valid_i       (if_valid),
        .pc_i          (if_pc),
        .pc_plus4_i    (if_pc_plus4),
        .instruction_i (if_instruction),
        .pred_hit_i    (if_pred_hit),
        .pred_taken_i  (if_pred_taken),
        .pred_target_i (if_pred_target),
        .valid_o       (id_valid),
        .pc_o          (id_pc),
        .pc_plus4_o    (id_pc_plus4),
        .instruction_o (id_instruction),
        .pred_hit_o    (id_pred_hit),
        .pred_taken_o  (id_pred_taken),
        .pred_target_o (id_pred_target)
    );

    assign pc_id = id_pc;

    // ========================================================================
    // 2. INSTRUCTION DECODE (ID) STAGE & REGISTER FILE
    // ========================================================================
    wire [2:0]  id_alu_op;
    wire        id_arithsubtype;
    wire        id_alu;
    wire        id_lui;
    wire        id_auipc;
    wire        id_jal;
    wire        id_jalr;
    wire        id_branch;
    wire        id_mem_read;
    wire        id_mem_write;
    wire        id_mem_to_reg;
    wire        id_reg_write;
    wire        id_immediate_sel;
    wire        id_is_mul;
    wire        id_is_div;
    wire        id_is_fpu;
    wire        id_is_csr;
    wire [11:0] id_csr_addr;
    wire        id_illegal_inst;
    wire [31:0] id_rdata1;
    wire [31:0] id_rdata2;
    wire [31:0] id_imm;
    wire [4:0]  id_rs1;
    wire [4:0]  id_rs2;
    wire [4:0]  id_rd;
    wire [2:0]  id_funct3;
    wire [6:0]  id_funct7;
    wire        id_rs1_used;
    wire        id_rs2_used;
    wire        id_is_fp_dest;
    wire        id_rs1_is_fp;
    wire        id_rs2_is_fp;
    wire        wb_is_fp_dest;

    decode_stage u_decode_stage (
        .clk             (clk),
        .reset_n         (reset_n),
        .instruction_i   (id_instruction),
        .pc_i            (id_pc),
        .wb_reg_write_i  (wb_reg_write),
        .wb_fp_reg_write_i(wb_reg_write && wb_is_fp_dest),
        .wb_dest_reg_i   (wb_dest_reg),
        .wb_data_i       (wb_data),
        .alu_op_o        (id_alu_op),
        .arithsubtype_o  (id_arithsubtype),
        .alu_o           (id_alu),
        .lui_o           (id_lui),
        .auipc_o         (id_auipc),
        .jal_o           (id_jal),
        .jalr_o          (id_jalr),
        .branch_o        (id_branch),
        .mem_read_o      (id_mem_read),
        .mem_write_o     (id_mem_write),
        .mem_to_reg_o    (id_mem_to_reg),
        .reg_write_o     (id_reg_write),
        .immediate_sel_o (id_immediate_sel),
        .is_mul_o        (id_is_mul),
        .is_div_o        (id_is_div),
        .is_fpu_o        (id_is_fpu),
        .is_csr_o        (id_is_csr),
        .csr_addr_o      (id_csr_addr),
        .illegal_inst_o  (id_illegal_inst),
        .rdata1_o        (id_rdata1),
        .rdata2_o        (id_rdata2),
        .imm_o           (id_imm),
        .rs1_o           (id_rs1),
        .rs2_o           (id_rs2),
        .rd_o            (id_rd),
        .funct3_o        (id_funct3),
        .funct7_o        (id_funct7),
        .id_rs1_used_o   (id_rs1_used),
        .id_rs2_used_o   (id_rs2_used),
        .is_fp_dest_o    (id_is_fp_dest),
        .rs1_is_fp_o     (id_rs1_is_fp),
        .rs2_is_fp_o     (id_rs2_is_fp)
    );

    // ========================================================================
    // ID/EX PIPELINE REGISTER
    // ========================================================================
    wire [31:0] ex_pc;
    wire [31:0] ex_pc_plus4;
    wire [2:0]  ex_alu_op;
    wire        ex_arithsubtype;
    wire        ex_alu;
    wire        ex_lui;
    wire        ex_auipc;
    wire        ex_jal;
    wire        ex_jalr;
    wire        ex_branch;
    wire        ex_mem_read;
    wire        ex_mem_write;
    wire        ex_mem_to_reg;
    wire        ex_reg_write;
    wire        ex_immediate_sel;
    wire        ex_is_mul;
    wire        ex_is_div;
    wire        ex_is_fpu;
    wire        ex_is_csr;
    wire [11:0] ex_csr_addr;
    wire        ex_use_dsp;
    wire [6:0]  ex_funct7;
    wire [31:0] ex_rdata1;
    wire [31:0] ex_rdata2;
    wire [31:0] ex_imm;
    wire        ex_valid;
    wire [4:0]  ex_rs1;
    wire [4:0]  ex_rs2;
    wire [4:0]  ex_rd;
    wire        ex_pred_taken;
    wire [31:0] ex_pred_target;
    wire        ex_is_fp_dest;
    wire        ex_rs1_is_fp;
    wire        ex_rs2_is_fp;

    id_ex_reg u_id_ex_reg (
        .clk             (clk),
        .reset_n         (reset_n),
        .stall           (stall_id_ex || stall_ext),
        .flush           (flush_id_ex),
        .valid_i         (id_valid),
        .pc_i            (id_pc),
        .pc_plus4_i      (id_pc_plus4),
        .alu_op_i        (id_alu_op),
        .arithsubtype_i  (id_arithsubtype),
        .alu_i           (id_alu),
        .lui_i           (id_lui),
        .auipc_i         (id_auipc),
        .jal_i           (id_jal),
        .jalr_i          (id_jalr),
        .branch_i        (id_branch),
        .mem_read_i      (id_mem_read),
        .mem_write_i     (id_mem_write),
        .mem_to_reg_i    (id_mem_to_reg),
        .reg_write_i     (id_reg_write),
        .immediate_sel_i (id_immediate_sel),
        .is_mul_i        (id_is_mul),
        .is_div_i        (id_is_div),
        .is_fpu_i        (id_is_fpu),
        .is_csr_i        (id_is_csr),
        .csr_addr_i      (id_csr_addr),
        .use_dsp_i       (use_dsp_i),
        .funct7_i        (id_funct7),
        .rdata1_i        (id_rdata1),
        .rdata2_i        (id_rdata2),
        .imm_i           (id_imm),
        .rs1_i           (id_rs1),
        .rs2_i           (id_rs2),
        .rd_i            (id_rd),
        .pred_taken_i    (id_pred_taken),
        .pred_target_i   (id_pred_target),
        .is_fp_dest_i    (id_is_fp_dest),
        .rs1_is_fp_i     (id_rs1_is_fp),
        .rs2_is_fp_i     (id_rs2_is_fp),
        .valid_o         (ex_valid),
        .pc_o            (ex_pc),
        .pc_plus4_o      (ex_pc_plus4),
        .alu_op_o        (ex_alu_op),
        .arithsubtype_o  (ex_arithsubtype),
        .alu_o           (ex_alu),
        .lui_o           (ex_lui),
        .auipc_o         (ex_auipc),
        .jal_o           (ex_jal),
        .jalr_o          (ex_jalr),
        .branch_o        (ex_branch),
        .mem_read_o      (ex_mem_read),
        .mem_write_o     (ex_mem_write),
        .mem_to_reg_o    (ex_mem_to_reg),
        .reg_write_o     (ex_reg_write),
        .immediate_sel_o (ex_immediate_sel),
        .is_mul_o        (ex_is_mul),
        .is_div_o        (ex_is_div),
        .is_fpu_o        (ex_is_fpu),
        .is_csr_o        (ex_is_csr),
        .csr_addr_o      (ex_csr_addr),
        .use_dsp_o       (ex_use_dsp),
        .funct7_o        (ex_funct7),
        .rdata1_o        (ex_rdata1),
        .rdata2_o        (ex_rdata2),
        .imm_o           (ex_imm),
        .rs1_o           (ex_rs1),
        .rs2_o           (ex_rs2),
        .rd_o            (ex_rd),
        .pred_taken_o    (ex_pred_taken),
        .pred_target_o   (ex_pred_target),
        .is_fp_dest_o    (ex_is_fp_dest),
        .rs1_is_fp_o     (ex_rs1_is_fp),
        .rs2_is_fp_o     (ex_rs2_is_fp)
    );

    assign pc_ex = ex_pc;

    // ========================================================================
    // 3. EXECUTE (EX) STAGE & CSR PERFORMANCE COUNTER UNIT
    // ========================================================================
    wire [31:0] ex_alu_result;
    wire [31:0] ex_mem_wdata;
    wire [31:0] ex_target_pc;
    wire        ex_branch_taken;
    wire        ex_branch_or_jump_taken;
    wire [31:0] mem_alu_result;
    wire [31:0] csr_rdata_wire;

    wire [31:0] mem_forward_data;
    execute_stage u_execute_stage (
        .clk                    (clk),
        .reset_n                (reset_n),
        .pc_i                   (ex_pc),
        .pc_plus4_i             (ex_pc_plus4),
        .rdata1_i               (ex_rdata1),
        .rdata2_i               (ex_rdata2),
        .imm_i                  (ex_imm),
        .ex_mem_data_i          (mem_forward_data),
        .mem_wb_data_i          (wb_data),
        .forward_a_i            (forward_a),
        .forward_b_i            (forward_b),
        .alu_op_i               (ex_alu_op),
        .arithsubtype_i         (ex_arithsubtype),
        .lui_i                  (ex_lui),
        .auipc_i                (ex_auipc),
        .jal_i                  (ex_jal),
        .jalr_i                 (ex_jalr),
        .branch_i               (ex_branch),
        .mem_read_i             (ex_mem_read),
        .mem_write_i            (ex_mem_write),
        .immediate_sel_i        (ex_immediate_sel),
        .is_mul_i               (ex_is_mul),
        .is_div_i               (ex_is_div),
        .is_fpu_i               (ex_is_fpu),
        .is_csr_i               (ex_is_csr),
        .funct7_i               (ex_funct7),
        .use_dsp_i              (ex_use_dsp),
        .csr_rdata_i            (csr_rdata_wire),
        .pred_taken_i           (ex_pred_taken),
        .pred_target_i          (ex_pred_target),
        .alu_result_o           (ex_alu_result),
        .mem_wdata_o            (ex_mem_wdata),
        .target_pc_o            (ex_target_pc),
        .branch_taken_o         (ex_branch_taken),
        .branch_or_jump_taken_o (ex_branch_or_jump_taken),
        .div_busy_o             (div_busy_wire),
        .fpu_busy_o             (fpu_busy_wire),
        .mispredict_o           (ex_mispredict),
        .redirect_pc_o          (ex_redirect_pc),
        .btb_update_en_o        (ex_btb_update_en),
        .btb_update_taken_o     (ex_btb_update_taken),
        .btb_update_pc_o        (ex_btb_update_pc),
        .btb_update_target_o    (ex_btb_update_target),
        .zbb_active_o           (zbb_active_o),
        .fpu_exc_nv_o           (fpu_exc_nv_o),
        .fpu_exc_dz_o           (fpu_exc_dz_o),
        .fpu_exc_of_o           (fpu_exc_of_o),
        .fpu_exc_uf_o           (fpu_exc_uf_o),
        .fpu_exc_nx_o           (fpu_exc_nx_o)
    );

    wire mem_valid;
    wire wb_valid;

    // Feature 8 Passive Hardware Performance Counters
    csr_perf_counters u_csr_perf (
        .clk                (clk),
        .reset_n            (reset_n),
        .stall_cycle        (hazard_stall),
        .inst_retired       (wb_valid && !stall_ext),
        .branch_exec        (ex_valid && ex_btb_update_en && !stall_id_ex),
        .branch_mispredict  (ex_valid && ex_mispredict && !stall_id_ex),
        .icache_miss        (icache_miss_pulse),
        .dcache_miss        (dcache_miss_pulse),
        .csr_addr           (ex_csr_addr),
        .csr_rdata          (csr_rdata_wire),
        .cycle_count_o      (cycle_count_o),
        .instret_count_o    (instret_count_o),
        .stall_count_o      (stall_count_o),
        .branch_count_o     (branch_count_o),
        .mispredict_count_o (mispredict_count_o)
    );

    // ========================================================================
    // EX/MEM PIPELINE REGISTER
    // ========================================================================
    wire [31:0] mem_pc;
    wire [31:0] mem_pc_plus4;
    wire [31:0] mem_store_data;
    wire [4:0]  mem_rd;
    wire [2:0]  mem_funct3;
    wire        mem_mem_read;
    wire        mem_mem_write;
    wire        mem_mem_to_reg;
    wire        mem_reg_write;
    wire        mem_is_fp_dest;

    ex_mem_reg u_ex_mem_reg (
        .clk          (clk),
        .reset_n      (reset_n),
        .stall        (stall_ex_mem || stall_ext),
        .flush        (flush_ex_mem),
        .valid_i      (ex_valid),
        .pc_i         (ex_pc),
        .pc_plus4_i   (ex_pc_plus4),
        .alu_result_i (ex_alu_result),
        .mem_wdata_i  (ex_mem_wdata),
        .rd_i         (ex_rd),
        .funct3_i     (ex_alu_op),
        .mem_read_i   (ex_mem_read),
        .mem_write_i  (ex_mem_write),
        .mem_to_reg_i (ex_mem_to_reg),
        .reg_write_i  (ex_reg_write),
        .is_fp_dest_i (ex_is_fp_dest),
        .valid_o      (mem_valid),
        .pc_o         (mem_pc),
        .pc_plus4_o   (mem_pc_plus4),
        .alu_result_o (mem_alu_result),
        .mem_wdata_o  (mem_store_data),
        .rd_o         (mem_rd),
        .funct3_o     (mem_funct3),
        .mem_read_o   (mem_mem_read),
        .mem_write_o  (mem_mem_write),
        .mem_to_reg_o (mem_mem_to_reg),
        .reg_write_o  (mem_reg_write),
        .is_fp_dest_o (mem_is_fp_dest)
    );

    assign pc_mem = mem_pc;

    // ========================================================================
    // 4. MEMORY (MEM) STAGE & L1 D-CACHE
    // ========================================================================
    wire [31:0] dmem_stage_addr;
    wire [31:0] dmem_stage_wdata;
    wire [3:0]  dmem_stage_wstrb;
    wire        dmem_stage_we;
    wire        dmem_stage_re;

    memory_stage u_memory_stage (
        .mem_read_i   (mem_mem_read),
        .mem_write_i  (mem_mem_write),
        .funct3_i     (mem_funct3),
        .alu_result_i (mem_alu_result),
        .store_data_i (mem_store_data),
        .dmem_addr_o  (dmem_stage_addr),
        .dmem_wdata_o (dmem_stage_wdata),
        .dmem_wstrb_o (dmem_stage_wstrb),
        .dmem_we_o    (dmem_stage_we),
        .dmem_re_o    (dmem_stage_re)
    );

    // ------------------------------------------------------------------------
    // Memory-Mapped I/O (MMIO) Registers & Logic (0x80000000 - 0x8000000C)
    // ------------------------------------------------------------------------
    wire is_mmio = dmem_stage_addr[31];
    reg [31:0] mmio_rdata;

    always @(*) begin
        case (dmem_stage_addr[3:0])
            4'h0:    mmio_rdata = {16'h0000, sw_i};
            4'h4:    mmio_rdata = {uart_tx_busy_i, 31'b0};
            4'h8:    mmio_rdata = seg7_override_o;
            4'hC:    mmio_rdata = {31'b0, demo_complete_o};
            default: mmio_rdata = 32'h0000_0000;
        endcase
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            uart_tx_start_o <= 1'b0;
            uart_tx_data_o  <= 8'h00;
            seg7_override_o <= 32'h0000_0000;
            demo_complete_o <= 1'b0;
        end else begin
            uart_tx_start_o <= 1'b0; // 1-cycle strobe
            if (is_mmio && dmem_stage_we) begin
                case (dmem_stage_addr[3:0])
                    4'h4: begin
                        uart_tx_start_o <= 1'b1;
                        uart_tx_data_o  <= dmem_stage_wdata[7:0];
                    end
                    4'h8: seg7_override_o <= dmem_stage_wdata;
                    4'hC: demo_complete_o <= dmem_stage_wdata[0];
                endcase
            end
        end
    end

    wire [31:0] dcache_cpu_rdata;
    wire [31:0] dcache_mem_addr;
    wire [31:0] dcache_mem_rdata;
    wire [31:0] dcache_mem_wdata;
    wire [3:0]  dcache_mem_wstrb;
    wire        dcache_mem_we;
    wire        dcache_mem_req;
    wire        dcache_mem_grant;

    dcache_controller #(
        .NUM_LINES      (128),
        .WORDS_PER_LINE (4),
        .ADDR_WIDTH     (32),
        .TAG_WIDTH      (21),
        .INDEX_WIDTH    (7),
        .OFFSET_WIDTH   (2)
    ) u_dcache (
        .clk             (clk),
        .reset_n         (reset_n),
        .counter_reset_i (1'b0),
        .cache_bypass_i  (dcache_bypass_i),
        .cpu_addr        (dmem_stage_addr),
        .cpu_wdata       (dmem_stage_wdata),
        .cpu_wstrb       (dmem_stage_wstrb),
        .cpu_we          (dmem_stage_we && !is_mmio),
        .cpu_re          (dmem_stage_re && !is_mmio),
        .cpu_rdata       (dcache_cpu_rdata),
        .dcache_stall    (dcache_stall),
        .mem_addr        (dcache_mem_addr),
        .mem_rdata       (dcache_mem_rdata),
        .mem_wdata       (dcache_mem_wdata),
        .mem_wstrb       (dcache_mem_wstrb),
        .mem_we          (dcache_mem_we),
        .mem_req         (dcache_mem_req),
        .mem_grant       (dcache_mem_grant),
        .cache_hit       (dcache_hit),
        .cache_miss      (dcache_miss),
        .miss_pulse_o    (dcache_miss_pulse),
        .hit_count       (),
        .miss_count      ()
    );

    // ========================================================================
    // MEMORY BUS ARBITER (D-Cache Priority over I-Cache)
    // ========================================================================
    mem_bus_arbiter u_bus_arbiter (
        .clk            (clk),
        .reset_n        (reset_n),
        .icache_req     (icache_mem_req),
        .icache_addr    (icache_mem_addr),
        .icache_rdata   (icache_mem_rdata),
        .icache_grant   (icache_mem_grant),
        .dcache_req     (dcache_mem_req),
        .dcache_we      (dcache_mem_we),
        .dcache_addr    (dcache_mem_addr),
        .dcache_wdata   (dcache_mem_wdata),
        .dcache_wstrb   (dcache_mem_wstrb),
        .dcache_rdata   (dcache_mem_rdata),
        .dcache_grant   (dcache_mem_grant),
        .main_mem_req   (main_mem_req),
        .main_mem_addr  (main_mem_addr),
        .main_mem_we    (main_mem_we),
        .main_mem_wdata (main_mem_wdata),
        .main_mem_wstrb (main_mem_wstrb),
        .main_mem_rdata (main_mem_rdata)
    );

    // ========================================================================
    // MEM/WB PIPELINE REGISTER
    // ========================================================================
    wire [31:0] wb_pc_reg;
    wire [31:0] wb_alu_result_reg;
    wire [31:0] wb_mem_rdata_reg;
    wire [4:0]  wb_rd_reg;
    wire [2:0]  wb_funct3_reg;
    wire        wb_mem_to_reg_reg;
    wire        wb_reg_write_reg;

wire [31:0] mem_rdata_to_wb = mem_alu_result[31] ? mmio_rdata : dcache_cpu_rdata;

    reg [31:0] mem_formatted_load_data;
    always @(*) begin
        case (mem_funct3)
            3'b000: begin // LB
                case (mem_alu_result[1:0])
                    2'b00:   mem_formatted_load_data = {{24{mem_rdata_to_wb[7]}},  mem_rdata_to_wb[7:0]};
                    2'b01:   mem_formatted_load_data = {{24{mem_rdata_to_wb[15]}}, mem_rdata_to_wb[15:8]};
                    2'b10:   mem_formatted_load_data = {{24{mem_rdata_to_wb[23]}}, mem_rdata_to_wb[23:16]};
                    default: mem_formatted_load_data = {{24{mem_rdata_to_wb[31]}}, mem_rdata_to_wb[31:24]};
                endcase
            end
            3'b001: begin // LH
                mem_formatted_load_data = mem_alu_result[1] ? {{16{mem_rdata_to_wb[31]}}, mem_rdata_to_wb[31:16]} :
                                                              {{16{mem_rdata_to_wb[15]}}, mem_rdata_to_wb[15:0]};
            end
            3'b010: begin // LW
                mem_formatted_load_data = mem_rdata_to_wb;
            end
            3'b100: begin // LBU
                case (mem_alu_result[1:0])
                    2'b00:   mem_formatted_load_data = {24'h0, mem_rdata_to_wb[7:0]};
                    2'b01:   mem_formatted_load_data = {24'h0, mem_rdata_to_wb[15:8]};
                    2'b10:   mem_formatted_load_data = {24'h0, mem_rdata_to_wb[23:16]};
                    default: mem_formatted_load_data = {24'h0, mem_rdata_to_wb[31:24]};
                endcase
            end
            3'b101: begin // LHU
                mem_formatted_load_data = mem_alu_result[1] ? {16'h0, mem_rdata_to_wb[31:16]} :
                                                              {16'h0, mem_rdata_to_wb[15:0]};
            end
            default: mem_formatted_load_data = mem_rdata_to_wb;
        endcase
    end

    assign mem_forward_data = mem_mem_to_reg ? mem_formatted_load_data : mem_alu_result;
    mem_wb_reg u_mem_wb_reg (
        .clk          (clk),
        .reset_n      (reset_n),
        .stall        (stall_ext),
        .flush        (flush_mem_wb),
        .valid_i      (mem_valid),
        .pc_i         (mem_pc),
        .alu_result_i (mem_alu_result),
        .mem_rdata_i  (mem_rdata_to_wb),
        .rd_i         (mem_rd),
        .funct3_i     (mem_funct3),
        .mem_to_reg_i (mem_mem_to_reg),
        .reg_write_i  (mem_reg_write),
        .is_fp_dest_i (mem_is_fp_dest),
        .valid_o      (wb_valid),
        .pc_o         (wb_pc_reg),
        .alu_result_o (wb_alu_result_reg),
        .mem_rdata_o  (wb_mem_rdata_reg),
        .rd_o         (wb_rd_reg),
        .funct3_o     (wb_funct3_reg),
        .mem_to_reg_o (wb_mem_to_reg_reg),
        .reg_write_o  (wb_reg_write_reg),
        .is_fp_dest_o (wb_is_fp_dest)
    );

    assign pc_wb = wb_pc_reg;

    // ========================================================================
    // 5. WRITEBACK (WB) STAGE
    // ========================================================================
    writeback_stage u_writeback_stage (
        .mem_to_reg_i  (wb_mem_to_reg_reg),
        .reg_write_i   (wb_reg_write_reg),
        .funct3_i      (wb_funct3_reg),
        .byte_offset_i (wb_alu_result_reg[1:0]),
        .alu_result_i  (wb_alu_result_reg),
        .mem_rdata_i   (wb_mem_rdata_reg),
        .rd_i          (wb_rd_reg),
        .wb_reg_write_o(wb_reg_write),
        .wb_dest_reg_o (wb_dest_reg),
        .wb_data_o     (wb_data)
    );

    // ========================================================================
    // CENTRALIZED HAZARD & FORWARDING UNIT
    // ========================================================================
    hazard_unit u_hazard_unit (
        .id_rs1           (id_rs1),
        .id_rs2           (id_rs2),
        .id_rs1_used      (id_rs1_used),
        .id_rs2_used      (id_rs2_used),
        .id_ex_rd         (ex_rd),
        .id_ex_mem_read   (ex_mem_read),
        .ex_rs1           (ex_rs1),
        .ex_rs2           (ex_rs2),
        .ex_mem_rd        (mem_rd),
        .ex_mem_reg_write (mem_reg_write),
        .mem_wb_rd        (wb_dest_reg),
        .mem_wb_reg_write (wb_reg_write),
        .id_rs1_is_fp     (id_rs1_is_fp),
        .id_rs2_is_fp     (id_rs2_is_fp),
        .id_ex_is_fp_dest (ex_is_fp_dest),
        .ex_rs1_is_fp     (ex_rs1_is_fp),
        .ex_rs2_is_fp     (ex_rs2_is_fp),
        .ex_mem_is_fp_dest(mem_is_fp_dest),
        .mem_wb_is_fp_dest(wb_is_fp_dest),
        .div_busy         (div_busy_wire),
        .fpu_busy         (fpu_busy_wire),
        .icache_stall     (icache_stall),
        .dcache_stall     (dcache_stall || (dcache_mem_we && !dcache_mem_grant)),
        .mispredict       (ex_mispredict),
        .forward_a        (forward_a),
        .forward_b        (forward_b),
        .stall_if         (stall_if),
        .stall_if_id      (stall_if_id),
        .stall_id_ex      (stall_id_ex),
        .stall_ex_mem     (stall_ex_mem),
        .flush_if_id      (flush_if_id),
        .flush_id_ex      (flush_id_ex),
        .flush_ex_mem     (flush_ex_mem),
        .flush_mem_wb     (flush_mem_wb),
        .load_use_hazard_o(load_use_hazard_o)
    );

    // Architectural Status Indicators for Nexys A7
    assign dcache_miss_busy_o     = dcache_stall;
    assign icache_miss_busy_o     = icache_stall;
    assign btb_mispredict_flush_o = ex_mispredict;
    assign muldiv_busy_o          = div_busy_wire;
    assign wb_reg_commit_o        = wb_reg_write && (wb_dest_reg != 5'd0);

endmodule
