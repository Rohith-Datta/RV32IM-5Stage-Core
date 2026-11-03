// ============================================================================
// File: mem_bus_arbiter.v
// Module: mem_bus_arbiter
// Description: Centralized Memory Bus Arbiter between L1 I-Cache and L1 D-Cache
//              with Strict Priority for D-Cache over I-Cache to prevent
//              pipeline stalls, starvation, and deadlock.
// Architecture:
//   - When I-Cache and D-Cache request memory simultaneously, D-Cache is GRANTED FIRST.
//   - Once a burst line refill begins, the arbiter locks until the burst completes,
//     ensuring non-interleaved atomic 4-word cache line refills.
// ============================================================================

`timescale 1ns/1ps

module mem_bus_arbiter (
    input  wire        clk,
    input  wire        reset_n,

    // Interface with L1 I-Cache
    input  wire        icache_req,
    input  wire [31:0] icache_addr,
    output wire [31:0] icache_rdata,
    output wire        icache_grant,

    // Interface with L1 D-Cache (Higher Priority)
    input  wire        dcache_req,
    input  wire        dcache_we,
    input  wire [31:0] dcache_addr,
    input  wire [31:0] dcache_wdata,
    input  wire [3:0]  dcache_wstrb,
    output wire [31:0] dcache_rdata,
    output wire        dcache_grant,

    // Interface with Unified / Backing Main Memory
    output reg         main_mem_req,
    output reg  [31:0] main_mem_addr,
    output reg         main_mem_we,
    output reg  [31:0] main_mem_wdata,
    output reg  [3:0]  main_mem_wstrb,
    input  wire [31:0] main_mem_rdata
);

    localparam [1:0] GRANT_IDLE   = 2'b00,
                     GRANT_DCACHE = 2'b01,
                     GRANT_ICACHE = 2'b10;

    reg [1:0] current_grant;

    // Detect if D-Cache is actively requesting memory (refill or store write-through)
    wire dcache_active = dcache_req || dcache_we;
    wire icache_active = icache_req;

    // Grant arbitration state machine
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            current_grant <= GRANT_IDLE;
        end else begin
            case (current_grant)
                GRANT_IDLE: begin
                    // Priority Rule: D-Cache has strict higher priority on simultaneous miss
                    if (dcache_active) begin
                        current_grant <= GRANT_DCACHE;
                    end else if (icache_active) begin
                        current_grant <= GRANT_ICACHE;
                    end
                end

                GRANT_DCACHE: begin
                    // Stay in DCACHE grant while D-Cache is active
                    if (!dcache_active) begin
                        // Once D-Cache finishes, immediately service pending I-Cache request
                        if (icache_active)
                            current_grant <= GRANT_ICACHE;
                        else
                            current_grant <= GRANT_IDLE;
                    end
                end

                GRANT_ICACHE: begin
                    // Stay in ICACHE grant until I-Cache completes its refill
                    if (!icache_active) begin
                        if (dcache_active)
                            current_grant <= GRANT_DCACHE;
                        else
                            current_grant <= GRANT_IDLE;
                    end
                end

                default: current_grant <= GRANT_IDLE;
            endcase
        end
    end

    // Combinational Grant Signals with Strict Priority:
    // When arbiter is in GRANT_ICACHE, I-Cache owns the bus until its 4-word refill completes.
    // When arbiter is in GRANT_DCACHE, D-Cache owns the bus until its transaction completes.
    // When GRANT_IDLE: D-Cache gets first priority if active; otherwise I-Cache.
    wire dcache_has_bus = (current_grant == GRANT_DCACHE) ||
                          ((current_grant == GRANT_IDLE) && dcache_active);
    wire icache_has_bus = (current_grant == GRANT_ICACHE) ||
                          ((current_grant == GRANT_IDLE) && !dcache_active && icache_active);

    assign dcache_grant = dcache_has_bus;
    assign icache_grant = icache_has_bus;

    // Return read data to granted cache
    assign dcache_rdata = main_mem_rdata;
    assign icache_rdata = main_mem_rdata;

    // Multiplex memory bus to Backing Main Memory
    always @(*) begin
        if (dcache_has_bus) begin
            main_mem_req   = dcache_active;
            main_mem_addr  = dcache_addr;
            main_mem_we    = dcache_we;
            main_mem_wdata = dcache_wdata;
            main_mem_wstrb = dcache_wstrb;
        end else if (icache_has_bus) begin
            main_mem_req   = icache_active;
            main_mem_addr  = icache_addr;
            main_mem_we    = 1'b0;
            main_mem_wdata = 32'd0;
            main_mem_wstrb = 4'b0000;
        end else begin
            main_mem_req   = 1'b0;
            main_mem_addr  = 32'd0;
            main_mem_we    = 1'b0;
            main_mem_wdata = 32'd0;
            main_mem_wstrb = 4'b0000;
        end
    end

endmodule
