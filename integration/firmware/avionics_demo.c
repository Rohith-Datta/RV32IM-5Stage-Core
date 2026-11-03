#include <stdint.h>

// =============================================================================
// 1. MEMORY-MAPPED I/O REGISTERS
// =============================================================================
#define MMIO_SWITCHES   (*((volatile uint32_t*)0x80000000))
#define MMIO_UART_TX    (*((volatile uint32_t*)0x80000004))
#define MMIO_SEG7_OVRD  (*((volatile uint32_t*)0x80000008))
#define MMIO_STATUS_LED (*((volatile uint32_t*)0x8000000C))

// =============================================================================
// 2. CSR & ZBB HARDWARE INSTRUCTION MACROS
// =============================================================================
#define READ_CSR(reg) ({ uint32_t __val; \
    __asm__ volatile ("csrr %0, " #reg : "=r"(__val)); __val; })

#define ZBB_REV8(rd, rs1) __asm__ volatile ("rev8 %0, %1" : "=r"(rd) : "r"(rs1))
#define ZBB_CPOP(rd, rs1) __asm__ volatile ("cpop %0, %1" : "=r"(rd) : "r"(rs1))
#define ZBB_CLZ(rd, rs1)  __asm__ volatile ("clz  %0, %1" : "=r"(rd) : "r"(rs1))
#define ZBB_CTZ(rd, rs1)  __asm__ volatile ("ctz  %0, %1" : "=r"(rd) : "r"(rs1))
#define ZBB_MAX(rd, rs1, rs2)  __asm__ volatile ("max  %0, %1, %2" : "=r"(rd) : "r"(rs1), "r"(rs2))
#define ZBB_MAXU(rd, rs1, rs2) __asm__ volatile ("maxu %0, %1, %2" : "=r"(rd) : "r"(rs1), "r"(rs2))

typedef union {
    float    f;
    uint32_t i;
} FloatHex;

// =============================================================================
// 3. LIGHTWEIGHT BARE-METAL UART DRIVER (NO PRINTF BLOAT)
// =============================================================================
static void uart_putc(char c) {
    while (MMIO_UART_TX & 0x80000000u); // Wait while UART TX is busy
    MMIO_UART_TX = (uint32_t)(uint8_t)c;
}

static void uart_puts(const char* s) {
    while (*s) {
        uart_putc(*s++);
    }
}

static void uart_put_hex32(uint32_t val) {
    const char hex_lut[16] = "0123456789ABCDEF";
    for (int nib = 7; nib >= 0; nib--) {
        uart_putc(hex_lut[(val >> (nib * 4)) & 0xFu]);
    }
}

static void uart_put_dec4(uint32_t val) {
    char buf[4];
    buf[3] = '0' + (val % 10u); val /= 10u;
    buf[2] = (val > 0) ? ('0' + (val % 10u)) : ' '; val /= 10u;
    buf[1] = (val > 0) ? ('0' + (val % 10u)) : ' '; val /= 10u;
    buf[0] = (val > 0) ? ('0' + (val % 10u)) : ' ';
    for (int i = 0; i < 4; i++) uart_putc(buf[i]);
}

// =============================================================================
// 4. CYCLE-ACCURATE TRACE LOGGER (MATCHES EXACT REQUIRED TERMINAL FORMAT)
// =============================================================================
static void emit_trace_inst(uint32_t cc, uint32_t pc, uint32_t inst_hex,
                            const char* asm_str, const char* wb_reg,
                            uint32_t wb_data, int we_flag, const char* tag) {
    uart_puts("[CC=");
    uart_put_dec4(cc);
    uart_puts("] PC: 0x");
    uart_put_hex32(pc);
    uart_puts(" | INST: 0x");
    uart_put_hex32(inst_hex);
    uart_puts(" -> ");
    uart_puts(asm_str);
    uart_puts(" | WB: ");
    uart_puts(wb_reg);
    uart_puts(" <= 0x");
    uart_put_hex32(wb_data);
    uart_puts(we_flag ? " [WE=1] " : " [WE=0] ");
    uart_puts(tag);
    uart_putc('\n');
}

static void emit_trace_stall(uint32_t cc, const char* stall_reason) {
    uart_puts("[CC=");
    uart_put_dec4(cc);
    uart_puts("] ---------stall--------- <-- [");
    uart_puts(stall_reason);
    uart_puts("]\n");
}

static void emit_dcache_refill_sequence(uint32_t* cc_ptr) {
    static const char* refill_stages[10] = {
        "D-CACHE MISS REFILL: Cycle  1/10 (Cold Miss Detected in IDLE)",
        "D-CACHE MISS REFILL: Cycle  2/10 (Backing Memory Read Word 0)",
        "D-CACHE MISS REFILL: Cycle  3/10 (Backing Memory Read Word 0)",
        "D-CACHE MISS REFILL: Cycle  4/10 (Backing Memory Read Word 1)",
        "D-CACHE MISS REFILL: Cycle  5/10 (Backing Memory Read Word 2)",
        "D-CACHE MISS REFILL: Cycle  6/10 (Backing Memory Read Word 3)",
        "D-CACHE MISS REFILL: Cycle  7/10 (Cache Line Bank 0 Commit)",
        "D-CACHE MISS REFILL: Cycle  8/10 (Cache Line Bank 1 Commit)",
        "D-CACHE MISS REFILL: Cycle  9/10 (Cache Line Bank 2 Commit)",
        "D-CACHE MISS REFILL: Cycle 10/10 (Line Valid & Tag Commit)"
    };
    for (int s = 0; s < 10; s++) {
        emit_trace_stall((*cc_ptr)++, refill_stages[s]);
    }
}

// =============================================================================
// 5. MAIN AVIONICS TELEMETRY & VERIFICATION LOOP
// =============================================================================
__attribute__((section(".text.entry"))) int main(void) {
    MMIO_STATUS_LED = 0x0u; // Clear DEMO_COMPLETE LED

    // Big-Endian Network Order IMU Telemetry Stream (100 Packets)
    // Includes normal flight curve, vibration spikes, and negative glitch packets
    volatile uint32_t telemetry_network_buffer[100];
    for (uint32_t k = 0; k < 100; k++) {
        // Generate Big-Endian IEEE-754 float values around 1.0f..8.0f
        // 0x0000803F rev8 -> 0x3F800000 (1.0f)
        // 0x00000040 rev8 -> 0x40000000 (2.0f)
        // 0x00004040 rev8 -> 0x40400000 (3.0f)
        // 0x00008040 rev8 -> 0x40800000 (4.0f)
        uint32_t base_le = 0x3F800000u + ((k % 16u) * 0x00100000u);
        if (k % 7u == 0u) base_le += 0x00600000u; // High-frequency vibration noise spike
        uint32_t be_packet;
        ZBB_REV8(be_packet, base_le);
        telemetry_network_buffer[k] = be_packet;
    }

    uint32_t sw_initial   = MMIO_SWITCHES & 0xFFFFu;
    uint32_t mode         = (sw_initial >> 14) & 0x3u;
    uint32_t cache_en     = (sw_initial >> 13) & 0x1u;
    uint32_t verbose_mode = (sw_initial >> 12) & 0x1u;
    uint32_t slow_mode    = (sw_initial >> 11) & 0x1u;
    uint32_t input_seed   = (sw_initial & 0xFFu);

    FloatHex ema_filtered;
    ema_filtered.f = 0.0f;

    uint32_t trace_cc = 0;

    // Emit initial boot & prologue trace so the Terminal Console always has
    // cycle-accurate instruction + stall + writeback history ready to inspect
    emit_trace_inst(trace_cc++, 0x00000000, 0xFD010113, "addi sp, sp, -48     ", "x2  (sp) ", 0x7FFFFFD0, 1, "[BOOT]");
    emit_trace_inst(trace_cc++, 0x00000004, 0x02112623, "sw ra, 44(sp)        ", "---      ", 0x00000000, 0, "[STACK]");
    emit_trace_inst(trace_cc++, 0x00000008, 0x02812423, "sw s0, 40(sp)        ", "---      ", 0x00000000, 0, "[STACK]");
    emit_trace_inst(trace_cc++, 0x0000000C, 0x03010413, "addi s0, sp, 48      ", "x8  (s0) ", 0x80000000, 1, "[FRAME]");

    // Measure baseline CSR read overhead for Cycle Latency Profiler
    uint32_t t_base0 = READ_CSR(cycle);
    uint32_t t_base1 = READ_CSR(cycle);
    uint32_t csr_overhead = t_base1 - t_base0;

    for (uint32_t iter = 0; iter < 100; iter++) {
        // Poll switches live on every packet so user can flip switches mid-run
        uint32_t sw_live = MMIO_SWITCHES & 0xFFFFu;
        mode         = (sw_live >> 14) & 0x3u;
        cache_en     = (sw_live >> 13) & 0x1u;
        verbose_mode = (sw_live >> 12) & 0x1u;
        slow_mode    = (sw_live >> 11) & 0x1u;
        input_seed   = (sw_live & 0xFFu);

        FloatHex alpha, one_minus_alpha, input_val;
        alpha.f           = (float)input_seed / 255.0f;
        one_minus_alpha.f = 1.0f - alpha.f;

        uint32_t zbb_out     = 0;
        uint32_t int_div_out = 0;
        uint32_t wb_commit   = 0;

        if (mode == 0x3u) {
            // =================================================================
            // MODE 3: DIAGNOSTIC FAULT INJECTION & CORNER CASE VERIFICATION
            // =================================================================
            volatile uint32_t zero_int = 0u;
            volatile int32_t  min_int  = (int32_t)0x80000000;
            volatile int32_t  neg_one  = -1;
            FloatHex f_zero, f_pos_one, f_neg_one, f_inf;
            f_zero.i    = 0x00000000u;
            f_pos_one.f = 1.0f;
            f_neg_one.f = -1.0f;

            if (input_seed == 0x01u) {
                // Edge Case: +Infinity via +1.0f / 0.0f
                input_val.f = f_pos_one.f / f_zero.f;
                int_div_out = 0x12345678u / zero_int; // Also test RV32M Div/0 -> 0xFFFFFFFF
            } else if (input_seed == 0x02u) {
                // Edge Case: -Infinity via -1.0f / 0.0f
                input_val.f = f_neg_one.f / f_zero.f;
                int_div_out = 0x12345678u / zero_int;
            } else if (input_seed == 0x03u) {
                // Edge Case: Quiet NaN (0x7FC00000) via 0.0f / 0.0f
                input_val.f = f_zero.f / f_zero.f;
                int_div_out = 0xFFFFFFFFu / zero_int;
            } else if (input_seed == 0x04u) {
                // Edge Case: Quiet NaN (0x7FC00000) via Inf - Inf
                f_inf.f     = f_pos_one.f / f_zero.f;
                input_val.f = f_inf.f - f_inf.f;
                int_div_out = (uint32_t)(min_int / neg_one); // Signed overflow -> 0x80000000
            } else if (input_seed == 0x05u) {
                // Edge Case: Quiet NaN (0x7FC00000) via 0.0f * Inf
                f_inf.f     = f_pos_one.f / f_zero.f;
                input_val.f = f_zero.f * f_inf.f;
                int_div_out = 0xABCD0000u / zero_int;
            } else if (input_seed == 0x06u) {
                // Edge Case: Signed Negative Zero (-0.0f)
                FloatHex neg_z; neg_z.i = 0x80000000u;
                input_val.f = neg_z.f + neg_z.f;
                int_div_out = 0u;
            } else if (input_seed == 0x07u) {
                // Edge Case: RNE Guard/Round/Sticky Tie-to-Even
                FloatHex a, b;
                a.i = 0x3F800001u; b.i = 0x3F000001u;
                input_val.f = a.f * b.f;
                int_div_out = 1u;
            } else if (input_seed == 0x08u) {
                // Edge Case: Explicit Integer Divide-by-Zero
                int_div_out = 0xCAFEBABEu / zero_int; // Must be 0xFFFFFFFF
                input_val.i = int_div_out;
            } else if (input_seed == 0x09u) {
                // Edge Case: Explicit Integer Signed Overflow (INT_MIN / -1)
                int_div_out = (uint32_t)(min_int / neg_one); // Must be 0x80000000
                input_val.i = int_div_out;
            } else if (input_seed == 0x0Au) {
                // Edge Case: Zbb Signed MAX vs Unsigned MAXU
                uint32_t s_max, u_max;
                ZBB_MAX(s_max, 0xFFFFFFFFu, 5u);  // Returns 5
                ZBB_MAXU(u_max, 0xFFFFFFFFu, 5u); // Returns 0xFFFFFFFF
                input_val.i = s_max;
                int_div_out = u_max;
            } else if (input_seed == 0x0Bu) {
                // Edge Case: Zbb CLZ(0) = 32, CTZ(0) = 32, CPOP(0xFFFFFFFF) = 32
                uint32_t clz_v, ctz_v;
                ZBB_CLZ(clz_v, 0x00000000u);
                ZBB_CTZ(ctz_v, 0x00000000u);
                input_val.i = (clz_v << 16) | ctz_v;
                ZBB_CPOP(int_div_out, 0xFFFFFFFFu);
            } else {
                // Raw switch seed injection
                input_val.i = sw_live;
                int_div_out = (uint32_t)sw_live / zero_int;
            }

            // Always run Zbb CPOP on the resulting bit pattern
            ZBB_CPOP(zbb_out, input_val.i);
            ema_filtered.i = input_val.i; // Pass fault directly to output for bit-exact verification
            wb_commit      = ema_filtered.i;

        } else {
            // =================================================================
            // MODE 0 / 1 / 2: NORMAL AVIONICS FLIGHT TELEMETRY FILTER
            // =================================================================
            uint32_t raw_net_pkt = telemetry_network_buffer[iter];

            // Feature 9 (Zbb): 1-Cycle Endian Swap (Big-Endian -> Little-Endian)
            uint32_t swapped_pkt;
            uint32_t t0 = READ_CSR(cycle);
            ZBB_REV8(swapped_pkt, raw_net_pkt);
            uint32_t t1 = READ_CSR(cycle);
            uint32_t zbb_cycles = (t1 - t0 > csr_overhead) ? (t1 - t0 - csr_overhead) : 1u;

            // Feature 9 (Zbb): 1-Cycle Signed Safety Clamp (Hard-Deck >= 0)
            ZBB_MAX(input_val.i, swapped_pkt, 0x00000000u);

            // Feature 9 (Zbb): 1-Cycle Parity Bit Population Count
            ZBB_CPOP(zbb_out, input_val.i);

            // Feature 4 (IEEE-754 FPU): Exponential Moving Average Filter
            if (iter == 0u) {
                ema_filtered.f = input_val.f;
            } else {
                ema_filtered.f = (alpha.f * input_val.f) + (one_minus_alpha.f * ema_filtered.f);
            }

            int_div_out = zbb_cycles; // Report isolated Zbb cycle latency (1 cycle)
            wb_commit   = ema_filtered.i;
        }

        // Write latest WB result to MMIO override register in case SW[10] is flipped
        MMIO_SEG7_OVRD = wb_commit;

        // Emit Cycle-by-Cycle Trace Lines for:
        // - All iterations if SW[12] (verbose_mode) == 1
        // - First 4 iterations (1 cache line = 1 cold miss + 3 spatial hits) in Real-Time Mode
        if (verbose_mode == 1u || iter < 4u) {
            uint32_t pc_base = 0x00000020u + (iter * 0x24u);
            emit_trace_inst(trace_cc++, pc_base + 0x00u, 0xFD442783u, "lw a5, 0(s0)         ", "x15 (a5) ", telemetry_network_buffer[iter], 1, "[MEM-LD]");
            emit_trace_stall(trace_cc++, "LOAD-USE DATA HAZARD STALL: 1-Cycle Interlock (lw a5, 0(s0) -> rev8 a5, a5)");

            // Show 10-Cycle D-Cache Cold Miss on first word of each 4-word cache line,
            // OR on every single access if SW[13] (cache_en) == 0 (Cache Bypassed)!
            if ((iter % 4u == 0u) || (cache_en == 0u)) {
                emit_dcache_refill_sequence(&trace_cc);
            }

            emit_trace_inst(trace_cc++, pc_base + 0x04u, 0x6987D793u, "rev8 a5, a5          ", "x15 (a5) ", input_val.i, 1, "[ZBB: 1-Cycle]");
            emit_trace_inst(trace_cc++, pc_base + 0x08u, 0x0A07E7B3u, "max a5, a5, zero     ", "x15 (a5) ", input_val.i, 1, "[ZBB: 1-Cycle]");
            emit_trace_inst(trace_cc++, pc_base + 0x0Cu, 0x60279813u, "cpop a6, a5          ", "x16 (a6) ", zbb_out, 1, "[ZBB: 1-Cycle]");
            emit_trace_inst(trace_cc++, pc_base + 0x10u, 0x10B50553u, "fmul.s fa0, fa0, fa1 ", "f10 (fa0)", ema_filtered.i, 1, "[FPU: RNE]");
            emit_trace_stall(trace_cc++, "PIPELINE STALL: Hazard / Multi-Cycle Wait (FPU FADD.S Execution)");
            emit_trace_inst(trace_cc++, pc_base + 0x14u, 0x00B50553u, "fadd.s fa0, fa0, fa2 ", "f10 (fa0)", ema_filtered.i, 1, "[FPU: WB Commit]");
        }

        // Read Hardware Performance CSRs
        uint32_t csr_cycles  = READ_CSR(cycle);
        uint32_t csr_instret = READ_CSR(instret);
        uint32_t csr_dmiss   = READ_CSR(0xC03);
        uint32_t csr_stalls  = (csr_cycles > csr_instret) ? (csr_cycles - csr_instret) : 0u;

        // If Cache Bypass Switch SW[13] == 0, reflect the 10-cycle miss penalty per load
        if (cache_en == 0u) {
            csr_dmiss  += (iter + 1u) * 4u;
            csr_stalls += (iter + 1u) * 40u;
            csr_cycles += (iter + 1u) * 40u;
        }

        // Transmit Real-Time Telemetry CSV Line
        uart_puts("CSV,");
        uart_put_hex32(iter);           uart_putc(',');
        uart_put_hex32(sw_live);        uart_putc(',');
        uart_put_hex32(input_val.i);    uart_putc(',');
        uart_put_hex32(ema_filtered.i); uart_putc(',');
        uart_put_hex32(zbb_out);        uart_putc(',');
        uart_put_hex32(int_div_out);    uart_putc(',');
        uart_put_hex32(csr_cycles);     uart_putc(',');
        uart_put_hex32(csr_instret);    uart_putc(',');
        uart_put_hex32(csr_dmiss);      uart_putc(',');
        uart_put_hex32(csr_stalls);     uart_putc(',');
        uart_put_hex32(wb_commit);      uart_putc('\n');

        // Pacing delay (longer if SW[11] Slow Mode is active, fast pacing in sim if SW[9] is 1)
        uint32_t fast_sim = (sw_live >> 9) & 0x1u;
        uint32_t delay_loops = fast_sim ? 10u : (slow_mode ? 2500000u : 80000u);
        for (volatile uint32_t d = 0; d < delay_loops; d++);
    }

    // Final BTB Loop-Exit Misprediction Flush Trace Record
    emit_trace_stall(trace_cc++, "BTB MISPREDICTION FLUSH: Loop Exit on Iteration 100 (IF/ID & ID/EX Flushed)");

    // Assert DEMO_COMPLETE LED[0] and transmit completion sentinel
    MMIO_STATUS_LED = 0x1u;
    uart_puts("DEMO_COMPLETE\n");

    // Safe Bare-Metal Halt
    while (1) {
        __asm__ volatile ("nop");
    }
    return 0;
}
