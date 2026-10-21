// ============================================================================
// File: writeback_stage.v
// Description: Writeback Stage with Load Data Formatting & Result Mux
// Project: Pipelined RV32IM RISC-V Core (Feature 1: 5-Stage Upgrade)
// ============================================================================

`timescale 1ns/1ps

module writeback_stage (
    // Inputs from MEM/WB
    input  wire        mem_to_reg_i,
    input  wire        reg_write_i,
    input  wire [2:0]  funct3_i,
    input  wire [1:0]  byte_offset_i,
    input  wire [31:0] alu_result_i,
    input  wire [31:0] mem_rdata_i,
    input  wire [4:0]  rd_i,

    // Outputs to Register File & Hazard/Debug
    output wire        wb_reg_write_o,
    output wire [4:0]  wb_dest_reg_o,
    output wire [31:0] wb_data_o
);

    `include "opcode.vh"

    reg [31:0] formatted_load_data;

    // Load data formatting based on alignment and sign/zero extension
    always @(*) begin
        case (funct3_i)
            LB: begin
                case (byte_offset_i)
                    2'b00:   formatted_load_data = {{24{mem_rdata_i[7]}},  mem_rdata_i[7:0]};
                    2'b01:   formatted_load_data = {{24{mem_rdata_i[15]}}, mem_rdata_i[15:8]};
                    2'b10:   formatted_load_data = {{24{mem_rdata_i[23]}}, mem_rdata_i[23:16]};
                    default: formatted_load_data = {{24{mem_rdata_i[31]}}, mem_rdata_i[31:24]};
                endcase
            end

            LH: begin
                formatted_load_data = byte_offset_i[1] ? {{16{mem_rdata_i[31]}}, mem_rdata_i[31:16]} :
                                                         {{16{mem_rdata_i[15]}}, mem_rdata_i[15:0]};
            end

            LW: begin
                formatted_load_data = mem_rdata_i;
            end

            LBU: begin
                case (byte_offset_i)
                    2'b00:   formatted_load_data = {24'h0, mem_rdata_i[7:0]};
                    2'b01:   formatted_load_data = {24'h0, mem_rdata_i[15:8]};
                    2'b10:   formatted_load_data = {24'h0, mem_rdata_i[23:16]};
                    default: formatted_load_data = {24'h0, mem_rdata_i[31:24]};
                endcase
            end

            LHU: begin
                formatted_load_data = byte_offset_i[1] ? {16'h0, mem_rdata_i[31:16]} :
                                                         {16'h0, mem_rdata_i[15:0]};
            end

            default: formatted_load_data = mem_rdata_i;
        endcase
    end

    // Final result selection
    assign wb_data_o      = mem_to_reg_i ? formatted_load_data : alu_result_i;
    assign wb_reg_write_o = reg_write_i;
    assign wb_dest_reg_o  = rd_i;

endmodule
