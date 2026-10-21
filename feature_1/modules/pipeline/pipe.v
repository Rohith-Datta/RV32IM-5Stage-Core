// ============================================================================
// File: pipe.v
// Description: Backward-Compatible Wrapper for 5-Stage RV32I Core
// Project: Pipelined RV32IM RISC-V Core (Feature 1: 5-Stage Upgrade)
// ============================================================================

`timescale 1ns/1ps

module pipe
#(
    parameter [31:0] RESET = 32'h0000_0000
)
(
    input  wire        clk,
    input  wire        reset,      // Active-low reset
    input  wire        stall,
    output wire        exception,
    output wire [31:0] pc_out,

    // Instruction memory interface
    input  wire        inst_mem_is_valid,
    input  wire [31:0] inst_mem_read_data,

    // Data memory interface
    input  wire [31:0] dmem_read_data_temp,
    input  wire        dmem_write_valid,
    input  wire        dmem_read_valid
);

    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we;
    wire        dmem_re;

    wire [31:0] pc_if;
    wire [31:0] pc_wb;
    wire        wb_reg_write;
    wire [4:0]  wb_dest_reg;
    wire [31:0] wb_data;

    // Direct interface wires for testbench probing
    wire [31:0] inst_mem_address = pc_if;
    wire [31:0] dmem_write_address = dmem_addr;
    wire [31:0] dmem_read_address = dmem_addr;
    wire [31:0] dmem_write_data = dmem_wdata;
    wire [3:0]  dmem_write_byte = dmem_wstrb;
    wire        dmem_write_ready = dmem_we;
    wire        dmem_read_ready = dmem_re;

    pipeline_5stage #(
        .RESET_PC(RESET)
    ) u_core (
        .clk            (clk),
        .reset_n        (reset),
        .stall_ext      (stall),
        .imem_addr      (pc_if),
        .imem_rdata     (inst_mem_read_data),
        .dmem_addr      (dmem_addr),
        .dmem_wdata     (dmem_wdata),
        .dmem_wstrb     (dmem_wstrb),
        .dmem_we        (dmem_we),
        .dmem_re        (dmem_re),
        .dmem_rdata     (dmem_read_data_temp),
        .pc_if          (pc_if),
        .pc_id          (),
        .pc_ex          (),
        .pc_mem         (),
        .pc_wb          (pc_wb),
        .wb_reg_write   (wb_reg_write),
        .wb_dest_reg    (wb_dest_reg),
        .wb_data        (wb_data),
        .hazard_stall   (),
        .hazard_flush_id(),
        .hazard_flush_ex(),
        .forward_a      (),
        .forward_b      (),
        .exception      (exception)
    );

    assign pc_out = pc_if;

endmodule
