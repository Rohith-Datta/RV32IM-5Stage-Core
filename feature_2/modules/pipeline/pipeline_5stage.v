// ============================================================================
// File: pipeline_5stage.v (Feature 2: RV32IM Multiplier Integrated Core)
// Description: Fully Pipelined 5-Stage RV32IM Processor Core with Hardware Multiplier
// Project: Pipelined RV32IMF RISC-V Core (Feature 2: Hardware Multiplier)
// ============================================================================

`timescale 1ns/1ps

module pipeline_5stage #(
    parameter RESET_PC = 32'h0000_0000
)(
    input  wire        clk,
    input  wire        reset_n,
    input  wire        stall_ext,
    input  wire        use_dsp_i,

    // Instruction Memory Bus
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,

    // Data Memory Bus
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire [3:0]  dmem_wstrb,
    output wire        dmem_we,
    output wire        dmem_re,
    input  wire [31:0] dmem_rdata,

    // Pipeline Diagnostics and Real-Time Observation
    output wire [31:0] pc_if,
    output wire [31:0] pc_id,
    output wire [31:0] pc_ex,
    output wire [31:0] pc_mem,
    output wire [31:0] pc_wb,

    // Commit / Writeback Status
    output wire        wb_reg_write,
    output wire [4:0]  wb_dest_reg,
    output wire [31:0] wb_data,

    // Hazard Status Diagnostics
    output wire        hazard_stall,
    output wire        hazard_flush_id,
    output wire        hazard_flush_ex,
    output wire [1:0]  forward_a,
    output wire [1:0]  forward_b,
    output wire        mul_active,
    output wire        exception
);

    // ========================================================================
    // Hazard and Branch Control Wires
    // ========================================================================
    wire        stall_if;
    wire        stall_if_id;
    wire        flush_if_id;
    wire        flush_id_ex;

    wire        branch_or_jump_taken;
    wire [31:0] target_pc;

    // ========================================================================
    // 1. IF Stage (Instruction Fetch & PC Update)
    // ========================================================================
    reg  [31:0] pc_reg;
    wire [31:0] pc_next;
    wire [31:0] pc_plus4;

    assign pc_plus4 = pc_reg + 32'd4;
    assign pc_next  = branch_or_jump_taken ? target_pc : pc_plus4;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            pc_reg <= RESET_PC;
        end else if (!stall_if && !stall_ext) begin
            pc_reg <= pc_next;
        end
    end

    assign imem_addr = pc_reg;
    assign pc_if     = pc_reg;

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
        .flush      (flush_if_id || branch_or_jump_taken),
        .pc_i       (pc_reg),
        .pc_plus4_i (pc_plus4),
        .instr_i    (imem_rdata),
        .pc_o       (if_id_pc),
        .pc_plus4_o (if_id_pc_plus4),
        .instr_o    (if_id_inst)
    );

    assign pc_id = if_id_pc;

    // ========================================================================
    // 2. ID Stage (Decode, Register File, & Hazard Source Signals)
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
        .stall           (stall_ext),
        .flush           (flush_id_ex || branch_or_jump_taken),
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
        .illegal_inst_o  (id_ex_illegal_inst),
        .pc_o            (id_ex_pc),
        .pc_plus4_o      (id_ex_pc_plus4),
        .rdata1_o        (id_ex_rdata1),
        .rdata2_o        (id_ex_rdata2),
        .imm_o           (id_ex_imm),
        .rs1_o           (id_ex_rs1),
        .rs2_o           (id_ex_rs2),
        .rd_o            (id_ex_rd),
        .funct3_o        (id_ex_funct3)
    );

    assign pc_ex = id_ex_pc;

    // ========================================================================
    // 3. EX Stage (Execution, ALU, Multiplier, & Branch Evaluation)
    // ========================================================================
    wire [31:0] ex_alu_result;
    wire [31:0] ex_store_data;
    wire        ex_branch_taken;
    wire [31:0] ex_alu_in1;
    wire [31:0] ex_alu_in2;

    wire [31:0] ex_mem_alu_result; // Forwarded from EX/MEM

    execute_stage u_execute_stage (
        .pc_i                  (id_ex_pc),
        .pc_plus4_i            (id_ex_pc_plus4),
        .rdata1_i              (id_ex_rdata1),
        .rdata2_i              (id_ex_rdata2),
        .imm_i                 (id_ex_imm),
        .alu_op_i              (id_ex_alu_op),
        .arithsubtype_i        (id_ex_arithsubtype),
        .alu_i                 (id_ex_alu),
        .lui_i                 (id_ex_lui),
        .auipc_i               (id_ex_auipc),
        .jal_i                 (id_ex_jal),
        .jalr_i                (id_ex_jalr),
        .branch_i              (id_ex_branch),
        .mem_read_i            (id_ex_mem_read),
        .mem_write_i           (id_ex_mem_write),
        .immediate_sel_i       (id_ex_immediate_sel),
        .is_mul_i              (id_ex_is_mul),
        .use_dsp_i             (use_dsp_i),
        .forward_a_i           (forward_a),
        .forward_b_i           (forward_b),
        .ex_mem_alu_result_i   (ex_mem_alu_result),
        .wb_data_i             (wb_data),
        .alu_result_o          (ex_alu_result),
        .store_data_o          (ex_store_data),
        .branch_taken_o        (ex_branch_taken),
        .branch_or_jump_taken_o(branch_or_jump_taken),
        .target_pc_o           (target_pc),
        .alu_in1_o             (ex_alu_in1),
        .alu_in2_o             (ex_alu_in2),
        .mul_active_o          (mul_active)
    );

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
        .stall        (stall_ext),
        .flush        (1'b0),
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
    // 4. MEM Stage (Memory Access & Store Data Formatting)
    // ========================================================================
    memory_stage u_memory_stage (
        .mem_read_i   (ex_mem_mem_read),
        .mem_write_i  (ex_mem_mem_write),
        .funct3_i     (ex_mem_funct3),
        .alu_result_i (ex_mem_alu_result),
        .store_data_i (ex_mem_store_data),
        .dmem_addr_o  (dmem_addr),
        .dmem_wdata_o (dmem_wdata),
        .dmem_wstrb_o (dmem_wstrb),
        .dmem_we_o    (dmem_we),
        .dmem_re_o    (dmem_re)
    );

    // ========================================================================
    // MEM/WB Pipeline Register
    // ========================================================================
    wire        mem_wb_mem_to_reg;
    wire        mem_wb_reg_write;
    wire [2:0]  mem_wb_funct3;
    wire [1:0]  mem_wb_byte_offset;
    wire [31:0] mem_wb_alu_result;
    wire [31:0] mem_wb_rdata;
    wire [4:0]  mem_wb_rd;
    wire [31:0] mem_wb_pc_plus4;

    mem_wb_reg u_mem_wb_reg (
        .clk           (clk),
        .reset_n       (reset_n),
        .stall         (stall_ext),
        .mem_to_reg_i  (ex_mem_mem_to_reg),
        .reg_write_i   (ex_mem_reg_write),
        .funct3_i      (ex_mem_funct3),
        .byte_offset_i (ex_mem_alu_result[1:0]),
        .alu_result_i  (ex_mem_alu_result),
        .mem_rdata_i   (dmem_rdata),
        .rd_i          (ex_mem_rd),
        .pc_plus4_i    (ex_mem_pc_plus4),
        .mem_to_reg_o  (mem_wb_mem_to_reg),
        .reg_write_o   (mem_wb_reg_write),
        .funct3_o      (mem_wb_funct3),
        .byte_offset_o (mem_wb_byte_offset),
        .alu_result_o  (mem_wb_alu_result),
        .mem_rdata_o   (mem_wb_rdata),
        .rd_o          (mem_wb_rd),
        .pc_plus4_o    (mem_wb_pc_plus4)
    );

    assign pc_wb = mem_wb_pc_plus4 - 32'd4;

    // ========================================================================
    // 5. WB Stage (Writeback & Load Data Formatting)
    // ========================================================================
    writeback_stage u_writeback_stage (
        .mem_to_reg_i  (mem_wb_mem_to_reg),
        .reg_write_i   (mem_wb_reg_write),
        .funct3_i      (mem_wb_funct3),
        .byte_offset_i (mem_wb_byte_offset),
        .alu_result_i  (mem_wb_alu_result),
        .mem_rdata_i   (mem_wb_rdata),
        .rd_i          (mem_wb_rd),
        .wb_reg_write_o(wb_reg_write),
        .wb_dest_reg_o (wb_dest_reg),
        .wb_data_o     (wb_data)
    );

    // ========================================================================
    // 6. Hazard Detection & Forwarding Unit
    // ========================================================================
    hazard_unit u_hazard_unit (
        .id_rs1          (id_rs1),
        .id_rs2          (id_rs2),
        .id_rs1_used     (id_rs1_used),
        .id_rs2_used     (id_rs2_used),
        .id_ex_rs1       (id_ex_rs1),
        .id_ex_rs2       (id_ex_rs2),
        .id_ex_rd        (id_ex_rd),
        .id_ex_mem_read  (id_ex_mem_read),
        .id_ex_branch    (id_ex_branch),
        .id_ex_jal       (id_ex_jal),
        .id_ex_jalr      (id_ex_jalr),
        .ex_branch_taken (ex_branch_taken),
        .ex_mem_rd       (ex_mem_rd),
        .ex_mem_reg_write(ex_mem_reg_write),
        .mem_wb_rd       (mem_wb_rd),
        .mem_wb_reg_write(mem_wb_reg_write),
        .forward_a       (forward_a),
        .forward_b       (forward_b),
        .stall_if        (stall_if),
        .stall_if_id     (stall_if_id),
        .flush_if_id     (flush_if_id),
        .flush_id_ex     (flush_id_ex)
    );

    // Diagnostics / Exception
    assign hazard_stall    = stall_if;
    assign hazard_flush_id = flush_if_id;
    assign hazard_flush_ex = flush_id_ex;
    assign exception       = id_illegal_inst;

endmodule
