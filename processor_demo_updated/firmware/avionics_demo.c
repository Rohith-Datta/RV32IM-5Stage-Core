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
// 5. MAIN AVIONICS TELEMETRY & VERIFICATION LOOP
// =============================================================================
static uint32_t hw_divu(uint32_t a, uint32_t b) { uint32_t r; __asm__ volatile("divu %0,%1,%2":"=r"(r):"r"(a),"r"(b)); return r; }
static uint32_t hw_div(int32_t a, int32_t b) { uint32_t r; __asm__ volatile("div %0,%1,%2":"=r"(r):"r"(a),"r"(b)); return r; }
static float fp_add(float a,float b){float r;__asm__ volatile("fadd.s %0,%1,%2,rne":"=f"(r):"f"(a),"f"(b));return r;}
static float fp_sub(float a,float b){float r;__asm__ volatile("fsub.s %0,%1,%2,rne":"=f"(r):"f"(a),"f"(b));return r;}
static float fp_mul(float a,float b){float r;__asm__ volatile("fmul.s %0,%1,%2,rne":"=f"(r):"f"(a),"f"(b));return r;}
static float fp_div(float a,float b){float r;__asm__ volatile("fdiv.s %0,%1,%2,rne":"=f"(r):"f"(a),"f"(b));return r;}
static uint32_t selftest_failures;
static void check_word(const char *name, uint32_t actual, uint32_t expected) {
    uart_puts("CHECK,");uart_puts(name);uart_putc(',');uart_put_hex32(actual);uart_putc(',');uart_put_hex32(expected);uart_putc('\n');
    if(actual!=expected) selftest_failures++;
}
#define INTEGER_CHECK(name,ins,a,b,expected) do { uint32_t value; __asm__ volatile(ins " %0,%1,%2":"=r"(value):"r"((uint32_t)(a)),"r"((uint32_t)(b))); check_word(name,value,expected); } while(0)
static void check_fp(const char *name, uint32_t op, uint32_t a, uint32_t b, uint32_t expected, uint32_t flags) {
    FloatHex x,y,result;x.i=a;y.i=b;
    __asm__ volatile("csrwi fflags,0":::"memory");
    switch(op) {
        case 0:result.f=fp_add(x.f,y.f);break;
        case 4:result.f=fp_sub(x.f,y.f);break;
        case 8:result.f=fp_mul(x.f,y.f);break;
        default:result.f=fp_div(x.f,y.f);break;
    }
    uint32_t actual_flags=READ_CSR(fflags);
    check_word(name,result.i,expected);
    uart_puts("CHECK,");uart_puts(name);uart_puts("_FLAGS,");uart_put_hex32(actual_flags);uart_putc(',');uart_put_hex32(flags);uart_putc('\n');
    if(actual_flags!=flags) selftest_failures++;
}
static void architectural_selftest(void) {
    uint32_t value;
    static volatile uint32_t hazard_data[4] __attribute__((aligned(16)))={7,0,0x3f800000,0};
    static volatile uint32_t cache_probe[1024] __attribute__((aligned(2048)));
    __asm__ volatile("csrwi fcsr,0":::"memory");
    check_word("FCSR_RESET",READ_CSR(fcsr),0);
    __asm__ volatile("lw t0,0(%1)\nadd %0,t0,t0":"=r"(value):"r"(hazard_data):"t0","memory");
    check_word("LW_ADD_INTERLOCK",value,14);
    __asm__ volatile("lw t0,0(%0)\nsw t0,4(%0)"::"r"(hazard_data):"t0","memory");
    check_word("LW_SW_INTERLOCK",hazard_data[1],7);
    __asm__ volatile("flw ft0,8(%1)\nfmul.s ft1,ft0,ft0,rne\nfmv.x.w %0,ft1":"=r"(value):"r"(hazard_data):"ft0","ft1","memory");
    check_word("FLW_FMUL_F0",value,0x3f800000);
    INTEGER_CHECK("MUL", "mul",10,20,200);
    INTEGER_CHECK("MULH", "mulh",0xffffffff,0xffffffff,0);
    INTEGER_CHECK("MULHSU", "mulhsu",0xffffffff,0xffffffff,0xffffffff);
    INTEGER_CHECK("MULHU", "mulhu",0xffffffff,0xffffffff,0xfffffffe);
    INTEGER_CHECK("DIV_ZERO", "div",0x12345678,0,0xffffffff);
    INTEGER_CHECK("DIVU_ZERO", "divu",0x12345678,0,0xffffffff);
    INTEGER_CHECK("REM_ZERO", "rem",0x12345678,0,0x12345678);
    INTEGER_CHECK("REMU_ZERO", "remu",0x12345678,0,0x12345678);
    INTEGER_CHECK("DIV_OVERFLOW", "div",0x80000000,0xffffffff,0x80000000);
    INTEGER_CHECK("REM_OVERFLOW", "rem",0x80000000,0xffffffff,0);
    ZBB_REV8(value,0x0000803f);check_word("REV8",value,0x3f800000);
    ZBB_CPOP(value,0);check_word("CPOP_ZERO",value,0);
    ZBB_CPOP(value,0xffffffff);check_word("CPOP_ONES",value,32);
    ZBB_CLZ(value,0);check_word("CLZ_ZERO",value,32);
    ZBB_CTZ(value,0);check_word("CTZ_ZERO",value,32);
    INTEGER_CHECK("MAX_SIGNED","max",0xffffffff,5,5);
    INTEGER_CHECK("MAX_UNSIGNED","maxu",0xffffffff,5,0xffffffff);
    check_fp("POS_INF",12,0x3f800000,0,0x7f800000,8);
    check_fp("NEG_INF",12,0xbf800000,0,0xff800000,8);
    check_fp("NAN_DIV",12,0,0,0x7fc00000,16);
    check_fp("NAN_SUB",4,0x7f800000,0x7f800000,0x7fc00000,16);
    check_fp("NAN_MUL",8,0,0x7f800000,0x7fc00000,16);
    check_fp("NEG_ZERO",0,0x80000000,0x80000000,0x80000000,0);
    check_fp("TIE_EVEN",0,0x3f800000,0x33800000,0x3f800000,1);
    check_fp("TIE_ODD",0,0x3f800001,0x33800000,0x3f800002,1);
    check_fp("SUBNORMAL_EXACT",8,0x00800000,0x3f000000,0x00400000,0);
    check_fp("SUBNORMAL_INEXACT",8,1,0x3f000000,0,3);
    check_fp("SUBNORMAL_ADD",0,1,1,2,0);
    check_fp("OVERFLOW",8,0x7f7fffff,0x40000000,0x7f800000,5);
    cache_probe[0]=1;cache_probe[1]=2;cache_probe[2]=3;cache_probe[3]=4;cache_probe[512]=9;
    value=cache_probe[512];
    uint32_t before,after,sum;
    __asm__ volatile("csrr %0,0xc03\nlw t0,0(%3)\nlw t1,4(%3)\nadd %2,t0,t1\nlw t0,8(%3)\nadd %2,%2,t0\nlw t1,12(%3)\nadd %2,%2,t1\ncsrr %1,0xc03"
        :"=&r"(before),"=&r"(after),"=&r"(sum):"r"(cache_probe):"t0","t1","memory");
    check_word("CACHE_SPATIAL_DATA",sum,10);
    check_word("CACHE_SPATIAL_MISSES",after-before,(MMIO_SWITCHES&(1u<<13))?1:4);
    value=cache_probe[512];check_word("CACHE_CONFLICT_DATA",value,9);
    __asm__ volatile("csrr %0,0xc06\nli t0,100\n1:addi t0,t0,-1\nbnez t0,1b\ncsrr %1,0xc06\nmv %2,t0"
       :"=&r"(before),"=&r"(after),"=&r"(value)::"t0","memory");
    check_word("LOOP_100_EXIT",value,0);
    check_word("BTB_MISPREDICT_OBSERVED",after>before,1);
    check_word("ICACHE_HIT_OBSERVED",READ_CSR(0xc0a)>0,(MMIO_SWITCHES>>13)&1);
    check_word("DCACHE_HIT_OBSERVED",READ_CSR(0xc09)>0,(MMIO_SWITCHES>>13)&1);
    check_word("ICACHE_MISS_OBSERVED",READ_CSR(0xc04)>0,1);
    check_word("CSR_CYCLE_ACTIVE",READ_CSR(cycle)>0,1);
    check_word("CSR_INSTRET_ACTIVE",READ_CSR(instret)>0,1);
    check_word("CSR_STALL_ACTIVE",READ_CSR(0xc05)>0,1);
    check_word("SELFTEST_FAILURES",selftest_failures,0);
    __asm__ volatile("csrwi fflags,0":::"memory");
}
#undef INTEGER_CHECK

