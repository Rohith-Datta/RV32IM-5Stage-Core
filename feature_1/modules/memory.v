// ============================================================================
// File: memory.v
// Description: Instruction Memory (IMEM) and Data Memory (DMEM) Models
// Project: Pipelined RV32IM RISC-V Core (Feature 1: 5-Stage Upgrade)
// ============================================================================

`timescale 1ns/1ps

// ----------------------------------------------------------------------------
// Instruction Memory (IMEM)
// ----------------------------------------------------------------------------
module instr_mem
#(
    parameter HEX_FILE = "C:/CS2202L/RISCV/feature_1/mem/imem.hex",
    parameter WORDS    = 1024
)
(
    input  wire        clk,
    input  wire [31:0] pc,     // Byte address
    output wire [31:0] instr   // Fetched instruction
);

    // 1024 words = 4 KB memory
    (* ram_style = "block" *)
    reg [31:0] imem [0:WORDS-1];

    initial begin
        $readmemh(HEX_FILE, imem);
        $display("[IMEM] Loaded instruction memory from: %s", HEX_FILE);
        $display("[IMEM] imem[0] = 0x%08h, imem[1] = 0x%08h", imem[0], imem[1]);
    end

    // Combinational word read using word-aligned address (pc[11:2])
    assign instr = (pc[11:2] < WORDS) ? imem[pc[11:2]] : 32'h0000_0013; // NOP if out of bounds

endmodule


// ----------------------------------------------------------------------------
// Data Memory (DMEM) - Byte-addressable with Strobe Enables
// ----------------------------------------------------------------------------
module data_mem
#(
    parameter HEX_FILE = "C:/CS2202L/RISCV/feature_1/mem/dmem.hex",
    parameter WORDS    = 1024
)
(
    input  wire        clk,

    // Read Port
    input  wire        re,
    input  wire [31:0] raddr,  // Byte address
    output wire [31:0] rdata,

    // Write Port
    input  wire        we,
    input  wire [31:0] waddr,  // Byte address
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb
);

    // 1024 words = 4 KB memory
    reg [31:0] dmem [0:WORDS-1];

    wire [9:0] rindex = raddr[11:2];
    wire [9:0] windex = waddr[11:2];

    initial begin
        $readmemh(HEX_FILE, dmem);
        $display("[DMEM] Loaded data memory from: %s", HEX_FILE);
    end

    // Synchronous Byte-level Write Logic
    always @(posedge clk) begin
        if (we && (windex < WORDS)) begin
            if (wstrb[0]) dmem[windex][7:0]   <= wdata[7:0];
            if (wstrb[1]) dmem[windex][15:8]  <= wdata[15:8];
            if (wstrb[2]) dmem[windex][23:16] <= wdata[23:16];
            if (wstrb[3]) dmem[windex][31:24] <= wdata[31:24];
        end
    end

    // Read Port with internal forwarding for same-cycle read-after-write
    wire [31:0] mem_word = (rindex < WORDS) ? dmem[rindex] : 32'h0;

    assign rdata[7:0]   = (we && (rindex == windex) && wstrb[0]) ? wdata[7:0]   : mem_word[7:0];
    assign rdata[15:8]  = (we && (rindex == windex) && wstrb[1]) ? wdata[15:8]  : mem_word[15:8];
    assign rdata[23:16] = (we && (rindex == windex) && wstrb[2]) ? wdata[23:16] : mem_word[23:16];
    assign rdata[31:24] = (we && (rindex == windex) && wstrb[3]) ? wdata[31:24] : mem_word[31:24];

endmodule
