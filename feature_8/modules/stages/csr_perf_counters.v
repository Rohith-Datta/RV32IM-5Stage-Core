// ============================================================================
// File: csr_perf_counters.v
// Module: csr_perf_counters
// Description: Feature 8 - Passive Hardware Performance Counters & CSR Unit
// Compliant with RISC-V Unprivileged & Privileged Specification (Counters)
// Supported 64-bit Passive Counters:
//   - cycle / cycleh       (0xC00 / 0xC80) : Clock cycles elapsed
//   - time / timeh         (0xC01 / 0xC81) : Real-time timer ticks (mirrors cycle)
//   - instret / instreth   (0xC02 / 0xC82) : Instructions retired/committed
//   - hpmcounter3 / 3h     (0xC03 / 0xC83) : Pipeline stall cycles (load-use, DIV, FPU)
//   - hpmcounter4 / 4h     (0xC04 / 0xC84) : Branch & Jump instructions executed
//   - hpmcounter5 / 5h     (0xC05 / 0xC85) : Branch mispredictions / branch stalls
// ============================================================================

`timescale 1ns/1ps

module csr_perf_counters (
    input  wire        clk,
    input  wire        reset_n,

    // Performance Event Triggers from Pipeline
    input  wire        stall_cycle,       // 1 if pipeline is stalled this cycle
    input  wire        inst_retired,      // 1 if instruction successfully retired in WB
    input  wire        branch_exec,       // 1 if branch/jump executed in EX
    input  wire        branch_mispredict, // 1 if branch mispredicted

    // CSR Read Interface (From ID/EX Stage)
    input  wire [11:0] csr_addr,          // 12-bit CSR address
    output reg  [31:0] csr_rdata,         // 32-bit CSR read value

    // 64-bit Hardware Telemetry Outputs (To FPGA Top / UART Telemetry)
    output wire [63:0] cycle_count_o,
    output wire [63:0] instret_count_o,
    output wire [63:0] stall_count_o,
    output wire [63:0] branch_count_o
);

    `include "opcode.vh"

    // 64-bit Passive Internal Hardware Registers
    reg [63:0] cycle_cnt;
    reg [63:0] instret_cnt;
    reg [63:0] stall_cnt;
    reg [63:0] branch_cnt;
    reg [63:0] mispredict_cnt;

    assign cycle_count_o   = cycle_cnt;
    assign instret_count_o = instret_cnt;
    assign stall_count_o   = stall_cnt;
    assign branch_count_o  = branch_cnt;

    ////////////////////////////////////////////////////////////////////////////
    // TODO 1: Performance Counter Update Logic
    //
    // On Reset:
    //   - Clear all 64-bit counters to 64'd0.
    //
    // On Clock Edge (if reset_n is high):
    //   1. cycle_cnt: Always increments by 1 every clock cycle.
    //   2. instret_cnt: Increments by 1 whenever an instruction commits (inst_retired == 1).
    //   3. stall_cnt: Increments by 1 whenever pipeline stalls (stall_cycle == 1).
    //   4. branch_cnt: Increments by 1 on branch execution (branch_exec == 1).
    //   5. mispredict_cnt: Increments by 1 on branch misprediction (branch_mispredict == 1).
    ////////////////////////////////////////////////////////////////////////////

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            cycle_cnt      <= /* TODO: 64'd0 */ 64'd0;
            instret_cnt    <= /* TODO: 64'd0 */ 64'd0;
            stall_cnt      <= /* TODO: 64'd0 */ 64'd0;
            branch_cnt     <= /* TODO: 64'd0 */ 64'd0;
            mispredict_cnt <= /* TODO: 64'd0 */ 64'd0;
        end else begin
            // Cycle counter increments monotonically every clock
            cycle_cnt <= /* TODO: cycle_cnt + 64'd1 */ cycle_cnt + 64'd1;

            if (inst_retired)
                instret_cnt <= /* TODO: instret_cnt + 64'd1 */ instret_cnt + 64'd1;

            if (stall_cycle)
                stall_cnt <= /* TODO: stall_cnt + 64'd1 */ stall_cnt + 64'd1;

            if (branch_exec)
                branch_cnt <= /* TODO: branch_cnt + 64'd1 */ branch_cnt + 64'd1;

            if (branch_mispredict)
                mispredict_cnt <= /* TODO: mispredict_cnt + 64'd1 */ mispredict_cnt + 64'd1;
        end
    end

    ////////////////////////////////////////////////////////////////////////////
    // TODO 2: Passive CSR Read Address Decode Multiplexer
    //
    // Instructions:
    //   Decode the 12-bit csr_addr and return the corresponding 32-bit slice:
    //   - CSR_CYCLE        (0xC00) -> cycle_cnt[31:0]
    //   - CSR_CYCLEH       (0xC80) -> cycle_cnt[63:32]
    //   - CSR_TIME         (0xC01) -> cycle_cnt[31:0]
    //   - CSR_TIMEH        (0xC81) -> cycle_cnt[63:32]
    //   - CSR_INSTRET      (0xC02) -> instret_cnt[31:0]
    //   - CSR_INSTRETH     (0xC82) -> instret_cnt[63:32]
    //   - CSR_HPMCOUNTER3  (0xC03) -> stall_cnt[31:0]
    //   - CSR_HPMCOUNTER3H (0xC83) -> stall_cnt[63:32]
    //   - CSR_HPMCOUNTER4  (0xC04) -> branch_cnt[31:0]
    //   - CSR_HPMCOUNTER4H (0xC84) -> branch_cnt[63:32]
    //   - CSR_HPMCOUNTER5  (0xC05) -> mispredict_cnt[31:0]
    //   - CSR_HPMCOUNTER5H (0xC85) -> mispredict_cnt[63:32]
    //   - default          -> 32'h0
    ////////////////////////////////////////////////////////////////////////////

    always @(*) begin
        case (csr_addr)
            CSR_CYCLE:        csr_rdata = /* TODO: cycle_cnt[31:0] */      cycle_cnt[31:0];
            CSR_CYCLEH:       csr_rdata = /* TODO: cycle_cnt[63:32] */     cycle_cnt[63:32];
            CSR_TIME:         csr_rdata = /* TODO: cycle_cnt[31:0] */      cycle_cnt[31:0];
            CSR_TIMEH:        csr_rdata = /* TODO: cycle_cnt[63:32] */     cycle_cnt[63:32];
            CSR_INSTRET:      csr_rdata = /* TODO: instret_cnt[31:0] */    instret_cnt[31:0];
            CSR_INSTRETH:     csr_rdata = /* TODO: instret_cnt[63:32] */   instret_cnt[63:32];
            CSR_HPMCOUNTER3:  csr_rdata = /* TODO: stall_cnt[31:0] */      stall_cnt[31:0];
            CSR_HPMCOUNTER3H: csr_rdata = /* TODO: stall_cnt[63:32] */     stall_cnt[63:32];
            CSR_HPMCOUNTER4:  csr_rdata = /* TODO: branch_cnt[31:0] */     branch_cnt[31:0];
            CSR_HPMCOUNTER4H: csr_rdata = /* TODO: branch_cnt[63:32] */     branch_cnt[63:32];
            CSR_HPMCOUNTER5:  csr_rdata = /* TODO: mispredict_cnt[31:0] */  mispredict_cnt[31:0];
            CSR_HPMCOUNTER5H: csr_rdata = /* TODO: mispredict_cnt[63:32] */ mispredict_cnt[63:32];
            default:          csr_rdata = /* TODO: 32'h0 */                32'h0;
        endcase
    end

endmodule