int main(void) {
    architectural_selftest();
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

    

    // Measure baseline CSR read overhead for Cycle Latency Profiler
    uint32_t t_base0,t_base1;
    __asm__ volatile(".balign 16\ncsrr %0,cycle\ncsrr %1,cycle":"=&r"(t_base0),"=&r"(t_base1)::"memory");
    uint32_t csr_overhead = t_base1 - t_base0;

    uint32_t profile_values[6];
    uint32_t profile_done=0, run_config_changed=0;
    for (uint32_t iter = 0; iter < 100; iter++) {
        // Poll switches live on every packet so user can flip switches mid-run
        uint32_t sw_live = MMIO_SWITCHES & 0xFFFFu;
        if (sw_live != sw_initial) run_config_changed=1;
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
                input_val.f = fp_div(f_pos_one.f,f_zero.f);
                int_div_out = hw_divu(0x12345678u,zero_int); // Also test RV32M Div/0 -> 0xFFFFFFFF
            } else if (input_seed == 0x02u) {
                // Edge Case: -Infinity via -1.0f / 0.0f
                input_val.f = fp_div(f_neg_one.f,f_zero.f);
                int_div_out = hw_divu(0x12345678u,zero_int);
            } else if (input_seed == 0x03u) {
                // Edge Case: Quiet NaN (0x7FC00000) via 0.0f / 0.0f
                input_val.f = fp_div(f_zero.f,f_zero.f);
                int_div_out = hw_divu(0xFFFFFFFFu,zero_int);
            } else if (input_seed == 0x04u) {
                // Edge Case: Quiet NaN (0x7FC00000) via Inf - Inf
                f_inf.f     = fp_div(f_pos_one.f,f_zero.f);
                input_val.f = fp_sub(f_inf.f,f_inf.f);
                int_div_out = hw_div(min_int,neg_one); // Signed overflow -> 0x80000000
            } else if (input_seed == 0x05u) {
                // Edge Case: Quiet NaN (0x7FC00000) via 0.0f * Inf
                f_inf.f     = fp_div(f_pos_one.f,f_zero.f);
                input_val.f = fp_mul(f_zero.f,f_inf.f);
                int_div_out = hw_divu(0xABCD0000u,zero_int);
            } else if (input_seed == 0x06u) {
                // Edge Case: Signed Negative Zero (-0.0f)
                FloatHex neg_z; neg_z.i = 0x80000000u;
                input_val.f = fp_add(neg_z.f,neg_z.f);
                int_div_out = 0u;
            } else if (input_seed == 0x07u) {
                // Edge Case: RNE Guard/Round/Sticky Tie-to-Even
                FloatHex a, b;
                a.i = 0x3F800001u; b.i = 0x3F000001u;
                input_val.f = fp_mul(a.f,b.f);
                int_div_out = 1u;
            } else if (input_seed == 0x08u) {
                // Edge Case: Explicit Integer Divide-by-Zero
                int_div_out = hw_divu(0xCAFEBABEu,zero_int); // Must be 0xFFFFFFFF
                input_val.i = int_div_out;
            } else if (input_seed == 0x09u) {
                // Edge Case: Explicit Integer Signed Overflow (INT_MIN / -1)
                int_div_out = hw_div(min_int,neg_one); // Must be 0x80000000
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
                int_div_out = hw_divu((uint32_t)sw_live,zero_int);
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
                ema_filtered.f = fp_add(fp_mul(alpha.f,input_val.f),fp_mul(one_minus_alpha.f,ema_filtered.f));
            }

            int_div_out = hw_divu(iter + 100u, 7u); // Report isolated Zbb cycle latency (1 cycle)
            wb_commit   = ema_filtered.i;
        }

        if (mode == 2u) {
            static volatile uint32_t thrash[1024] __attribute__((aligned(2048)));
            for(uint32_t j=0;j<16;j++) { uint32_t index=(j&1u)*512u; thrash[index]=iter+j; int_div_out ^= thrash[index]; }
        }
        if (mode == 1u && !profile_done) {
            static volatile uint32_t profile_memory[1024] __attribute__((aligned(2048)));
            uint32_t begin,end,result,miss_window,hit_window;
            float fp_result;
            profile_memory[0]=0x3f800000;
            profile_memory[512]=0x40000000;
            result=profile_memory[512];
#define PROFILE_SAVE(index) profile_values[index]=end-begin-csr_overhead
            __asm__ volatile(".balign 16\ncsrr %0,cycle\nrev8 %2,%3\ncsrr %1,cycle" : "=&r"(begin),"=&r"(end),"=&r"(result):"r"(input_val.i):"memory");
            PROFILE_SAVE(0);
            __asm__ volatile(".balign 16\ncsrr %0,cycle\nlw %2,0(%3)\nadd %2,%2,zero\ncsrr %1,cycle" : "=&r"(begin),"=&r"(end),"=&r"(result):"r"(&profile_memory[0]):"memory");
            miss_window=end-begin-csr_overhead;
            __asm__ volatile(".balign 16\ncsrr %0,cycle\nlw %2,0(%3)\nadd %2,%2,zero\ncsrr %1,cycle" : "=&r"(begin),"=&r"(end),"=&r"(result):"r"(&profile_memory[0]):"memory");
            hit_window=end-begin-csr_overhead;
            profile_values[1]=miss_window>=hit_window ? miss_window-hit_window : 0;
            profile_values[2]=hit_window>=2u ? hit_window-2u : 0;
            __asm__ volatile(".balign 16\ncsrr %0,cycle\nfmul.s %2,%3,%4,rne\ncsrr %1,cycle" : "=&r"(begin),"=&r"(end),"=&f"(fp_result):"f"(input_val.f),"f"(alpha.f):"memory");
            PROFILE_SAVE(3);
            __asm__ volatile(".balign 16\ncsrr %0,cycle\nfdiv.s %2,%3,%4,rne\ncsrr %1,cycle" : "=&r"(begin),"=&r"(end),"=&f"(fp_result):"f"(input_val.f),"f"(alpha.f):"memory");
            PROFILE_SAVE(4);
            __asm__ volatile(".balign 16\ncsrr %0,cycle\ndiv %2,%3,%4\ncsrr %1,cycle" : "=&r"(begin),"=&r"(end),"=&r"(result):"r"(12345678),"r"(13):"memory");
            PROFILE_SAVE(5);
#undef PROFILE_SAVE
            profile_done=1;
        }
        // Write latest WB result to MMIO override register in case SW[10] is flipped
        MMIO_SEG7_OVRD = wb_commit;

        // Both L1 caches: 9 stall cycles + 1 service cycle per cold access.
        // Four independent bypassed words contribute 36u stall cycles, not 40u.
        // Read actual hardware CSRs; do not replace them with modeled products.
        // Refill Cycle 1/9 through Cycle 9/9 comes from hardware DREFILL,
        // not a software loop that would fabricate per-cycle observations.
        // Read Hardware Performance CSRs
        uint32_t csr_cycles  = READ_CSR(cycle);
        uint32_t csr_instret = READ_CSR(instret);
        uint32_t csr_dmiss   = READ_CSR(0xC03);
        uint32_t csr_stalls  = READ_CSR(0xC05);

        uint32_t csr_last_wb = READ_CSR(0xC08);
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
        uart_put_hex32(csr_last_wb);    uart_putc('\n');

        // Pacing delay (longer if SW[11] Slow Mode is active so 7-seg PC is visible)
        uint32_t delay_loops = 0; // UART provides pacing; slow clock is controlled in hardware.
        for (volatile uint32_t d = 0; d < delay_loops; d++);
    }

    // Freeze active-core counter totals before serializing the final summaries.
    uint32_t total_cycles=READ_CSR(cycle);
    uint32_t total_instret=READ_CSR(instret);
    if ((MMIO_SWITCHES & 0xffffu) != sw_initial) run_config_changed=1;
    uart_puts("RUN_STATS,");uart_put_hex32(sw_initial);uart_putc(',');
    uart_put_hex32(total_cycles);uart_putc(',');uart_put_hex32(total_instret);uart_putc(',');
    uart_put_hex32(run_config_changed);uart_putc('\n');
    if (profile_done) {
        const char *names[6]={"REV8_WINDOW","DCACHE_MISS_PENALTY","DCACHE_HIT_SERVICE","FMUL_WINDOW","FDIV_WINDOW","DIV_WINDOW"};
        for(uint32_t n=0;n<6;n++) {
            uart_puts("PROFILE,");uart_puts(names[n]);uart_putc(',');
            uart_put_hex32(profile_values[n]);uart_putc('\n');
        }
    }
    // Assert DEMO_COMPLETE LED[0] and transmit completion sentinel
    uart_puts("DEMO_COMPLETE\n");
    while (MMIO_UART_TX & 0x80000000u) {}
    MMIO_STATUS_LED = 0x1u;

    // Safe Bare-Metal Halt
    while (1) {
        __asm__ volatile ("nop");
    }
    return 0;
}
