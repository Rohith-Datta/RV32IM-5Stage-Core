// ============================================================================
// File: pipeline_5stage.v (Feature 5: RV32IMF Core with L1 D-Cache)
// Description: Top-Level 5-Stage RV32IMF Pipelined Processor Core with L1 D-Cache
// Project: Pipelined RV32IMF RISC-V Core (Feature 5: L1 D-Cache)
// Integrated Subsystems:
//   - Feature 1: 5-Stage Pipeline Registers & Hazard Unit
//   - Feature 2: Dual-Mode Hardware Multiplier (DSP48E1 / Booth Radix-4)
//   - Feature 3: 32-Cycle Radix-2 Hardware Divider & Remainder Unit
//   - Feature 4: IEEE 754 Single-Precision FPU (FADD/FSUB 5c, FMUL 4c, FDIV 15c)
//   - Feature 5: Direct-Mapped 2 KB L1 Data Cache (1-cycle hit, 10-cycle miss FSM,
//                Write-Through + Write Buffer, No-Write-Allocate)
// Target: Standard 50 MHz Core Frequency
// ============================================================================

`timescale 1ns/1ps

module pipeline_5stage #(
    parameter RESET_PC = 32'h0000_0000
)(
    input  wire        clk,
    input  wire        reset_n,
    input  wire        stall_ext,        // External freeze (e.g. UART / hardware pause)
    input  wire        use_dsp_i,        // 1: DSP48E1, 0: Booth Radix-4 Multiplier
    input  wire        dcache_bypass_i,  // 0: D-Cache Enabled, 1: D-Cache Bypassed

    // Instruction Memory Bus (IF stage directly to Backing IMEM)
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,

    // Data Memory Bus (Backing DMEM Refill & Write-Through Bus)
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire [3:0]  dmem_wstrb,
    output wire        dmem_we,
    output wire        dmem_req,
    input  wire [31:0] dmem_rdata,

    // MMIO Interface (to UART Subsystem & Peripherals)
    output wire [31:0] mmio_addr_o,
    output wire [31:0] mmio_wdata_o,
    output wire        mmio_we_o,
    output wire        mmio_re_o,
    input  wire [31:0] mmio_rdata_i,
    input  wire        mmio_match_i,

    // Pipeline Monitoring & Diagnostics
    output wire [31:0] pc_if,
    output wire [31:0] pc_id,
    output wire [31:0] pc_ex,
    output wire [31:0] pc_mem,
    output wire [31:0] pc_wb,
    output wire        wb_reg_write,
    output wire [4:0]  wb_dest_reg,
    output wire [31:0] wb_data,
    output wire        hazard_stall,
    output wire        hazard_flush_id,
    output wire        hazard_flush_ex,
    output wire [1:0]  forward_a,
    output wire [1:0]  forward_b,
    output wire        mul_active,
    output wire        div_active,
    output wire        div_busy,
    output wire        fpu_active,
    output wire        fpu_busy,
    output wire        exception,

    // D-Cache Diagnostics
    output wire        dcache_stall,
    output wire        dcache_hit,
    output wire        dcache_miss,
    output wire [31:0] dcache_hit_count,
    output wire [31:0] dcache_miss_count
);

    `include "opcode.vh"

    // Interconnect Controls
    wire        stall_if;
    wire        stall_if_id;
    wire        stall_id_ex;
    wire        stall_ex_mem;
    wire        flush_if_id;
    wire        flush_id_ex;
    wire        flush_ex_mem;
    wire        flush_mem_wb;

    wire        branch_or_jump_taken;
    wire [31:0] target_pc;

    // ========================================================================
    // 1. IF Stage (Instruction Fetch & PC Update)
    // ========================================================================
    reg  [31:0] pc_reg;
    wire [31:0] pc_plus4;

    assign pc_plus4 = pc_reg + 32'd4;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            pc_reg <= RESET_PC;
        end else if (!stall_ext) begin
            if (stall_if)
                pc_reg <= pc_reg;
            else if (branch_or_jump_taken)
                pc_reg <= target_pc;
            else
                pc_reg <= pc_plus4;
        end
    end

    assign pc_if     = pc_reg;
    assign imem_addr = pc_reg;

    // ========================================================================
    // IF/ID Pipeline Register
    // ========================================================================
    wire [31:0] if_id_pc;
    wire [31:0] if_id_pc_plus4;
    wire [31:0] if_id_inst;

    if_id_reg u_if_id_reg (
        .clk        (clk),
        .reset_n    (reset_n),
        .stall      (stall_if_id || stall_ext),
        .flush      (flush_if_id),
        .pc_i       (pc_reg),
        .pc_plus4_i (pc_plus4),
        .instr_i    (imem_rdata),
        .pc_o       (if_id_pc),
        .pc_plus4_o (if_id_pc_plus4),
        .instr_o    (if_id_inst)
    );

    assign pc_id = if_id_pc;

    // ========================================================================
    // 2. ID Stage (Decode, Register File, & Hazard Signals)
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
    wire [6:0]  id_funct7;
    wire        id_illegal_inst;
    wire [31:0] id_rdata1;
    wire [31:0] id_rdata2;
    wire [31:0] id_imm;
    wire [4:0]  id_rs1;
    wire [4:0]  id_rs2;
    wire [4:0]  id_rd;
    wire [2:0]  id_funct3;
    wire        id_rs1_used;
    wire        id_rs2_used;

    decode_stage u_decode_stage (
        .clk            (clk),
        .reset_n        (reset_n),
        .instruction_i  (if_id_inst),
        .pc_i           (if_id_pc),
        .wb_reg_write_i (wb_reg_write),
        .wb_dest_reg_i  (wb_dest_reg),
        .wb_data_i      (wb_data),
        .alu_op_o       (id_alu_op),
        .arithsubtype_o (id_arithsubtype),
        .alu_o          (id_alu),
        .lui_o          (id_lui),
        .auipc_o        (id_auipc),
        .jal_o          (id_jal),
        .jalr_o         (id_jalr),
        .branch_o       (id_branch),
        .mem_read_o     (id_mem_read),
        .mem_write_o    (id_mem_write),
        .mem_to_reg_o   (id_mem_to_reg),
        .reg_write_o    (id_reg_write),
        .immediate_sel_o(id_immediate_sel),
        .is_mul_o       (id_is_mul),
        .is_div_o       (id_is_div),
        .is_fpu_o       (id_is_fpu),
        .funct7_o       (id_funct7),
        .illegal_inst_o (id_illegal_inst),
        .rdata1_o       (id_rdata1),
        .rdata2_o       (id_rdata2),
        .imm_o          (id_imm),
        .rs1_o          (id_rs1),
        .rs2_o          (id_rs2),
        .rd_o           (id_rd),
        .funct3_o       (id_funct3),
        .id_rs1_used_o  (id_rs1_used),
        .id_rs2_used_o  (id_rs2_used)
    );

    // ========================================================================
    // ID/EX Pipeline Register
    // ========================================================================
    wire [2:0]  id_ex_alu_op;
    wire        id_ex_arithsubtype;
    wire        id_ex_alu;
    wire        id_ex_lui;
    wire        id_ex_auipc;
    wire        id_ex_jal;
    wire        id_ex_jalr;
    wire        id_ex_branch;
    wire        id_ex_mem_read;
    wire        id_ex_mem_write;
    wire        id_ex_mem_to_reg;
    wire        id_ex_reg_write;
    wire        id_ex_immediate_sel;
    wire        id_ex_is_mul;
    wire        id_ex_is_div;
    wire        id_ex_is_fpu;
    wire [6:0]  id_ex_funct7;
    wire        id_ex_illegal_inst;
    wire [31:0] id_ex_pc;
    wire [31:0] id_ex_pc_plus4;
    wire [31:0] id_ex_rdata1;
    wire [31:0] id_ex_rdata2;
    wire [31:0] id_ex_imm;
    wire [4:0]  id_ex_rs1;
    wire [4:0]  id_ex_rs2;
    wire [4:0]  id_ex_rd;
    wire [2:0]  id_ex_funct3;

    id_ex_reg u_id_ex_reg (
        .clk             (clk),
        .reset_n         (reset_n),
        .stall           (stall_id_ex || stall_ext),
        .flush           (flush_id_ex),
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
        .funct7_i        (id_funct7),
        .illegal_inst_i  (id_illegal_inst),
        .pc_i            (if_id_pc),
        .pc_plus4_i      (if_id_pc_plus4),
        .rdata1_i        (id_rdata1),
        .rdata2_i        (id_rdata2),
        .imm_i           (id_imm),
        .rs1_i           (id_rs1),
        .rs2_i           (id_rs2),
        .rd_i            (id_rd),
        .funct3_i        (id_funct3),
        .wb_reg_write_i  (wb_reg_write),
        .wb_dest_reg_i   (wb_dest_reg),
        .wb_data_i       (wb_data),
        .alu_op_o        (id_ex_alu_op),
        .arithsubtype_o  (id_ex_arithsubtype),
        .alu_o           (id_ex_alu),
        .lui_o           (id_ex_lui),
        .auipc_o         (id_ex_auipc),
        .jal_o           (id_ex_jal),
        .jalr_o          (id_ex_jalr),
        .branch_o        (id_ex_branch),
        .mem_read_o      (id_ex_mem_read),
        .mem_write_o     (id_ex_mem_write),
        .mem_to_reg_o    (id_ex_mem_to_reg),
        .reg_write_o     (id_ex_reg_write),
        .immediate_sel_o (id_ex_immediate_sel),
        .is_mul_o        (id_ex_is_mul),
        .is_div_o        (id_ex_is_div),
        .is_fpu_o        (id_ex_is_fpu),
        .funct7_o        (id_ex_funct7),
        .illegal_inst_o  (id_ex_illegal_inst),
        .pc_o            (id_ex_pc),
        .pc_plus4_o      (id_ex_pc_plus4),
        .rdata1_o        (id_ex_rdata1),
        .rdata2_o        (id_ex_rdata2),
        .imm_o           (id_ex_imm),
        .rs1_o          (id_ex_rs1),
        .rs2_o          (id_ex_rs2),
        .rd_o           (id_ex_rd),
        .funct3_o       (id_ex_funct3)
    );

    assign pc_ex = id_ex_pc;

    // ========================================================================
    // 3. EX Stage (Execution, Multiplier, Divider, FPU, Branch, & Forwarding)
    // ========================================================================
    wire [31:0] ex_alu_result;
    wire [31:0] ex_store_data;
    wire        ex_branch_taken;
    wire [31:0] ex_mem_alu_result;

    execute_stage u_execute_stage (
        .clk                   (clk),
        .reset_n               (reset_n),
        .pc_i                  (id_ex_pc),
        .pc_plus4_i            (id_ex_pc_plus4),
        .rdata1_i              (id_ex_rdata1),
        .rdata2_i              (id_ex_rdata2),
        .imm_i                 (id_ex_imm),
        .ex_mem_data_i         (ex_mem_alu_result),
        .mem_wb_data_i         (wb_data),
        .forward_a_i           (forward_a),
        .forward_b_i           (forward_b),
        .alu_op_i              (id_ex_alu_op),
        .arithsubtype_i        (id_ex_arithsubtype),
        .lui_i                 (id_ex_lui),
        .auipc_i               (id_ex_auipc),
        .jal_i                 (id_ex_jal),
        .jalr_i                (id_ex_jalr),
        .branch_i              (id_ex_branch),
        .mem_read_i            (id_ex_mem_read),
        .mem_write_i           (id_ex_mem_write),
        .immediate_sel_i       (id_ex_immediate_sel),
        .is_mul_i              (id_ex_is_mul),
        .is_div_i              (id_ex_is_div),
        .is_fpu_i              (id_ex_is_fpu),
        .funct7_i              (id_ex_funct7),
        .use_dsp_i             (use_dsp_i),
        .alu_result_o          (ex_alu_result),
        .mem_wdata_o           (ex_store_data),
        .target_pc_o           (target_pc),
        .branch_taken_o        (ex_branch_taken),
        .branch_or_jump_taken_o(branch_or_jump_taken),
        .div_busy_o            (div_busy),
        .fpu_busy_o            (fpu_busy)
    );

    assign mul_active = id_ex_is_mul;
    assign div_active = id_ex_is_div;
    assign fpu_active = id_ex_is_fpu;

    // ========================================================================
    // EX/MEM Pipeline Register
    // ========================================================================
    wire        ex_mem_mem_read;
    wire        ex_mem_mem_write;
    wire        ex_mem_mem_to_reg;
    wire        ex_mem_reg_write;
    wire [2:0]  ex_mem_funct3;
    wire [31:0] ex_mem_store_data;
    wire [4:0]  ex_mem_rd;
    wire [31:0] ex_mem_pc;
    wire [31:0] ex_mem_pc_plus4;

    ex_mem_reg u_ex_mem_reg (
        .clk          (clk),
        .reset_n      (reset_n),
        .stall        (stall_ex_mem || stall_ext),
        .flush        (flush_ex_mem),
        .mem_read_i   (id_ex_mem_read),
        .mem_write_i  (id_ex_mem_write),
        .mem_to_reg_i (id_ex_mem_to_reg),
        .reg_write_i  (id_ex_reg_write),
        .funct3_i     (id_ex_funct3),
        .alu_result_i (ex_alu_result),
        .store_data_i (ex_store_data),
        .rd_i         (id_ex_rd),
        .pc_i         (id_ex_pc),
        .pc_plus4_i   (id_ex_pc_plus4),
        .mem_read_o   (ex_mem_mem_read),
        .mem_write_o  (ex_mem_mem_write),
        .mem_to_reg_o (ex_mem_mem_to_reg),
        .reg_write_o  (ex_mem_reg_write),
        .funct3_o     (ex_mem_funct3),
        .alu_result_o (ex_mem_alu_result),
        .store_data_o (ex_mem_store_data),
        .rd_o         (ex_mem_rd),
        .pc_o         (ex_mem_pc),
        .pc_plus4_o   (ex_mem_pc_plus4)
    );

    assign pc_mem = ex_mem_pc;

    // ========================================================================
    // 4. MEM Stage (Memory Interface, L1 D-Cache, & MMIO Bypass)
    // ========================================================================
    wire [31:0] dmem_stage_addr;
    wire [31:0] dmem_stage_wdata;
    wire [3:0]  dmem_stage_wstrb;
    wire        dmem_stage_we;
    wire        dmem_stage_re;

    memory_stage u_memory_stage (
        .mem_read_i   (ex_mem_mem_read),
        .mem_write_i  (ex_mem_mem_write),
        .funct3_i     (ex_mem_funct3),
        .alu_result_i (ex_mem_alu_result),
        .store_data_i (ex_mem_store_data),
        .dmem_addr_o  (dmem_stage_addr),
        .dmem_wdata_o (dmem_stage_wdata),
        .dmem_wstrb_o (dmem_stage_wstrb),
        .dmem_we_o    (dmem_stage_we),
        .dmem_re_o    (dmem_stage_re)
    );

    // MMIO Detection: 0x8000_xxxx (UART) or 0x1000_xxxx (Diagnostic)
    wire is_mmio = (dmem_stage_addr[31:16] == 16'h8000) || (dmem_stage_addr[31:28] == 4'h1) || mmio_match_i;

    assign mmio_addr_o  = dmem_stage_addr;
    assign mmio_wdata_o = dmem_stage_wdata;
    assign mmio_we_o    = dmem_stage_we && is_mmio;
    assign mmio_re_o    = dmem_stage_re && is_mmio;

    // Gate cache accesses so MMIO operations bypass L1 D-Cache directly
    wire dcache_cpu_we = dmem_stage_we && !is_mmio;
    wire dcache_cpu_re = dmem_stage_re && !is_mmio;

    wire [31:0] dcache_rdata;

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
        .cpu_we          (dcache_cpu_we),
        .cpu_re          (dcache_cpu_re),
        .cpu_rdata       (dcache_rdata),
        .dcache_stall    (dcache_stall),
        .mem_addr        (dmem_addr),
        .mem_rdata       (dmem_rdata),
        .mem_wdata       (dmem_wdata),
        .mem_wstrb       (dmem_wstrb),
        .mem_we          (dmem_we),
        .mem_req         (dmem_req),
        .cache_hit       (dcache_hit),
        .cache_miss      (dcache_miss),
        .hit_count       (dcache_hit_count),
        .miss_count      (dcache_miss_count)
    );

    // Selected read data: MMIO peripheral read vs L1 D-Cache read
    wire [31:0] mem_rdata_final = is_mmio ? mmio_rdata_i : dcache_rdata;

    // ========================================================================
    // MEM/WB Pipeline Register
    // ========================================================================
    wire        mem_wb_mem_to_reg;
    wire        mem_wb_reg_write;
    wire [2:0]  mem_wb_funct3;
    wire [1:0]  mem_wb_byte_offset;
    wire [31:0] mem_wb_alu_result;
    wire [31:0] mem_wb_mem_rdata;
    wire [4:0]  mem_wb_rd;
    wire [31:0] mem_wb_pc_plus4;

    mem_wb_reg u_mem_wb_reg (
        .clk           (clk),
        .reset_n       (reset_n),
        .stall         (stall_ext),
        .flush         (flush_mem_wb),
        .mem_to_reg_i  (ex_mem_mem_to_reg),
        .reg_write_i   (ex_mem_reg_write),
        .funct3_i      (ex_mem_funct3),
        .byte_offset_i (ex_mem_alu_result[1:0]),
        .alu_result_i  (ex_mem_alu_result),
        .mem_rdata_i   (mem_rdata_final),
        .rd_i          (ex_mem_rd),
        .pc_plus4_i    (ex_mem_pc_plus4),
        .mem_to_reg_o  (mem_wb_mem_to_reg),
        .reg_write_o   (mem_wb_reg_write),
        .funct3_o      (mem_wb_funct3),
        .byte_offset_o (mem_wb_byte_offset),
        .alu_result_o  (mem_wb_alu_result),
        .mem_rdata_o   (mem_wb_mem_rdata),
        .rd_o          (mem_wb_rd),
        .pc_plus4_o    (mem_wb_pc_plus4)
    );

    assign pc_wb = mem_wb_pc_plus4 - 32'd4;

    // ========================================================================
    // 5. WB Stage (Writeback Multiplexing & Sign/Zero Extension)
    // ========================================================================
    writeback_stage u_writeback_stage (
        .mem_to_reg_i  (mem_wb_mem_to_reg),
        .reg_write_i   (mem_wb_reg_write),
        .funct3_i      (mem_wb_funct3),
        .byte_offset_i (mem_wb_byte_offset),
        .alu_result_i  (mem_wb_alu_result),
        .mem_rdata_i   (mem_wb_mem_rdata),
        .rd_i          (mem_wb_rd),
        .wb_reg_write_o(wb_reg_write),
        .wb_dest_reg_o (wb_dest_reg),
        .wb_data_o     (wb_data)
    );

    // ========================================================================
    // Centralized Hazard Detection Unit
    // ========================================================================
    hazard_unit u_hazard_unit (
        .id_rs1           (id_rs1),
        .id_rs2           (id_rs2),
        .id_rs1_used      (id_rs1_used),
        .id_rs2_used      (id_rs2_used),
        .id_ex_rs1        (id_ex_rs1),
        .id_ex_rs2        (id_ex_rs2),
        .id_ex_rd         (id_ex_rd),
        .id_ex_mem_read   (id_ex_mem_read),
        .id_ex_branch     (id_ex_branch),
        .id_ex_jal        (id_ex_jal),
        .id_ex_jalr       (id_ex_jalr),
        .ex_branch_taken  (ex_branch_taken),
        .div_busy         (div_busy),
        .fpu_busy         (fpu_busy),
        .ex_mem_rd        (ex_mem_rd),
        .ex_mem_reg_write (ex_mem_reg_write),
        .dcache_stall_i   (dcache_stall),
        .mem_wb_rd        (wb_dest_reg),
        .mem_wb_reg_write (wb_reg_write),
        .forward_a        (forward_a),
        .forward_b        (forward_b),
        .stall_if         (stall_if),
        .stall_if_id      (stall_if_id),
        .stall_id_ex      (stall_id_ex),
        .stall_ex_mem     (stall_ex_mem),
        .flush_if_id      (flush_if_id),
        .flush_id_ex      (flush_id_ex),
        .flush_ex_mem     (flush_ex_mem),
        .flush_mem_wb     (flush_mem_wb)
    );

    assign hazard_stall    = stall_if || dcache_stall;
    assign hazard_flush_id = flush_if_id;
    assign hazard_flush_ex = flush_id_ex;
    assign exception       = id_illegal_inst;

endmodule
