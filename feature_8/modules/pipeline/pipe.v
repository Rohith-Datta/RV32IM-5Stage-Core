// ============================================================================
// File: pipe.v (Feature 8: Student Learning & Guided Practice Wrapper)
// Module: pipe
// Description: Educational Pipeline Wrapper with Register Forwarding & Writeback
// ============================================================================

`timescale 1ns/1ps

module pipe #(
    parameter [31:0] RESET = 32'h0000_0000
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        stall,
    output wire        exception,
    output wire [31:0] pc_out,

    // Interface of Instruction Memory
    input  wire        inst_mem_is_valid,
    input  wire [31:0] inst_mem_read_data,
    input  wire [31:0] dmem_read_data_temp,
    input  wire        dmem_write_valid,
    input  wire        dmem_read_valid
);

    // Data Memory Wires
    wire [31:0] dmem_read_data;
    wire        dmem_write_ready;
    wire        dmem_read_ready;
    wire [31:0] dmem_write_address;
    wire [31:0] dmem_read_address;
    wire [1:0]  dmem_read_offset;
    wire [31:0] dmem_write_data;
    wire [3:0]  dmem_write_byte;
    wire        inst_mem_is_ready;
    wire        dmem_read_valid_checker;

    // IF/ID Wires
    wire [31:0] execute_immediate;
    wire        immediate_sel;
    wire [4:0]  src1_select;
    wire [4:0]  src2_select;
    wire [4:0]  dest_reg_sel;
    wire [2:0]  alu_operation;
    wire        arithsubtype;
    wire        mem_write;
    wire        mem_to_reg;
    wire        illegal_inst;
    wire        alu;
    wire        lui;
    wire        jal;
    wire        jalr;
    wire        branch;
    reg         stall_read;
    wire [31:0] instruction;
    wire [31:0] reg_rdata2;
    wire [31:0] reg_rdata1;
    reg  [31:0] regs [31:1];

    // PC Wires
    wire [31:0] pc;
    wire [31:0] inst_fetch_pc;
    reg  [31:0] fetch_pc;

    // Stalls & WB
    wire        wb_stall;
    wire [31:0] next_pc;
    wire [31:0] write_address;
    wire        branch_taken;
    wire        branch_stall;
    wire [31:0] alu_operand1;
    wire [31:0] alu_operand2;

    wire        wb_alu_to_reg;
    wire [31:0] wb_result;
    wire [2:0]  wb_alu_operation;
    wire        wb_mem_write;
    wire        wb_mem_to_reg;
    wire [4:0]  wb_dest_reg_sel;
    wire        wb_branch;
    wire        wb_branch_nxt;
    wire [31:0] wb_write_address;
    wire [1:0]  wb_read_address;
    wire [3:0]  wb_write_byte;
    wire [31:0] wb_write_data;
    wire [31:0] wb_read_data;
    wire [31:0] inst_mem_address;

    assign dmem_write_address      = wb_write_address;
    assign dmem_read_address       = alu_operand1 + execute_immediate;
    assign dmem_read_offset        = dmem_read_address[1:0];
    assign dmem_read_ready         = mem_to_reg;
    assign dmem_write_ready        = wb_mem_write;
    assign dmem_write_data         = wb_write_data;
    assign dmem_write_byte         = wb_write_byte;
    assign dmem_read_data          = dmem_read_data_temp;
    assign dmem_read_valid_checker = 1'b1;

    ////////////////////////////////////////////////////////////////////////////
    // TODO: Register File Forwarding Logic
    //
    // Instructions:
    // - If source register is x0 (5'd0) -> return 32'd0
    // - If WB stage writes to the same register (and not stalled):
    //     forward wb_read_data (for LOAD) or wb_result (for ALU/CSR)
    // - Else read from register file array (regs)
    ////////////////////////////////////////////////////////////////////////////

    assign reg_rdata1 =
        (src1_select == 5'd0) ? /* TODO: 32'd0 */ 32'd0 :
        (!wb_stall && wb_alu_to_reg && (wb_dest_reg_sel == src1_select))
            ? (wb_mem_to_reg ? wb_read_data : wb_result)
            : /* TODO: regs[src1_select] */ regs[src1_select];

    assign reg_rdata2 =
        (src2_select == 5'd0) ? /* TODO: 32'd0 */ 32'd0 :
        (!wb_stall && wb_alu_to_reg && (wb_dest_reg_sel == src2_select))
            ? (wb_mem_to_reg ? wb_read_data : wb_result)
            : /* TODO: regs[src2_select] */ regs[src2_select];

    ////////////////////////////////////////////////////////////////////////////
    // TODO: Register File Writeback Logic
    //
    // On Reset:
    //   - Clear registers x1-x31 to 32'h0
    //
    // On Clock Edge (if wb_alu_to_reg asserted and not stalled):
    //   - Write either wb_read_data (if wb_mem_to_reg) or wb_result (ALU/CSR result)
    ////////////////////////////////////////////////////////////////////////////

    integer i;
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            for (i = 1; i < 32; i = i + 1)
                regs[i] <= /* TODO: 32'h0 */ 32'h0;
        end else if (wb_alu_to_reg && !stall_read && !wb_stall && (wb_dest_reg_sel != 5'd0)) begin
            regs[wb_dest_reg_sel] <= wb_mem_to_reg ? wb_read_data : /* TODO: wb_result */ wb_result;
        end
    end

    // Stall Register
    always @(posedge clk or negedge reset) begin
        if (!reset)
            stall_read <= 1'b1;
        else
            stall_read <= stall;
    end

    // PC Update Logic
    always @(posedge clk or negedge reset) begin
        if (!reset)
            fetch_pc <= RESET;
        else if (!stall_read)
            fetch_pc <= branch_stall ? fetch_pc + 4 : next_pc;
    end

    assign pc_out = fetch_pc;

endmodule
