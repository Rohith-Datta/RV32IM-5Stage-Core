// ============================================================================
// File: memory.v
// Description: Instruction Memory (IMEM) and Data Memory (DMEM) Models
// Project: Pipelined RV32IMF RISC-V Core (Feature 9: Zbb Bit Manipulation)
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

        // Pre-initialize with Zbb Exhaustive Verification Program for robust synthesis
        imem[0]  = 32'hffe00093; // 0x00: addi x1, x0, -2
        imem[1]  = 32'h00500113; // 0x04: addi x2, x0, 5
        imem[2]  = 32'h401171b3; // 0x08: andn x3, x2, x1
        imem[3]  = 32'h40116233; // 0x0C: orn  x4, x2, x1
        imem[4]  = 32'h401142b3; // 0x10: xnor x5, x2, x1
        imem[5]  = 32'h0a20e333; // 0x14: max  x6, x1, x2
        imem[6]  = 32'h0a20f3b3; // 0x18: maxu x7, x1, x2
        imem[7]  = 32'h0a20c433; // 0x1C: min  x8, x1, x2
        imem[8]  = 32'h0a20d4b3; // 0x20: minu x9, x1, x2
        imem[9]  = 32'hfff00513; // 0x24: addi x10, x0, -1
        imem[10] = 32'h080545b3; // 0x28: zext.h x11, x10
        imem[11] = 32'h60551613; // 0x2C: sext.h x12, x10
        imem[12] = 32'h60451693; // 0x30: sext.b x13, x10
        imem[13] = 32'h0f000713; // 0x34: addi x14, x0, 0x0F0
        imem[14] = 32'h60071793; // 0x38: clz  x15, x14
        imem[15] = 32'h60171813; // 0x3C: ctz  x16, x14
        imem[16] = 32'h60271893; // 0x40: cpop x17, x14
        imem[17] = 32'h60271933; // 0x44: rol  x18, x14, x2
        imem[18] = 32'h602759b3; // 0x48: ror  x19, x14, x2
        imem[19] = 32'h60475a13; // 0x4C: rori x20, x14, 4
        imem[20] = 32'h69875a93; // 0x50: rev8 x21, x14
        imem[21] = 32'h28775b13; // 0x54: orc.b x22, x14
        imem[22] = 32'h00000013; // 0x58: nop

        // Try reading hex file if present
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
