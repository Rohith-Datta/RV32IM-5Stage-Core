// ============================================================================
// File: memory_model.v
// Module: memory_model
// Description: Unified Synchronous Main Memory Model for Integration Simulation
// Supports byte-level write strobes and synchronous read latency
// ============================================================================

`timescale 1ns/1ps

module memory_model #(
    parameter MEM_SIZE_WORDS = 65536 // 256 KB memory
)(
    input  wire        clk,
    input  wire        reset_n,
    input  wire        mem_req,
    input  wire [31:0] mem_addr,
    input  wire        mem_we,
    input  wire [31:0] mem_wdata,
    input  wire [3:0]  mem_wstrb,
    output reg  [31:0] mem_rdata
);

    // 32-bit word memory array
    reg [31:0] ram [0:MEM_SIZE_WORDS-1];
    integer i;

    wire [31:0] word_addr = mem_addr[17:2]; // Word-aligned index

    // Initialize memory to 0
    initial begin
        for (i = 0; i < MEM_SIZE_WORDS; i = i + 1) begin
            ram[i] = 32'h0000_0000;
        end
    end

    // Synchronous Read and Byte-Masked Write
    always @(posedge clk) begin
        if (mem_req) begin
            if (mem_we) begin
                if (mem_wstrb[0]) ram[word_addr][7:0]   <= mem_wdata[7:0];
                if (mem_wstrb[1]) ram[word_addr][15:8]  <= mem_wdata[15:8];
                if (mem_wstrb[2]) ram[word_addr][23:16] <= mem_wdata[23:16];
                if (mem_wstrb[3]) ram[word_addr][31:24] <= mem_wdata[31:24];
            end
            mem_rdata <= ram[word_addr];
        end else begin
            mem_rdata <= ram[word_addr];
        end
    end

endmodule
