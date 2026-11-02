// ============================================================================
// File: csr_perf_counters.v
// Module: csr_perf_counters
// Description: Fully Implemented 64-Bit Passive Hardware Performance Counters & CSR Unit
// Compliant with RISC-V Privileged / Unprivileged Specification (Counters & Timers)
//
// Supported 64-bit Passive CSRs:
//   - cycle / cycleh         (0xC00 / 0xC80) : Monotonic clock cycles elapsed
//   - time / timeh           (0xC01 / 0xC81) : Real-time timer ticks (mirrors cycle)
//   - instret / instreth     (0xC02 / 0xC82) : Instructions retired/committed in WB
//   - hpmcounter3 / 3h       (0xC03 / 0xC83) : Pipeline stall cycles (Hazard/Math/Cache)
//   - hpmcounter4 / 4h       (0xC04 / 0xC84) : Branch & Jump instructions executed
//   - hpmcounter5 / 5h       (0xC05 / 0xC85) : Branch mispredictions
//   - hpmcounter6 / 6h       (0xC06 / 0xC86) : L1 I-Cache miss events
//   - hpmcounter7 / 7h       (0xC07 / 0xC87) : L1 D-Cache miss events
// ============================================================================

`timescale 1ns/1ps

module csr_perf_counters (
    input  wire        clk,
    input  wire        reset_n,

    // Performance Event Triggers from Pipeline & Caches
    input  wire        stall_cycle,       // 1 if pipeline is stalled this cycle
    input  wire        inst_retired,      // 1 if instruction successfully retired in WB
    input  wire        branch_exec,       // 1 if branch/jump executed in EX
    input  wire        branch_mispredict, // 1 if branch mispredicted in EX
    input  wire        icache_miss,       // 1 if I-Cache experienced a miss
    input  wire        dcache_miss,       // 1 if D-Cache experienced a miss

    // CSR Read Interface (From Decode/Execute Stage)
    input  wire [11:0] csr_addr,          // 12-bit CSR address
    output reg  [31:0] csr_rdata,         // 32-bit CSR read value to EX stage

    // 64-bit Hardware Telemetry Outputs (For system observability)
    output wire [63:0] cycle_count_o,
    output wire [63:0] instret_count_o,
    output wire [63:0] stall_count_o,
    output wire [63:0] branch_count_o,
    output wire [63:0] mispredict_count_o
);

    `include "opcode.vh"

    // 64-bit Internal Passive Counters
    reg [63:0] cycle_cnt;
    reg [63:0] instret_cnt;
    reg [63:0] stall_cnt;
    reg [63:0] branch_cnt;
    reg [63:0] mispredict_cnt;
    reg [63:0] icache_miss_cnt;
    reg [63:0] dcache_miss_cnt;

    assign cycle_count_o      = cycle_cnt;
    assign instret_count_o    = instret_cnt;
    assign stall_count_o      = stall_cnt;
    assign branch_count_o     = branch_cnt;
    assign mispredict_count_o = mispredict_cnt;

    // ------------------------------------------------------------------------
    // 1. Monotonic 64-bit Performance Counter Update Logic
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            cycle_cnt       <= 64'd0;
            instret_cnt     <= 64'd0;
            stall_cnt       <= 64'd0;
            branch_cnt      <= 64'd0;
            mispredict_cnt  <= 64'd0;
            icache_miss_cnt <= 64'd0;
            dcache_miss_cnt <= 64'd0;
        end else begin
            // Cycle counter increments monotonically every clock cycle
            cycle_cnt <= cycle_cnt + 64'd1;

            if (inst_retired)
                instret_cnt <= instret_cnt + 64'd1;

            if (stall_cycle)
                stall_cnt <= stall_cnt + 64'd1;

            if (branch_exec)
                branch_cnt <= branch_cnt + 64'd1;

            if (branch_mispredict)
                mispredict_cnt <= mispredict_cnt + 64'd1;

            if (icache_miss)
                icache_miss_cnt <= icache_miss_cnt + 64'd1;

            if (dcache_miss)
                dcache_miss_cnt <= dcache_miss_cnt + 64'd1;
        end
    end

    // ------------------------------------------------------------------------
    // 2. Passive CSR Read Address Decode Multiplexer
    // ------------------------------------------------------------------------
    always @(*) begin
        case (csr_addr)
            CSR_CYCLE:        csr_rdata = cycle_cnt[31:0];
            CSR_CYCLEH:       csr_rdata = cycle_cnt[63:32];
            CSR_TIME:         csr_rdata = cycle_cnt[31:0];
            CSR_TIMEH:        csr_rdata = cycle_cnt[63:32];
            CSR_INSTRET:      csr_rdata = instret_cnt[31:0];
            CSR_INSTRETH:     csr_rdata = instret_cnt[63:32];
            CSR_HPMCOUNTER3:  csr_rdata = stall_cnt[31:0];
            CSR_HPMCOUNTER3H: csr_rdata = stall_cnt[63:32];
            CSR_HPMCOUNTER4:  csr_rdata = branch_cnt[31:0];
            CSR_HPMCOUNTER4H: csr_rdata = branch_cnt[63:32];
            CSR_HPMCOUNTER5:  csr_rdata = mispredict_cnt[31:0];
            CSR_HPMCOUNTER5H: csr_rdata = mispredict_cnt[63:32];
            CSR_HPMCOUNTER6:  csr_rdata = icache_miss_cnt[31:0];
            CSR_HPMCOUNTER6H: csr_rdata = icache_miss_cnt[63:32];
            CSR_HPMCOUNTER7:  csr_rdata = dcache_miss_cnt[31:0];
            CSR_HPMCOUNTER7H: csr_rdata = dcache_miss_cnt[63:32];
            default:          csr_rdata = 32'h0000_0000;
        endcase
    end

endmodule
