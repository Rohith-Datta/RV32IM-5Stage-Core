// ============================================================================
// File: memory.v
// Description: Instruction Memory (IMEM) and Data Memory (DMEM) Models
// Project: Pipelined RV32IM RISC-V Core (Feature 7: BTB)
// ============================================================================

`timescale 1ns/1ps

// ----------------------------------------------------------------------------
// Instruction Memory (IMEM)
// ----------------------------------------------------------------------------
module instr_mem
#(
    parameter HEX_FILE = "imem.hex",
    parameter WORDS    = 1024
)
(
    input  wire        clk,
    input  wire [31:0] pc,     // Byte address
    output wire [31:0] instr   // Fetched instruction
);

    // 1024 words = 4 KB memory (distributed RAM / LUT ROM for combinational read)
    (* ram_style = "distributed" *)
    reg [31:0] imem [0:WORDS-1];

    integer init_i;
    initial begin
        for (init_i = 0; init_i < WORDS; init_i = init_i + 1)
            imem[init_i] = 32'h0000_0013; // default nop
        // Pre-initialize with compiled btb.c instructions for robust synthesis
        imem[0]  = 32'hfe010113; // addi sp,sp,-32
        imem[1]  = 32'h00112e23; // sw ra,28(sp)
        imem[2]  = 32'h00812c23; // sw s0,24(sp)
        imem[3]  = 32'h02010413; // addi s0,sp,32
        imem[4]  = 32'hfe042623; // sw zero,-20(s0)
        imem[5]  = 32'hfe042423; // sw zero,-24(s0)
        imem[6]  = 32'h0200006f; // j 38 <main+0x38>
        imem[7]  = 32'hfec42703; // lw a4,-20(s0)
        imem[8]  = 32'hfe842783; // lw a5,-24(s0)
        imem[9]  = 32'h00f707b3; // add a5,a4,a5
        imem[10] = 32'hfef42623; // sw a5,-20(s0)
        imem[11] = 32'hfe842783; // lw a5,-24(s0)
        imem[12] = 32'h00178793; // addi a5,a5,1
        imem[13] = 32'hfef42423; // sw a5,-24(s0)
        imem[14] = 32'hfe842703; // lw a4,-24(s0)
        imem[15] = 32'h00300793; // li a5,3
        imem[16] = 32'hfce7dee3; // bge a5,a4,1c <main+0x1c>
        imem[17] = 32'hfec42783; // lw a5,-20(s0)
        imem[18] = 32'h00078513; // mv a0,a5
        imem[19] = 32'h01c12083; // lw ra,28(sp)
        imem[20] = 32'h01812403; // lw s0,24(sp)
        imem[21] = 32'h02010113; // addi sp,sp,32
        imem[22] = 32'h00008067; // ret
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
    parameter HEX_FILE = "dmem.hex",
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

    integer dmem_init_i;
    initial begin
        for (dmem_init_i = 0; dmem_init_i < WORDS; dmem_init_i = dmem_init_i + 1)
            dmem[dmem_init_i] = 32'h0000_0000;
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
