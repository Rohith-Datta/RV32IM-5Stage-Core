// ============================================================================
// File: memory_stage.v
// Description: Memory Stage for Data Memory Access & Store Formatting
// Project: Pipelined RV32IM RISC-V Core (Feature 1: 5-Stage Upgrade)
// ============================================================================

`timescale 1ns/1ps

module memory_stage (
    // Inputs from EX/MEM
    input  wire        mem_read_i,
    input  wire        mem_write_i,
    input  wire [2:0]  funct3_i,
    input  wire [31:0] alu_result_i,
    input  wire [31:0] store_data_i,

    // Interface to Data Memory
    output wire [31:0] dmem_addr_o,
    output reg  [31:0] dmem_wdata_o,
    output reg  [3:0]  dmem_wstrb_o,
    output wire        dmem_we_o,
    output wire        dmem_re_o
);

    `include "opcode.vh"

    assign dmem_addr_o = alu_result_i;
    assign dmem_re_o   = mem_read_i;
    assign dmem_we_o   = mem_write_i;

    // Formatting store data and byte-write strobe based on funct3 & address
    always @(*) begin
        case (funct3_i)
            SB: begin
                dmem_wdata_o = {4{store_data_i[7:0]}};
                case (alu_result_i[1:0])
                    2'b00:  dmem_wstrb_o = 4'b0001;
                    2'b01:  dmem_wstrb_o = 4'b0010;
                    2'b10:  dmem_wstrb_o = 4'b0100;
                    default:dmem_wstrb_o = 4'b1000;
                endcase
            end

            SH: begin
                dmem_wdata_o = {2{store_data_i[15:0]}};
                dmem_wstrb_o = alu_result_i[1] ? 4'b1100 : 4'b0011;
            end

            SW: begin
                dmem_wdata_o = store_data_i;
                dmem_wstrb_o = 4'b1111;
            end

            default: begin
                dmem_wdata_o = store_data_i;
                dmem_wstrb_o = 4'b1111;
            end
        endcase
    end

endmodule
