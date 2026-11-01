// ============================================================================
// File: decode_stage.v (RV32F with separate FP register file: FLW/FSW/FMV + FADD..FDIV)
// Description: Instruction Decode & Register File with RV32M and RV32F Decoding
// Project: Pipelined RV32IMF RISC-V Core (Feature 4: IEEE 754 FPU)
// ============================================================================

`timescale 1ns/1ps

module decode_stage (
    input  wire        clk,
    input  wire        reset_n,

    // Instruction and PC from IF/ID
    input  wire [31:0] instruction_i,
    input  wire [31:0] pc_i,

    // Writeback Interface from WB stage
    input  wire        wb_reg_write_i,
    input  wire [4:0]  wb_dest_reg_i,
    input  wire [31:0] wb_data_i,
    input  wire        wb_rd_fp_i,       // 1: writeback targets the FP register file

    // Decoded Control Signals to ID/EX
    output reg  [2:0]  alu_op_o,
    output reg         arithsubtype_o,
    output reg         alu_o,
    output reg         lui_o,
    output reg         auipc_o,
    output reg         jal_o,
    output reg         jalr_o,
    output reg         branch_o,
    output reg         mem_read_o,
    output reg         mem_write_o,
    output reg         mem_to_reg_o,
    output reg         reg_write_o,
    output reg         immediate_sel_o,
    output reg         is_mul_o,
    output reg         is_div_o,
    output reg         is_fpu_o,
    output reg         is_fmv_o,         // FMV.X.W / FMV.W.X (bit-copy between files)
    output reg         rs1_fp_o,         // rs1 is read from the FP register file
    output reg         rs2_fp_o,         // rs2 is read from the FP register file
    output reg         rd_fp_o,          // rd  is written to the FP register file
    output reg         illegal_inst_o,

    // Decoded Data Signals to ID/EX
    output wire [31:0] rdata1_o,
    output wire [31:0] rdata2_o,
    output reg  [31:0] imm_o,

    // Register specifiers
    output wire [4:0]  rs1_o,
    output wire [4:0]  rs2_o,
    output wire [4:0]  rd_o,
    output wire [2:0]  funct3_o,
    output wire [6:0]  funct7_o,

    // Hazard usage indicators to Hazard Unit
    output reg         id_rs1_used_o,
    output reg         id_rs2_used_o
);

    `include "opcode.vh"

    // ------------------------------------------------------------------------
    // Field Extraction
    // ------------------------------------------------------------------------
    assign rs1_o    = instruction_i[`RS1];
    assign rs2_o    = instruction_i[`RS2];
    assign rd_o     = instruction_i[`RD];
    assign funct3_o = instruction_i[`FUNC3];
    assign funct7_o = instruction_i[31:25];

    wire [6:0] opcode = instruction_i[`OPCODE];

    // ------------------------------------------------------------------------
    // Integer Register File (x1..x31, x0 hardwired to 0)
    // FP Register File      (f0..f31, f0 is a NORMAL register)
    // Writeback selects the file with wb_rd_fp_i.
    // ------------------------------------------------------------------------
    reg [31:0] regs  [1:31];
    reg [31:0] fregs [0:31];
    integer i;
    integer j;

    // Synchronous Write Ports (mirror into both files so integer code and FP code interoperate)
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 1; i < 32; i = i + 1) regs[i]  <= 32'h0;
            for (j = 0; j < 32; j = j + 1) fregs[j] <= 32'h0;
        end else if (wb_reg_write_i) begin
            if (wb_dest_reg_i != 5'd0)
                regs[wb_dest_reg_i]  <= wb_data_i;
            fregs[wb_dest_reg_i]     <= wb_data_i;
        end
    end

    // Asynchronous Read Ports with WB -> ID bypass
    wire [31:0] int_rdata1 = (rs1_o == 5'd0) ? 32'd0 :
                             (wb_reg_write_i && (wb_dest_reg_i == rs1_o)) ? wb_data_i :
                             regs[rs1_o];
    wire [31:0] int_rdata2 = (rs2_o == 5'd0) ? 32'd0 :
                             (wb_reg_write_i && (wb_dest_reg_i == rs2_o)) ? wb_data_i :
                             regs[rs2_o];

    wire [31:0] fp_rdata1  = (wb_reg_write_i && (wb_dest_reg_i == rs1_o)) ? wb_data_i :
                             fregs[rs1_o];
    wire [31:0] fp_rdata2  = (wb_reg_write_i && (wb_dest_reg_i == rs2_o)) ? wb_data_i :
                             fregs[rs2_o];

    assign rdata1_o = rs1_fp_o ? fp_rdata1 : int_rdata1;
    assign rdata2_o = rs2_fp_o ? fp_rdata2 : int_rdata2;

    // ------------------------------------------------------------------------
    // Control Signal Decoding and Immediate Generation
    // ------------------------------------------------------------------------
    always @(*) begin
        // Defaults
        alu_op_o        = instruction_i[`FUNC3];
        arithsubtype_o  = instruction_i[`SUBTYPE];
        alu_o           = 1'b0;
        lui_o           = 1'b0;
        auipc_o         = 1'b0;
        jal_o           = 1'b0;
        jalr_o          = 1'b0;
        branch_o        = 1'b0;
        mem_read_o      = 1'b0;
        mem_write_o     = 1'b0;
        mem_to_reg_o    = 1'b0;
        reg_write_o     = 1'b0;
        immediate_sel_o = 1'b0;
        is_mul_o        = 1'b0;
        is_div_o        = 1'b0;
        is_fpu_o        = 1'b0;
        is_fmv_o        = 1'b0;
        rs1_fp_o        = 1'b0;
        rs2_fp_o        = 1'b0;
        rd_fp_o         = 1'b0;
        illegal_inst_o  = 1'b0;
        imm_o           = 32'h0;
        id_rs1_used_o   = 1'b0;
        id_rs2_used_o   = 1'b0;

        case (opcode)
            ARITHR: begin
                if (instruction_i[31:25] == FUNCT7_M_EXT) begin
                    if (instruction_i[14] == 1'b0) begin
                        // RV32M Hardware Multiplication (MUL, MULH, MULHSU, MULHU)
                        is_mul_o      = 1'b1;
                        alu_o         = 1'b0;
                        reg_write_o   = 1'b1;
                        id_rs1_used_o = 1'b1;
                        id_rs2_used_o = 1'b1;
                    end else begin
                        // RV32M Hardware Division (DIV, DIVU, REM, REMU)
                        is_div_o      = 1'b1;
                        alu_o         = 1'b0;
                        reg_write_o   = 1'b1;
                        id_rs1_used_o = 1'b1;
                        id_rs2_used_o = 1'b1;
                    end
                end else begin
                    alu_o         = 1'b1;
                    reg_write_o   = 1'b1;
                    id_rs1_used_o = 1'b1;
                    id_rs2_used_o = 1'b1;
                end
            end

            OP_FP: begin
                // Only the supported RV32F single-precision instructions are legal.
                // Anything else is an illegal instruction (all controls stay 0).
                case (instruction_i[31:25])
                    FUNCT7_FADD, FUNCT7_FSUB, FUNCT7_FMUL, FUNCT7_FDIV: begin
                        is_fpu_o      = 1'b1;
                        alu_o         = 1'b0;
                        reg_write_o   = 1'b1;
                        id_rs1_used_o = 1'b1;
                        id_rs2_used_o = 1'b1;
                        rs1_fp_o      = 1'b1;   // f[rs1]
                        rs2_fp_o      = 1'b1;   // f[rs2]
                        rd_fp_o       = 1'b1;   // f[rd]
                    end

                    FUNCT7_FMV_X_W: begin       // x[rd] <- f[rs1]
                        if (instruction_i[24:20] == 5'd0 && instruction_i[`FUNC3] == 3'b000) begin
                            is_fmv_o      = 1'b1;
                            reg_write_o   = 1'b1;
                            id_rs1_used_o = 1'b1;
                            rs1_fp_o      = 1'b1;
                        end else illegal_inst_o = 1'b1;
                    end

                    FUNCT7_FMV_W_X: begin       // f[rd] <- x[rs1]
                        if (instruction_i[24:20] == 5'd0 && instruction_i[`FUNC3] == 3'b000) begin
                            is_fmv_o      = 1'b1;
                            reg_write_o   = 1'b1;
                            id_rs1_used_o = 1'b1;
                            rd_fp_o       = 1'b1;
                        end else illegal_inst_o = 1'b1;
                    end

                    default: illegal_inst_o = 1'b1;
                endcase
            end

            // FLW rd(fp), imm(rs1 int)  -- same datapath as LW, destination is the FP file
            LOAD_FP: begin
                if (instruction_i[`FUNC3] == 3'b010) begin
                    mem_read_o      = 1'b1;
                    mem_to_reg_o    = 1'b1;
                    reg_write_o     = 1'b1;
                    immediate_sel_o = 1'b1;
                    id_rs1_used_o   = 1'b1;
                    rd_fp_o         = 1'b1;
                    imm_o           = {{20{instruction_i[31]}}, instruction_i[31:20]};
                end else illegal_inst_o = 1'b1;
            end

            // FSW rs2(fp), imm(rs1 int)  -- same datapath as SW, data comes from the FP file
            STORE_FP: begin
                if (instruction_i[`FUNC3] == 3'b010) begin
                    mem_write_o     = 1'b1;
                    immediate_sel_o = 1'b1;
                    id_rs1_used_o   = 1'b1;
                    id_rs2_used_o   = 1'b1;
                    rs2_fp_o        = 1'b1;
                    imm_o           = {{20{instruction_i[31]}}, instruction_i[31:25], instruction_i[11:7]};
                end else illegal_inst_o = 1'b1;
            end

            ARITHI: begin
                alu_o           = 1'b1;
                reg_write_o     = 1'b1;
                immediate_sel_o = 1'b1;
                id_rs1_used_o   = 1'b1;
                if (instruction_i[`FUNC3] == SLL || instruction_i[`FUNC3] == SR) begin
                    imm_o = {27'h0, instruction_i[24:20]};
                end else begin
                    imm_o = {{20{instruction_i[31]}}, instruction_i[31:20]};
                    arithsubtype_o = 1'b0;
                end
            end

            LOAD: begin
                mem_read_o      = 1'b1;
                mem_to_reg_o    = 1'b1;
                reg_write_o     = 1'b1;
                immediate_sel_o = 1'b1;
                id_rs1_used_o   = 1'b1;
                imm_o           = {{20{instruction_i[31]}}, instruction_i[31:20]};
            end

            STORE: begin
                mem_write_o     = 1'b1;
                immediate_sel_o = 1'b1;
                id_rs1_used_o   = 1'b1;
                id_rs2_used_o   = 1'b1;
                imm_o           = {{20{instruction_i[31]}}, instruction_i[31:25], instruction_i[11:7]};
            end

            BRANCH: begin
                branch_o      = 1'b1;
                id_rs1_used_o = 1'b1;
                id_rs2_used_o = 1'b1;
                imm_o         = {{20{instruction_i[31]}}, instruction_i[7], instruction_i[30:25], instruction_i[11:8], 1'b0};
            end

            LUI: begin
                lui_o           = 1'b1;
                reg_write_o     = 1'b1;
                immediate_sel_o = 1'b1;
                imm_o           = {instruction_i[31:12], 12'b0};
            end

            AUIPC: begin
                auipc_o         = 1'b1;
                reg_write_o     = 1'b1;
                immediate_sel_o = 1'b1;
                imm_o           = {instruction_i[31:12], 12'b0};
            end

            JAL: begin
                jal_o       = 1'b1;
                reg_write_o = 1'b1;
                imm_o       = {{12{instruction_i[31]}}, instruction_i[19:12], instruction_i[20], instruction_i[30:21], 1'b0};
            end

            JALR: begin
                jalr_o          = 1'b1;
                reg_write_o     = 1'b1;
                immediate_sel_o = 1'b1;
                id_rs1_used_o   = 1'b1;
                imm_o           = {{20{instruction_i[31]}}, instruction_i[31:20]};
            end

            default: begin
                illegal_inst_o = 1'b1;
            end
        endcase
    end

endmodule