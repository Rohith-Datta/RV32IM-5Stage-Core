// ============================================================================
// File: fpu_single_core.v
// Description: Complete IEEE 754 Single-Precision Floating-Point Unit (RV32F)
// Project: Pipelined RV32IMF RISC-V Core (Feature 4: IEEE 754 FPU)
// Instructions Supported:
//   - FADD.S : Floating-point Addition       (Latency: EXACTLY 5 cycles)
//   - FSUB.S : Floating-point Subtraction    (Latency: EXACTLY 5 cycles)
//   - FMUL.S : Floating-point Multiplication (Latency: EXACTLY 4 cycles)
//   - FDIV.S : Floating-point Division       (Latency: EXACTLY 15 cycles)
// Compliance:
//   - IEEE 754-2008 Standard 32-bit single-precision floating point
//   - Round to Nearest, ties to Even (RNE) rounding mode
//   - Full handling for zero, infinity, NaN, and divide-by-zero
// Handshaking:
//   - fpu_busy asserted high during execution to interlock hazard unit
//   - fpu_done asserted on the completion cycle
// ============================================================================

`timescale 1ns/1ps

module fpu_single_core (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        is_fpu,        // High when FPU instruction in EX stage
    input  wire [6:0]  funct7,        // FPU operation select (FADD, FSUB, FMUL, FDIV)
    input  wire [2:0]  funct3,        // Rounding mode (FRM_RNE default)
    input  wire [31:0] op_a,          // Float operand A (IEEE 754 single precision)
    input  wire [31:0] op_b,          // Float operand B (IEEE 754 single precision)
    output reg  [31:0] fpu_result,    // IEEE 754 float output
    output wire        fpu_busy,      // Multi-cycle stall interlock to Hazard Unit
    output wire [4:0] flags_o,
    output wire        fpu_done       // High when valid result is ready in EX
);

    `include "opcode.vh"

    // FSM States
    localparam [1:0] S_IDLE = 2'b00,
                     S_CALC = 2'b01,
                     S_DONE = 2'b10;

    reg [1:0]  state;
    reg [3:0]  count;
    reg [6:0]  saved_op;
    reg [2:0]  saved_frm;
    reg [31:0] result_reg;

    // ------------------------------------------------------------------------
    // FADD / FSUB Pipeline Registers
    // ------------------------------------------------------------------------
    reg        fadd_sign_large;
    reg [8:0]  fadd_exp_large;
    reg [27:0] fadd_m_large_ext;
    reg [27:0] fadd_m_small_aligned;
    reg        fadd_eff_sub;
    reg [28:0] fadd_sum;
    reg [27:0] fadd_norm_m;
    reg [8:0]  fadd_norm_e;
    reg        fadd_sticky_round;
    reg [31:0] fadd_final_res;
    reg        fadd_is_zero_res;

    // ------------------------------------------------------------------------
    // FMUL Pipeline Registers
    // ------------------------------------------------------------------------
    reg        fmul_sign_res;
    reg [9:0]  fmul_raw_exp;
    reg [23:0] fmul_mant_a, fmul_mant_b;
    reg [47:0] fmul_prod;
    reg        fmul_zero_res;
    reg [31:0] fmul_final_res;

    // ------------------------------------------------------------------------
    // FDIV Pipeline Registers
    // ------------------------------------------------------------------------
    reg        fdiv_sign_res;
    reg [9:0]  fdiv_exp_res;
    reg [25:0] fdiv_rem;
    reg [23:0] fdiv_denom;
    reg [25:0] fdiv_quot;
    reg        fdiv_div0, fdiv_nan, fdiv_zero_res;
    reg [31:0] fdiv_final_res;

    // ------------------------------------------------------------------------
    // Combinational Input Extraction
    // ------------------------------------------------------------------------
    wire sign_a = op_a[31];
    wire [7:0] exp_a = op_a[30:23];
    wire [22:0] frac_a = op_a[22:0];
    wire a_is_zero = (op_a[30:0] == 31'd0);
    wire a_is_nan  = (exp_a == 8'hFF) && (frac_a != 23'd0);
    wire a_is_inf  = (exp_a == 8'hFF) && (frac_a == 23'd0);

    wire is_sub_op = (funct7 == FUNCT7_FSUB);
    wire sign_b = op_b[31] ^ is_sub_op;
    wire [7:0] exp_b = op_b[30:23];
    wire [22:0] frac_b = op_b[22:0];
    wire b_is_zero = (op_b[30:0] == 31'd0);
    wire b_is_nan  = (exp_b == 8'hFF) && (frac_b != 23'd0);
    wire b_is_inf  = (exp_b == 8'hFF) && (frac_b == 23'd0);

    wire [23:0] mant_a = a_is_zero ? 24'd0 : {exp_a!=0, frac_a};
    wire [23:0] mant_b = b_is_zero ? 24'd0 : {exp_b!=0, frac_b};

    wire [7:0] effective_a = exp_a==0 ? 8'd1 : exp_a;
    wire [7:0] effective_b = exp_b==0 ? 8'd1 : exp_b;
    // Magnitude comparison for Addition/Subtraction
    wire a_greater = (effective_a > effective_b) || ((effective_a == effective_b) && (mant_a >= mant_b));
    wire [7:0] exp_diff_in = a_greater ? (effective_a - effective_b) : (effective_b - effective_a);
    wire [23:0] m_large_in = a_greater ? mant_a : mant_b;
    wire [23:0] m_small_in = a_greater ? mant_b : mant_a;
    wire sign_large_in     = a_greater ? sign_a : sign_b;
    wire sign_small_in     = a_greater ? sign_b : sign_a;

    // Small mantissa alignment shifter (27 bits: mantissa + 3 guard bits)
    wire [26:0] small_ext = {m_small_in, 3'b000};
    wire [4:0]  safe_shift = (exp_diff_in < 8'd27) ? exp_diff_in[4:0] : 5'd0;
    wire [26:0] small_shifted = (exp_diff_in >= 8'd27) ? 27'd0 : (small_ext >> safe_shift);
    wire small_sticky = (exp_diff_in >= 8'd27) ? (|m_small_in) :
                        (|(small_ext & ((27'd1 << safe_shift) - 27'd1)));
    wire [27:0] m_small_aligned = {1'b0, small_shifted[26:1], small_shifted[0] | small_sticky};
    wire [27:0] m_large_aligned = {1'b0, m_large_in, 3'b000};


    // ---- FIX: special cases (NaN / Inf / -0) ----
    localparam [31:0] QNAN = 32'h7FC0_0000;
    reg        sp_valid_c, sp_valid;
    reg [31:0] sp_res_c,   sp_res;
    always @(*) begin
        sp_valid_c = 1'b0;  sp_res_c = 32'd0;
        case (funct7)
            FUNCT7_FDIV: ;
            FUNCT7_FMUL: begin
                if (a_is_nan || b_is_nan || (a_is_inf && b_is_zero) || (a_is_zero && b_is_inf))
                    begin sp_valid_c = 1'b1; sp_res_c = QNAN; end
                else if (a_is_inf || b_is_inf)
                    begin sp_valid_c = 1'b1; sp_res_c = {op_a[31] ^ op_b[31], 8'hFF, 23'd0}; end
            end
            default: begin
                if (a_is_nan || b_is_nan || (a_is_inf && b_is_inf && (sign_a != sign_b)))
                    begin sp_valid_c = 1'b1; sp_res_c = QNAN; end
                else if (a_is_inf) begin sp_valid_c = 1'b1; sp_res_c = {sign_a, 8'hFF, 23'd0}; end
                else if (b_is_inf) begin sp_valid_c = 1'b1; sp_res_c = {sign_b, 8'hFF, 23'd0}; end
                else if (a_is_zero && b_is_zero)
                    begin sp_valid_c = 1'b1; sp_res_c = {sign_a & sign_b, 31'd0}; end
            end
        endcase
    end

    // ---- FIX: rounding-mode aware increment ----
    function round_inc;
        input [2:0] frm; input sign, lsb, g, r, s;
        begin
            case (frm)
                FRM_RTZ: round_inc = 1'b0;
                FRM_RDN: round_inc = sign  && (g | r | s);
                FRM_RUP: round_inc = !sign && (g | r | s);
                FRM_RMM: round_inc = g;
                default: round_inc = g && (r | s | lsb);
            endcase
        end
    endfunction

    // Bounded exponent math, logarithmic MSB search and a 25-bit rounding adder.
    // The former integer/64-bit path inferred long priority and carry chains.
    function [36:0] pack_rne;
        input sign_bit;
        input [63:0] magnitude;
        input signed [11:0] scale;
        input extra_sticky;
        reg [5:0] top;
        reg signed [12:0] e, shift;
        reg [63:0] probe, shifted, discarded;
        reg found,g,sticky,nx,uf,of;
        reg [24:0] rounded;
        reg [31:0] packed_value;
        begin
            top=0;probe=magnitude;found=|magnitude;
            if(|probe[63:32]) begin top=top+32;probe=probe>>32;end
            if(|probe[31:16]) begin top=top+16;probe=probe>>16;end
            if(|probe[15:8]) begin top=top+8;probe=probe>>8;end
            if(|probe[7:4]) begin top=top+4;probe=probe>>4;end
            if(|probe[3:2]) begin top=top+2;probe=probe>>2;end
            if(probe[1]) top=top+1;
            g=0;sticky=extra_sticky;nx=0;uf=0;of=0;discarded=0;shifted=0;
            e=$signed({7'b0,top})+scale+13'sd127;
            shift=e>0 ? $signed({7'b0,top})-13'sd23 : -13'sd149-scale;
            if(shift>0) begin
                shifted=shift>=64 ? 64'b0 : magnitude>>shift[5:0];
                if(shift<=64) begin
                    g=(magnitude>>(shift-1))&1'b1;
                    // Bits strictly below the guard bit, reduced in parallel.
                    discarded=magnitude & (64'hffffffffffffffff >> (13'sd65-shift));
                end else discarded=magnitude;
                sticky=extra_sticky | (|discarded);
                rounded=shifted[24:0];nx=g|sticky;
                if(g && (sticky || rounded[0])) rounded=rounded+25'd1;
            end else begin
                shifted=magnitude<<(-shift);rounded=shifted[24:0];nx=extra_sticky;
            end
            if(!found) packed_value={sign_bit,31'b0};
            else if(e<=0) begin
                if(rounded[23]) packed_value={sign_bit,8'h01,23'b0};
                else begin packed_value={sign_bit,8'b0,rounded[22:0]};uf=nx;end
            end else begin
                if(rounded[24]) begin rounded=rounded>>1;e=e+13'sd1;end
                if(e>=255) begin packed_value={sign_bit,8'hff,23'b0};of=1;nx=1;end
                else packed_value={sign_bit,e[7:0],rounded[22:0]};
            end
            pack_rne={2'b00,of,uf,nx,packed_value};
        end
    endfunction
    function [4:0] clz24;
        input [23:0] value;
        integer k;reg found;
        begin clz24=24;found=0;for(k=23;k>=0;k=k-1) if(value[k]&&!found) begin clz24=23-k;found=1;end end
    endfunction
    wire [4:0] shift_a=clz24(mant_a),shift_b=clz24(mant_b);
    wire [23:0] normal_a=mant_a<<shift_a,normal_b=mant_b<<shift_b;
    wire signed [10:0] normal_ea=$signed({3'b0,effective_a})-$signed({6'b0,shift_a});
    wire signed [10:0] normal_eb=$signed({3'b0,effective_b})-$signed({6'b0,shift_b});
    reg [36:0] packed_result;
    reg [2:0] arithmetic_flags;
    // Leading Zero Counter Function for FADD Normalization (27 bits)
    function [4:0] clz27;
        input [26:0] val;
        integer i;
        reg found;
        begin
            clz27 = 5'd27;
            found = 1'b0;
            for (i = 26; i >= 0; i = i - 1) begin
                if (val[i] && !found) begin
                    clz27 = 5'd26 - i[4:0];
                    found = 1'b1;
                end
            end
        end
    endfunction

    // ------------------------------------------------------------------------
    // Scratch Variables for Procedural Always Block
    // ------------------------------------------------------------------------
    reg [22:0] fmul_frac_raw, fmul_frac_final;
    reg        fmul_g, fmul_r, fmul_s, fmul_round_up;
    reg [9:0]  fmul_norm_e, fmul_final_e;

    reg [25:0] fdiv_rem_cur;
    reg        fdiv_q0, fdiv_q1;
    reg [25:0] fdiv_quot_comb;
    reg [22:0] fdiv_frac_raw, fdiv_frac_final;
    reg        fdiv_g, fdiv_r, fdiv_s, fdiv_round_up;
    reg [9:0]  fdiv_final_exp;

    reg [4:0]  fadd_lz;
    reg [22:0] fadd_frac_raw, fadd_frac_final;
    reg        fadd_g, fadd_r, fadd_s, fadd_round_up;
    reg [8:0]  fadd_final_e;

    // ------------------------------------------------------------------------
    // Main FSM State Machine & Multi-Cycle Execution
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state        <= S_IDLE;
            count        <= 4'd0;
            saved_op     <= 7'd0;
            saved_frm    <= 3'd0;
            result_reg   <= 32'd0;
            sp_valid     <= 1'b0;
            sp_res       <= 32'd0;
            arithmetic_flags <= 0;

            // FADD
            fadd_sign_large       <= 1'b0;
            fadd_exp_large        <= 9'd0;
            fadd_m_large_ext      <= 28'd0;
            fadd_m_small_aligned  <= 28'd0;
            fadd_eff_sub          <= 1'b0;
            fadd_sum              <= 29'd0;
            fadd_norm_m           <= 28'd0;
            fadd_norm_e           <= 9'd0;
            fadd_sticky_round     <= 1'b0;
            fadd_final_res        <= 32'd0;
            fadd_is_zero_res      <= 1'b0;

            // FMUL
            fmul_sign_res         <= 1'b0;
            fmul_raw_exp          <= 10'd0;
            fmul_mant_a           <= 24'd0;
            fmul_mant_b           <= 24'd0;
            fmul_prod             <= 48'd0;
            fmul_zero_res         <= 1'b0;
            fmul_final_res        <= 32'd0;

            // FDIV
            fdiv_sign_res         <= 1'b0;
            fdiv_exp_res          <= 10'd0;
            fdiv_rem              <= 26'd0;
            fdiv_denom            <= 24'd0;
            fdiv_quot             <= 26'd0;
            fdiv_div0             <= 1'b0;
            fdiv_nan              <= 1'b0;
            fdiv_zero_res         <= 1'b0;
            fdiv_final_res        <= 32'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (is_fpu) begin
                        saved_op  <= funct7;
                        saved_frm <= funct3;
                        sp_valid  <= sp_valid_c;
                        sp_res    <= sp_res_c;

                        case (funct7)
                            // ------------------------------------------------
                            // FMUL.S: Exactly 4 Cycles (1 IDLE + 2 CALC + 1 DONE)
                            // ------------------------------------------------
                            FUNCT7_FMUL: begin
                                count         <= 4'd1; // 2 CALC cycles: count=1, count=0
                                fmul_sign_res <= op_a[31] ^ op_b[31];
                                fmul_raw_exp  <= {2'b00,effective_a} + {2'b00,effective_b} - 10'd127;
                                fmul_mant_a   <= mant_a;
                                fmul_mant_b   <= mant_b;
                                fmul_zero_res <= a_is_zero || b_is_zero;
                                state         <= S_CALC;
                            end

                            // ------------------------------------------------
                            // FDIV.S: Exactly 15 Cycles (1 IDLE + 13 CALC + 1 DONE)
                            // ------------------------------------------------
                            FUNCT7_FDIV: begin
                                count         <= 4'd12; // 13 CALC cycles: count=12 down to 0
                                fdiv_sign_res <= op_a[31] ^ op_b[31];
                                fdiv_denom    <= normal_b;
                                fdiv_quot     <= 26'd0;
                                fdiv_div0     <= ((b_is_zero || a_is_inf) && !a_is_zero && !b_is_inf && !a_is_nan && !b_is_nan);
                                fdiv_nan      <= (a_is_nan || b_is_nan || (b_is_zero && a_is_zero) || (a_is_inf && b_is_inf));
                                fdiv_zero_res <= ((a_is_zero || b_is_inf) && !b_is_zero && !a_is_inf && !a_is_nan && !b_is_nan);

                                if (normal_a >= normal_b) begin
                                    fdiv_rem     <= {2'b00, normal_a};
                                    fdiv_exp_res <= normal_ea - normal_eb + 127;
                                end else begin
                                    fdiv_rem     <= {1'b0, normal_a, 1'b0};
                                    fdiv_exp_res <= normal_ea - normal_eb + 126; // 127 - 1
                                end
                                state <= S_CALC;
                            end

                            // ------------------------------------------------
                            // FADD.S / FSUB.S: Exactly 5 Cycles (1 IDLE + 3 CALC + 1 DONE)
                            // ------------------------------------------------
                            default: begin // FUNCT7_FADD, FUNCT7_FSUB
                                count                <= 4'd2; // 3 CALC cycles: count=2, count=1, count=0
                                fadd_sign_large      <= sign_large_in;
                                fadd_exp_large       <= {1'b0, (a_greater ? effective_a : effective_b)};
                                fadd_m_large_ext     <= m_large_aligned;
                                fadd_m_small_aligned <= m_small_aligned;
                                fadd_eff_sub         <= sign_large_in ^ sign_small_in;
                                fadd_is_zero_res     <= a_is_zero && b_is_zero;
                                state                <= S_CALC;
                            end
                        endcase
                    end
                end

                S_CALC: begin
                    case (saved_op)
                        // ====================================================
                        // FMUL.S Calculations (2 cycles)
                        // ====================================================
                        FUNCT7_FMUL: begin
                            if (count == 4'd1) begin
                                // Cycle 2: 24x24 mantissa multiply
                                fmul_prod <= fmul_mant_a * fmul_mant_b;
                                count     <= 4'd0;
                            end else begin
                                // Cycle 3: Normalization & IEEE 754 RNE Rounding
                                if (fmul_prod[47]) begin
                                    fmul_frac_raw = fmul_prod[46:24];
                                    fmul_g        = fmul_prod[23];
                                    fmul_r        = fmul_prod[22];
                                    fmul_s        = |fmul_prod[21:0];
                                    fmul_norm_e   = fmul_raw_exp + 10'd1;
                                end else begin
                                    fmul_frac_raw = fmul_prod[45:23];
                                    fmul_g        = fmul_prod[22];
                                    fmul_r        = fmul_prod[21];
                                    fmul_s        = |fmul_prod[20:0];
                                    fmul_norm_e   = fmul_raw_exp;
                                end

                                fmul_round_up = round_inc(saved_frm, fmul_sign_res, fmul_frac_raw[0], fmul_g, fmul_r, fmul_s);
                                if (fmul_round_up) begin
                                    if (fmul_frac_raw == 23'h7FFFFF) begin
                                        fmul_frac_final = 23'd0;
                                        fmul_final_e    = fmul_norm_e + 10'd1;
                                    end else begin
                                        fmul_frac_final = fmul_frac_raw + 23'd1;
                                        fmul_final_e    = fmul_norm_e;
                                    end
                                end else begin
                                    fmul_frac_final = fmul_frac_raw;
                                    fmul_final_e    = fmul_norm_e;
                                end

                                packed_result=pack_rne(fmul_sign_res,{16'b0,fmul_prod},$signed(fmul_raw_exp)-173,1'b0);
                                fmul_final_res<=packed_result[31:0];
                                arithmetic_flags<=packed_result[34:32];

                                state <= S_DONE;
                            end
                        end

                        // ====================================================
                        // FDIV.S Calculations (13 cycles: 26 bits computed)
                        // ====================================================
                        FUNCT7_FDIV: begin
                            // In all 13 cycles, compute 2 bits of restoring division
                            fdiv_rem_cur = fdiv_rem;

                            // Bit 0
                            if (fdiv_rem_cur >= {2'b00, fdiv_denom}) begin
                                fdiv_q0      = 1'b1;
                                fdiv_rem_cur = (fdiv_rem_cur - {2'b00, fdiv_denom}) << 1;
                            end else begin
                                fdiv_q0      = 1'b0;
                                fdiv_rem_cur = fdiv_rem_cur << 1;
                            end

                            // Bit 1
                            if (fdiv_rem_cur >= {2'b00, fdiv_denom}) begin
                                fdiv_q1      = 1'b1;
                                fdiv_rem_cur = (fdiv_rem_cur - {2'b00, fdiv_denom}) << 1;
                            end else begin
                                fdiv_q1      = 1'b0;
                                fdiv_rem_cur = fdiv_rem_cur << 1;
                            end

                            fdiv_quot_comb = {fdiv_quot[23:0], fdiv_q0, fdiv_q1};
                            fdiv_rem      <= fdiv_rem_cur;
                            fdiv_quot     <= fdiv_quot_comb;

                            if (count > 4'd0) begin
                                count <= count - 4'd1;
                            end else begin
                                // Cycle 14 (13th calculation step done, exactly 26 bits):
                                // quot has 26 bits: [25] is 1.0 (hidden bit).
                                // Fraction is quot[24:2]. Guard is quot[1]. Round is quot[0]. Sticky is |rem.
                                fdiv_frac_raw  = fdiv_quot_comb[24:2];
                                fdiv_g         = fdiv_quot_comb[1];
                                fdiv_r         = fdiv_quot_comb[0];
                                fdiv_s         = |fdiv_rem_cur;
                                fdiv_final_exp = fdiv_exp_res;

                                fdiv_round_up = round_inc(saved_frm, fdiv_sign_res, fdiv_frac_raw[0], fdiv_g, fdiv_r, fdiv_s);
                                if (fdiv_round_up) begin
                                    if (fdiv_frac_raw == 23'h7FFFFF) begin
                                        fdiv_frac_final = 23'd0;
                                        fdiv_final_exp  = fdiv_exp_res + 10'd1;
                                    end else begin
                                        fdiv_frac_final = fdiv_frac_raw + 23'd1;
                                    end
                                end else begin
                                    fdiv_frac_final = fdiv_frac_raw;
                                end

                                packed_result=pack_rne(fdiv_sign_res,{38'b0,fdiv_quot_comb},$signed(fdiv_exp_res)-152,|fdiv_rem_cur);
                                arithmetic_flags<=packed_result[34:32];
                                if (fdiv_nan) fdiv_final_res<=32'h7fc00000;
                                else if(fdiv_div0) fdiv_final_res<={fdiv_sign_res,8'hff,23'b0};
                                else if(fdiv_zero_res) fdiv_final_res<={fdiv_sign_res,31'b0};
                                else fdiv_final_res<=packed_result[31:0];

                                state <= S_DONE;
                            end
                        end

                        // ====================================================
                        // FADD.S / FSUB.S Calculations (3 cycles)
                        // ====================================================
                        default: begin
                            if (count == 4'd2) begin
                                // Cycle 2: Significand Add / Subtract
                                if (fadd_eff_sub) begin
                                    fadd_sum <= {1'b0, fadd_m_large_ext} - {1'b0, fadd_m_small_aligned};
                                end else begin
                                    fadd_sum <= {1'b0, fadd_m_large_ext} + {1'b0, fadd_m_small_aligned};
                                end
                                count <= 4'd1;
                            end else if (count == 4'd1) begin
                                // Cycle 3: Leading Zero Detect & Normalization
                                if (fadd_sum[27]) begin
                                    // Carry out from addition
                                    fadd_norm_m       <= fadd_sum[27:1];
                                    fadd_norm_e       <= fadd_exp_large + 9'd1;
                                    fadd_sticky_round <= fadd_sum[0];
                                end else begin
                                    fadd_lz = clz27(fadd_sum[26:0]);
                                    if (fadd_lz >= fadd_exp_large[4:0] && fadd_exp_large <= 9'd27) begin
                                        fadd_norm_m       <= (fadd_sum[26:0] << (fadd_exp_large > 0 ? (fadd_exp_large - 1) : 0));
                                        fadd_norm_e       <= 9'd0;
                                        fadd_sticky_round <= 1'b0;
                                    end else begin
                                        fadd_norm_m       <= (fadd_sum[26:0] << fadd_lz);
                                        fadd_norm_e       <= fadd_exp_large - {4'd0, fadd_lz};
                                        fadd_sticky_round <= 1'b0;
                                    end
                                end
                                count <= 4'd0;
                            end else begin
                                // Cycle 4: IEEE 754 RNE Rounding & Pack
                                fadd_frac_raw = fadd_norm_m[25:3];
                                fadd_g        = fadd_norm_m[2];
                                fadd_r        = fadd_norm_m[1];
                                fadd_s        = fadd_norm_m[0] | fadd_sticky_round;

                                fadd_round_up = round_inc(saved_frm, fadd_sign_large, fadd_frac_raw[0], fadd_g, fadd_r, fadd_s);
                                if (fadd_round_up) begin
                                    if (fadd_frac_raw == 23'h7FFFFF) begin
                                        fadd_frac_final = 23'd0;
                                        fadd_final_e    = fadd_norm_e + 9'd1;
                                    end else begin
                                        fadd_frac_final = fadd_frac_raw + 23'd1;
                                        fadd_final_e    = fadd_norm_e;
                                    end
                                end else begin
                                    fadd_frac_final = fadd_frac_raw;
                                    fadd_final_e    = fadd_norm_e;
                                end

                                if (fadd_is_zero_res || fadd_sum == 29'd0) begin
                                    fadd_final_res <= 32'h0000_0000;
                                end else if (fadd_final_e >= 255) begin
                                    fadd_final_res <= {fadd_sign_large, 8'hFF, 23'd0};
                                end else begin
                                    fadd_final_res <= {fadd_sign_large, fadd_final_e[7:0], fadd_frac_final};
                                end

                                arithmetic_flags <= {fadd_final_e>=255,
                                    fadd_final_e==0 && (fadd_g|fadd_r|fadd_s),
                                    fadd_final_e>=255 || fadd_g|fadd_r|fadd_s};
                                state <= S_DONE;
                            end
                        end
                    endcase
                end

                S_DONE: begin
                    // Cycle 5 (FADD/FSUB), Cycle 4 (FMUL), Cycle 15 (FDIV)
                    // Output is valid, return to IDLE on next clock edge
                    if (sp_valid) result_reg <= sp_res;
                    else case (saved_op)
                        FUNCT7_FMUL: result_reg <= fmul_final_res;
                        FUNCT7_FDIV: result_reg <= fdiv_final_res;
                        default:     result_reg <= fadd_final_res;
                    endcase
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // Result Mux
    always @(*) begin
        if (state == S_DONE && sp_valid) begin
            fpu_result = sp_res;
        end else if (state == S_DONE) begin
            case (saved_op)
                FUNCT7_FMUL: fpu_result = fmul_final_res;
                FUNCT7_FDIV: fpu_result = fdiv_final_res;
                default:     fpu_result = fadd_final_res;
            endcase
        end else begin
            fpu_result = result_reg;
        end
    end

    reg saved_nv, saved_dz, saved_finite_nonzero;
    wire snan_a = a_is_nan && !op_a[22];
    wire snan_b = b_is_nan && !op_b[22];
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin saved_nv<=0; saved_dz<=0; saved_finite_nonzero<=0; end
        else if(state==S_IDLE && is_fpu) begin
            saved_nv <= snan_a || snan_b ||
                (funct7==FUNCT7_FDIV && ((a_is_zero && b_is_zero) || (a_is_inf && b_is_inf))) ||
                (funct7==FUNCT7_FMUL && ((a_is_zero && b_is_inf) || (a_is_inf && b_is_zero))) ||
                ((funct7==FUNCT7_FADD || funct7==FUNCT7_FSUB) && a_is_inf && b_is_inf && sign_a!=sign_b);
            saved_dz <= funct7==FUNCT7_FDIV && !a_is_zero && !a_is_inf && !a_is_nan && b_is_zero;
            saved_finite_nonzero <= !a_is_inf && !b_is_inf && !a_is_nan && !b_is_nan && !a_is_zero && !b_is_zero;
        end
    end
    assign flags_o = fpu_done ? {saved_nv,saved_dz,
        saved_finite_nonzero ? arithmetic_flags : 3'b0} : 5'b0;

    // Handshaking:
    // fpu_busy is HIGH during multi-cycle computation, drops to LOW on S_DONE
    assign fpu_busy = is_fpu && (state != S_DONE);
    assign fpu_done = is_fpu && (state == S_DONE);

endmodule