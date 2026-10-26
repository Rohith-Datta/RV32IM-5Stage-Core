// ============================================================================
// File: pipe.v
// Module: pipe (Feature 7: Student Template / Wrapper)
// Description: Course-Style Modular Pipeline Wrapper with TODO Sections
// ============================================================================

`timescale 1ns/1ps

module pipe
#(
    parameter [31:0] RESET = 32'h0000_0000
)
(
    input               clk,
    input               reset,      // Active-low reset (reset_n)
    input               stall,
    output              exception,  
    output      [31:0]  pc_out,

    // Interface of Instruction Memory
    input               inst_mem_is_valid,
    input       [31: 0] inst_mem_read_data,
    input       [31: 0] dmem_read_data_temp,
    input               dmem_write_valid,
    input               dmem_read_valid
);
    
    // Declaring Wires and Registers
    wire        [31: 0] dmem_read_data;
    wire                dmem_write_ready;
    wire                dmem_read_ready;
    wire        [31: 0] dmem_write_address;
    wire        [31: 0] dmem_read_address;
    wire        [1:0]   dmem_read_offset;
    wire        [31: 0] dmem_write_data;
    wire        [ 3: 0] dmem_write_byte;
    wire                inst_mem_is_ready;
    wire                dmem_read_valid_checker;
    
    // Instruction Fetch/Decode Stage Signals
    reg         [31: 0] immediate;
    wire                immediate_sel;
    wire        [ 4: 0] src1_select;
    wire        [ 4: 0] src2_select;
    wire        [ 4: 0] dest_reg_sel;
    wire        [ 2: 0] alu_operation;
    wire                arithsubtype;
    wire                mem_write;
    wire                mem_to_reg;
    wire                illegal_inst;
    wire        [31: 0] execute_immediate;
    wire                alu;
    wire                lui;
    wire                jal;
    wire                jalr;
    wire                branch;
    reg                 stall_read;
    wire        [31: 0] instruction;
    wire        [31: 0] reg_rdata2;
    wire        [31: 0] reg_rdata1;
    reg         [31: 0] regs [31: 1];

    // PC Signals
    wire        [31: 0] pc;
    wire        [31: 0] inst_fetch_pc;
    reg         [31: 0] fetch_pc;  

    // Stalls & Flushes
    wire                wb_stall_first;
    wire                wb_stall_second;
    wire                wb_stall;        
         
    // Execute Stage Signals
    wire        [31: 0] next_pc;
    wire        [31: 0] write_address;
    wire                branch_taken;
    wire                branch_stall;
    wire        [31: 0] alu_operand1;
    wire        [31: 0] alu_operand2;

    // Write Back Signals
    wire                wb_alu_to_reg;
    wire        [31: 0] wb_result;
    wire        [ 2: 0] wb_alu_operation;
    wire                wb_mem_write;
    wire                wb_mem_to_reg;
    wire        [ 4: 0] wb_dest_reg_sel;
    wire                wb_branch;
    wire                wb_branch_nxt;
    wire        [31: 0] wb_write_address;
    wire        [ 1: 0] wb_read_address;
    wire        [ 3: 0] wb_write_byte;
    wire        [31: 0] wb_write_data;
    wire        [31: 0] wb_read_data;
    wire        [31: 0] inst_mem_address;

    // ------------------------------------------------------------------------
    // Memory Interface Assignments
    // ------------------------------------------------------------------------
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
    // TODO: Register File Forwarding (WB Stage -> ID Stage)
    //
    // Instructions:
    // - If src register is x0 (5'd0) -> return 32'd0
    // - If WB stage writes the same register (and not stalled):
    //     Forward wb_read_data (for LOAD) or wb_result (for ALU)
    // - Else -> read from register array (regs[src_select])
    ////////////////////////////////////////////////////////////////////////////

    assign reg_rdata1 = (src1_select == 5'd0) ? /* TODO: 32'd0 */ 32'd0 :
                        (!wb_stall && wb_alu_to_reg && (wb_dest_reg_sel == src1_select))
                        ? (wb_mem_to_reg ? wb_read_data : wb_result)
                        : /* TODO: read from regs */ regs[src1_select];

    assign reg_rdata2 = (src2_select == 5'd0) ? /* TODO: 32'd0 */ 32'd0 :
                        (!wb_stall && wb_alu_to_reg && (wb_dest_reg_sel == src2_select))
                        ? (wb_mem_to_reg ? wb_read_data : wb_result)
                        : /* TODO: read from regs */ regs[src2_select];

    ////////////////////////////////////////////////////////////////////////////
    // TODO: Register File Writeback (WB Stage -> Regs)
    //
    // Instructions:
    // On Reset:
    //   - Clear registers x1-x31 to 0
    // On Valid WB Cycle:
    //   - If wb_alu_to_reg asserted AND no stall:
    //       Write wb_read_data (if LOAD) or wb_result (if ALU) into regs[wb_dest_reg_sel]
    ////////////////////////////////////////////////////////////////////////////

    integer i;
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            for (i = 1; i < 32; i = i + 1)
                regs[i] <= /* TODO: 32'd0 */ 32'd0;
        end
        else if (wb_alu_to_reg && !stall_read && !wb_stall && (wb_dest_reg_sel != 5'd0)) begin
            regs[wb_dest_reg_sel] <= wb_mem_to_reg ? wb_read_data : /* TODO: wb_result */ wb_result;
        end
    end

    // Stall register
    always @(posedge clk or negedge reset) begin
        if (!reset)
            stall_read <= 1'b1;
        else
            stall_read <= stall;
    end

    ////////////////////////////////////////////////////////////////////////////
    // TODO: PC Update Logic
    //
    // On Reset:
    //   - Set fetch_pc = RESET
    // On clock (if not stalled):
    //   - If branch_stall == 1 -> hold branch redirect and step sequentially (fetch_pc + 4)
    //   - Else -> update fetch_pc with next_pc
    ////////////////////////////////////////////////////////////////////////////

    always @(posedge clk or negedge reset) begin
        if (!reset)
            fetch_pc <= RESET;
        else if (!stall_read)
            fetch_pc <= branch_stall ? /* TODO: fetch_pc + 4 */ (fetch_pc + 4) : /* TODO: next_pc */ next_pc;
    end

    assign pc_out = fetch_pc;

    // Pipeline core instantiation
    pipeline_5stage #(
        .RESET_PC(RESET)
    ) u_core (
        .clk             (clk),
        .reset_n         (reset),
        .stall_ext       (stall),
        .use_dsp_i       (1'b1),
        .imem_addr       (inst_mem_address),
        .imem_rdata      (inst_mem_read_data),
        .dmem_addr       (),
        .dmem_wdata      (),
        .dmem_wstrb      (),
        .dmem_we         (),
        .dmem_re         (),
        .dmem_rdata      (dmem_read_data_temp),
        .pc_if           (pc),
        .pc_id           (),
        .pc_ex           (),
        .pc_mem          (),
        .pc_wb           (),
        .wb_reg_write    (wb_alu_to_reg),
        .wb_dest_reg     (wb_dest_reg_sel),
        .wb_data         (wb_result),
        .hazard_stall    (wb_stall),
        .hazard_flush_id (),
        .hazard_flush_ex (),
        .forward_a       (),
        .forward_b       (),
        .mul_active      (),
        .div_active      (),
        .div_busy        (),
        .fpu_active      (),
        .fpu_busy        (),
        .exception       (exception),
        .btb_pred_hit    (),
        .btb_pred_taken  (),
        .btb_mispredict  ()
    );

endmodule
