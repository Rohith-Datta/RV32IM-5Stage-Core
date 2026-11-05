// ============================================================================
// File: tb_integrated_core.v
// Module: tb_integrated_core
// Description: Comprehensive Self-Checking Integration Testbench
// Exercises:
//   1. 5-Stage Pipeline RAW Data Forwarding (EX/MEM and MEM/WB)
//   2. RV32M Hardware Multiplication (DSP48E1 / Booth)
//   3. RV32M 32-Cycle Restoring Divider & Remainder Unit
//   4. RV32M Divide-by-Zero RISC-V Specification Corner Case
//   5. RV32Zbb Bit Manipulation Instructions (CLZ, CPOP, MAX, MIN, ANDN)
//   6. RV32F IEEE-754 Single-Precision FPU (FADD.S 5c, FMUL.S 4c)
//   7. L1 D-Cache & L1 I-Cache with Priority Memory Bus Arbitration
//   8. Feature 7 Static 32-Entry Branch Target Buffer (BTB) & Recovery
//   9. Feature 8 Passive Hardware Performance Counters (CSR_CYCLE, CSR_INSTRET, CSR_STALLS)
// ============================================================================

`timescale 1ns/1ps

module tb_integrated_core;

    reg clk;
    reg reset_n;
    reg stall_ext;

    // Memory Bus Signals
    wire        main_mem_req;
    wire [31:0] main_mem_addr;
    wire        main_mem_we;
    wire [31:0] main_mem_wdata;
    wire [3:0]  main_mem_wstrb;
    wire [31:0] main_mem_rdata;

    // Pipeline Monitoring Signals
    wire [31:0] pc_if, pc_id, pc_ex, pc_mem, pc_wb;
    wire        wb_reg_write;
    wire [5:0]  wb_dest_reg;
    wire [31:0] wb_data;

    wire        hazard_stall;
    wire        btb_pred_hit;
    wire        btb_pred_taken;
    wire        btb_mispredict;
    wire        icache_hit;
    wire        icache_miss;
    wire        dcache_hit;
    wire        dcache_miss;
    wire        div_busy;
    wire        fpu_busy;

    wire [63:0] cycle_count_o;
    wire [63:0] instret_count_o;
    wire [63:0] stall_count_o;
    wire [63:0] branch_count_o;
    wire [63:0] mispredict_count_o;

    // ------------------------------------------------------------------------
    // Clock Generation (50 MHz, 20 ns period)
    // ------------------------------------------------------------------------
    always #10 clk = ~clk;

    // ------------------------------------------------------------------------
    // Processor Core Instantiation
    // ------------------------------------------------------------------------
    rv32imf_core #(
        .RESET_PC (32'h0000_0000)
    ) dut (
        .mmio_rdata(32'b0),
        .clk                (clk),
        .reset_n            (reset_n),
        .stall_ext          (stall_ext),
        .use_dsp_i          (1'b1),
        .icache_bypass_i    (1'b0), // L1 I-Cache Active
        .bp_bypass_i        (1'b0),
        .dcache_bypass_i    (1'b0), // L1 D-Cache Active
        .main_mem_req       (main_mem_req),
        .main_mem_addr      (main_mem_addr),
        .main_mem_we        (main_mem_we),
        .main_mem_wdata     (main_mem_wdata),
        .main_mem_wstrb     (main_mem_wstrb),
        .main_mem_rdata     (main_mem_rdata),
        .pc_if              (pc_if),
        .pc_id              (pc_id),
        .pc_ex              (pc_ex),
        .pc_mem             (pc_mem),
        .pc_wb              (pc_wb),
        .wb_reg_write       (wb_reg_write),
        .wb_dest_reg        (wb_dest_reg),
        .wb_data            (wb_data),
        .hazard_stall       (hazard_stall),
        .btb_pred_hit       (btb_pred_hit),
        .btb_pred_taken     (btb_pred_taken),
        .btb_mispredict     (btb_mispredict),
        .icache_hit         (icache_hit),
        .icache_miss        (icache_miss),
        .dcache_hit         (dcache_hit),
        .dcache_miss        (dcache_miss),
        .div_busy           (div_busy),
        .fpu_busy           (fpu_busy),
        .cycle_count_o      (cycle_count_o),
        .instret_count_o    (instret_count_o),
        .stall_count_o      (stall_count_o),
        .branch_count_o     (branch_count_o),
        .mispredict_count_o (mispredict_count_o)
    );

    // ------------------------------------------------------------------------
    // Backing Main Memory Model Instantiation
    // ------------------------------------------------------------------------
    memory_model #(
        .MEM_SIZE_WORDS (65536)
    ) u_mem (
        .clk       (clk),
        .reset_n   (reset_n),
        .mem_req   (main_mem_req),
        .mem_addr  (main_mem_addr),
        .mem_we    (main_mem_we),
        .mem_wdata (main_mem_wdata),
        .mem_wstrb (main_mem_wstrb),
        .mem_rdata (main_mem_rdata)
    );

    // ------------------------------------------------------------------------
    // Scoreboard for Register Verification
    // ------------------------------------------------------------------------
    reg [31:0] reg_file_mirror [0:63];
    integer k;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (k = 0; k < 64; k = k + 1) reg_file_mirror[k] <= 32'h0;
        end else begin
            if (wb_reg_write && (wb_dest_reg != 5'd0)) begin
                reg_file_mirror[wb_dest_reg] <= wb_data;
                $display("[WB-TRACE] t=%0t PC=0x%08X rd=x%0d data=0x%08X (%0d)", $time, pc_wb, wb_dest_reg, wb_data, $signed(wb_data));
            end
        end
    end

    // ------------------------------------------------------------------------
    // Test Control & Verification Flow
    // ------------------------------------------------------------------------
    integer pass_count = 0;
    integer fail_count = 0;

    task check_reg;
        input [5:0]  reg_num;
        input [31:0] expected;
        input [127:0] desc;
        begin
            if (reg_file_mirror[reg_num] === expected) begin
                $display("[PASS] %0s: x%0d = 0x%08X (Expected 0x%08X)", desc, reg_num, reg_file_mirror[reg_num], expected);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s: x%0d = 0x%08X (Expected 0x%08X)", desc, reg_num, reg_file_mirror[reg_num], expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $display("\n==================================================================");
        $display("   STARTING INTEGRATED RV32IMF PROCESSOR FULL-SYSTEM VERIFICATION  ");
        $display("==================================================================");

        // Load test hex into memory model
        $readmemh("integration_prog.hex", u_mem.ram);

        clk       = 0;
        reset_n   = 0;
        stall_ext = 0;

        // Hold reset for 5 clock cycles
        #100;
        reset_n = 1;
        $display("[INFO] Core reset released. Processor executing instructions...\n");

        // Allow processor to run for 350 cycles (sufficient for all multi-cycle math, cache refills, and BTB branches)
        #7000;

        $display("\n------------------------------------------------------------------");
        $display("   MICROARCHITECTURAL & FUNCTIONAL VERIFICATION RESULTS           ");
        $display("------------------------------------------------------------------");

        // 1. Base Arithmetic & RAW Forwarding
        check_reg(1,  32'd10,         "ADDI x1, 10    ");
        check_reg(2,  32'd20,         "ADDI x2, 20    ");
        check_reg(3,  32'd30,         "ADD x3, x1, x2 ");

        // 2. RV32M Multiplier
        check_reg(4,  32'd200,        "MUL x4 (10*20) ");

        // 3. RV32M 32-Cycle Divider & Div-by-Zero
        check_reg(5,  32'd20,         "DIV x5 (200/10)");
        check_reg(6,  32'hFFFF_FFFF,  "DIV x6 (10 / 0)");

        // 4. RV32Zbb Bit Manipulation
        check_reg(7,  32'd28,         "Zbb CLZ x7     ");
        check_reg(8,  32'd2,          "Zbb CPOP x8    ");
        check_reg(9,  32'd20,         "Zbb MAX x9     ");
        check_reg(10, 32'd10,         "Zbb MIN x10    ");
        check_reg(11, 32'd10,         "Zbb ANDN x11   ");

        // 5. IEEE 754 Floating-Point Unit
        check_reg(45, 32'h4080_0000,  "FADD.S 1.5+2.5 ");
        check_reg(46, 32'h4100_0000,  "FMUL.S 4.0*2.0 ");

        // 6. Memory Store / Load via L1 D-Cache
        check_reg(18, 32'd200,        "D-Cache SW/LW  ");

        // 7. BTB Branch Target Buffer
        check_reg(26, 32'd1,          "BTB Taken Br   ");

        // 8. Feature 8 Performance Counter CSRs
        if (reg_file_mirror[19] > 32'd0) begin
            $display("[PASS] CSR_CYCLE: Read %0d cycles (Monotonically active)", reg_file_mirror[19]);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] CSR_CYCLE returned 0!");
            fail_count = fail_count + 1;
        end

        if (reg_file_mirror[20] > 32'd0) begin
            $display("[PASS] CSR_INSTRET: Read %0d retired instructions", reg_file_mirror[20]);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] CSR_INSTRET returned 0!");
            fail_count = fail_count + 1;
        end

        if (reg_file_mirror[21] >= 32'd30) begin
            $display("[PASS] CSR_HPMCOUNTER5: Read %0d stall cycles (Accurately captured math stalls)", reg_file_mirror[21]);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] CSR_HPMCOUNTER5 returned %0d (Expected >= 30 stall cycles)", reg_file_mirror[21]);
            fail_count = fail_count + 1;
        end

        if (reg_file_mirror[22] >= 32'd1) begin
            $display("[PASS] CSR_HPMCOUNTER7: Read %0d branch executions", reg_file_mirror[22]);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] CSR_HPMCOUNTER7 returned %0d (Expected >= 1)", reg_file_mirror[22]);
            fail_count = fail_count + 1;
        end

        $display("\n==================================================================");
        if (fail_count == 0) begin
            $display("   *** ALL %0d INTEGRATION TESTS PASSED SUCCESSFULLY! ***", pass_count);
            $display("   Tested integration cases passed; this is not exhaustive ISA compliance.");
        end else begin
            $display("   *** VERIFICATION FAILED: %0d Passed, %0d Failed ***", pass_count, fail_count);
        end
        $display("==================================================================\n");

        if(fail_count) $fatal(1,"Integration failure");
        $finish;
    end

endmodule
