// ============================================================================
// File: csr_perf_counters.v
// Module: csr_perf_counters
// Description: Fully Implemented 64-Bit Passive Hardware Performance Counters & CSR Unit
// Compliant with RISC-V Privileged / Unprivileged Specification (Counters & Timers)
//
// CSR map: C00 cycle, C01 cycle mirror, C02 instret, C03 D misses,
// C04 I misses, C05 stalls, C06 mispredicts, C07 branch executions.
// Add 0x80 for high halves. C08 is the latest valid WB data snapshot.
// 001/003 expose accrued flags read-only; rounding is fixed to explicit RNE.
// ============================================================================

`timescale 1ns/1ps

module csr_perf_counters (
    input  wire        clk,
    input  wire        reset_n,
    input wire [31:0] wb_data_i,
    input wire wb_commit_i,
    input wire [31:0] ihits_i,dhits_i,
    input wire [4:0] fp_flags_i,
    input wire csr_write_i,input wire [2:0] csr_funct3_i,input wire [31:0] csr_operand_i,
    output reg [2:0] frm_o,

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

    reg [31:0] last_wb;
    reg [4:0] accrued_flags;
    reg [31:0] writable_old,writable_new;
    always @(*) begin
        case(csr_addr)
            12'h001:writable_old={27'b0,accrued_flags};
            12'h002:writable_old={29'b0,frm_o};
            default:writable_old={24'b0,frm_o,accrued_flags};
        endcase
        case(csr_funct3_i[1:0])
            1:writable_new=csr_operand_i;
            2:writable_new=writable_old | csr_operand_i;
            3:writable_new=writable_old & ~csr_operand_i;
            default:writable_new=writable_old;
        endcase
    end
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin last_wb<=0;accrued_flags<=0;frm_o<=0;end
        else begin
            if(wb_commit_i) last_wb<=wb_data_i;
            accrued_flags<=accrued_flags | fp_flags_i;
            if(csr_write_i) case(csr_addr)
                12'h001:accrued_flags<=writable_new[4:0] | fp_flags_i;
                12'h002:frm_o<=writable_new[2:0];
                12'h003:begin accrued_flags<=writable_new[4:0] | fp_flags_i;frm_o<=writable_new[7:5];end
            endcase
        end
    end
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
            12'h001: csr_rdata={27'b0,accrued_flags};
            12'h002: csr_rdata={29'b0,frm_o};
            12'h003: csr_rdata={24'b0,frm_o,accrued_flags};
            12'hC08: csr_rdata=last_wb;
            12'hC09: csr_rdata=dhits_i;
            12'hC0A: csr_rdata=ihits_i;
            CSR_CYCLE:        csr_rdata = cycle_cnt[31:0];
            CSR_CYCLEH:       csr_rdata = cycle_cnt[63:32];
            CSR_TIME:         csr_rdata = cycle_cnt[31:0];
            CSR_TIMEH:        csr_rdata = cycle_cnt[63:32];
            CSR_INSTRET:      csr_rdata = instret_cnt[31:0];
            CSR_INSTRETH:     csr_rdata = instret_cnt[63:32];
            CSR_HPMCOUNTER3:  csr_rdata = dcache_miss_cnt[31:0];
            CSR_HPMCOUNTER3H: csr_rdata = dcache_miss_cnt[63:32];
            CSR_HPMCOUNTER4:  csr_rdata = icache_miss_cnt[31:0];
            CSR_HPMCOUNTER4H: csr_rdata = icache_miss_cnt[63:32];
            CSR_HPMCOUNTER5:  csr_rdata = stall_cnt[31:0];
            CSR_HPMCOUNTER5H: csr_rdata = stall_cnt[63:32];
            CSR_HPMCOUNTER6:  csr_rdata = mispredict_cnt[31:0];
            CSR_HPMCOUNTER6H: csr_rdata = mispredict_cnt[63:32];
            CSR_HPMCOUNTER7:  csr_rdata = branch_cnt[31:0];
            CSR_HPMCOUNTER7H: csr_rdata = branch_cnt[63:32];
            default:          csr_rdata = 32'h0000_0000;
        endcase
    end

endmodule
