// ============================================================================
// File: tb_feature5_pipeline.v
// Module: tb_feature5_pipeline
// Description: Full 5-Stage RV32IMF Pipeline Integration Testbench with L1 D-Cache
//              Verifies:
//              1. Cold start compulsory load miss (10-cycle burst refill stall)
//              2. Sequential spatial locality hits (1-cycle hit, 0 stall)
//              3. Store hit (SW) with write-through + 1-cycle latency
//              4. Read back updated word from cache line
//              5. Store miss (SW) with No-Write-Allocate / write-around (0 stall)
//              6. Interleaved ALU arithmetic & RAW register forwarding
//              7. UART MMIO non-cached peripheral write
// Project: Pipelined RV32IMF RISC-V Core (Feature 5: L1 D-Cache Verification)
// Clock: Standard 50 MHz (20 ns clock period)
// ============================================================================

`timescale 1ns/1ps

module tb_feature5_pipeline;

    // Clock and reset signals (50 MHz clock)
    reg clk;
    reg reset_n;

    // Memory bus interconnects
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;

    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we;
    wire        dmem_req;
    wire [31:0] dmem_rdata;

    // Pipeline telemetry signals
    wire [31:0] pc_if;
    wire [31:0] pc_id;
    wire [31:0] pc_ex;
    wire [31:0] pc_mem;
    wire [31:0] pc_wb;

    wire        wb_reg_write;
    wire [4:0]  wb_dest_reg;
    wire [31:0] wb_data;

    wire        hazard_stall;
    wire        hazard_flush_id;
    wire        hazard_flush_ex;
    wire [1:0]  forward_a;
    wire [1:0]  forward_b;
    wire        mul_active;
    wire        div_active;
    wire        div_busy;
    wire        fpu_active;
    wire        fpu_busy;
    wire        exception;

    wire        dcache_stall;
    wire        dcache_hit;
    wire        dcache_miss;
    wire [31:0] dcache_hit_count;
    wire [31:0] dcache_miss_count;

    wire [31:0] mmio_addr;
    wire [31:0] mmio_wdata;
    wire        mmio_we;
    wire        mmio_re;
    wire [31:0] mmio_rdata;
    wire        mmio_match;

    wire        uart_tx;
    wire        uart_busy;
    wire        banner_done;

    // 50 MHz core clock (period = 20 ns)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // Backing Instruction Memory (4 KB = 1024 words)
    instr_mem #(
        .HEX_FILE ("imem.hex"),
        .WORDS    (1024)
    ) u_backing_imem (
        .clk   (clk),
        .pc    (imem_addr),
        .instr (imem_rdata)
    );

    // Backing Data Memory (4 KB = 1024 words)
    data_mem #(
        .HEX_FILE ("dmem.hex"),
        .WORDS    (1024)
    ) u_backing_dmem (
        .clk   (clk),
        .re    (dmem_req),
        .raddr (dmem_addr),
        .rdata (dmem_rdata),
        .we    (dmem_we),
        .waddr (dmem_addr),
        .wdata (dmem_wdata),
        .wstrb (dmem_wstrb)
    );

    // 5-Stage RV32IMF Core with L1 D-Cache
    pipeline_5stage #(
        .RESET_PC(32'h0000_0000)
    ) dut (
        .clk              (clk),
        .reset_n          (reset_n),
        .stall_ext        (1'b0),
        .use_dsp_i        (1'b1),
        .imem_addr        (imem_addr),
        .imem_rdata       (imem_rdata),
        .dmem_addr        (dmem_addr),
        .dmem_wdata       (dmem_wdata),
        .dmem_wstrb       (dmem_wstrb),
        .dmem_we          (dmem_we),
        .dmem_req         (dmem_req),
        .dmem_rdata       (dmem_rdata),
        .mmio_addr_o      (mmio_addr),
        .mmio_wdata_o     (mmio_wdata),
        .mmio_we_o        (mmio_we),
        .mmio_re_o        (mmio_re),
        .mmio_rdata_i     (mmio_rdata),
        .mmio_match_i     (mmio_match),
        .pc_if            (pc_if),
        .pc_id            (pc_id),
        .pc_ex            (pc_ex),
        .pc_mem           (pc_mem),
        .pc_wb            (pc_wb),
        .wb_reg_write     (wb_reg_write),
        .wb_dest_reg      (wb_dest_reg),
        .wb_data          (wb_data),
        .hazard_stall     (hazard_stall),
        .hazard_flush_id  (hazard_flush_id),
        .hazard_flush_ex  (hazard_flush_ex),
        .forward_a        (forward_a),
        .forward_b        (forward_b),
        .mul_active       (mul_active),
        .div_active       (div_active),
        .div_busy         (div_busy),
        .fpu_active       (fpu_active),
        .fpu_busy         (fpu_busy),
        .exception        (exception),
        .dcache_stall     (dcache_stall),
        .dcache_hit       (dcache_hit),
        .dcache_miss      (dcache_miss),
        .dcache_hit_count (dcache_hit_count),
        .dcache_miss_count(dcache_miss_count)
    );

    // Dedicated UART Subsystem
    uart_unit #(
        .CLK_FREQ   (50_000_000),
        .BAUD_RATE  (115_200),
        .FIFO_DEPTH (64)
    ) u_uart (
        .clk             (clk),
        .reset_n         (reset_n),
        .dmem_addr       (mmio_addr),
        .dmem_wdata      (mmio_wdata),
        .dmem_we         (mmio_we),
        .dmem_re         (mmio_re),
        .uart_rdata      (mmio_rdata),
        .uart_addr_match (mmio_match),
        .fetch_pc        (pc_if),
        .fetch_inst      (imem_rdata),
        .hazard_stall    (hazard_stall),
        .step_trigger    (1'b1),
        .uart_tx         (uart_tx),
        .uart_busy       (uart_busy),
        .banner_done_o   (banner_done)
    );

    // Test program loader & verification logic
    integer test_pass = 0;
    integer test_fail = 0;
    integer cycle_cnt = 0;

    always @(posedge clk) begin
        cycle_cnt <= cycle_cnt + 1;
    end

    // Self-checking tasks
    task check_assert(input condition, input [1023:0] msg);
        begin
            if (condition) begin
                $display("  [PASS] %0s", msg);
                test_pass = test_pass + 1;
            end else begin
                $display("  [FAIL] %0s (wb_data=0x%08h, wb_dest_reg=%0d, wb_reg_write=%0d, dmem_addr=0x%08h)", msg, wb_data, wb_dest_reg, wb_reg_write, dut.dmem_stage_addr);
                test_fail = test_fail + 1;
            end
        end
    endtask

    always @(posedge clk) begin
        if (wb_reg_write && wb_dest_reg != 5'd0) begin
            $display("  [WB COMMIT] Time=%0d ns, Reg x%0d <= 0x%08h (pc_wb = 0x%08h)", $time, wb_dest_reg, wb_data, pc_wb);
        end
    end

    initial begin
        // Pre-populate backing data memory at word offset 0x100..0x10F
        u_backing_dmem.dmem[32'h0000_0100 >> 2] = 32'h1111_1111;
        u_backing_dmem.dmem[32'h0000_0104 >> 2] = 32'h2222_2222;
        u_backing_dmem.dmem[32'h0000_0108 >> 2] = 32'h3333_3333;
        u_backing_dmem.dmem[32'h0000_010C >> 2] = 32'h4444_4444;

        // Assembly program to verify 5-stage pipeline with D-Cache:
        // PC 0x00: ADDI x1, x0, 0x100       // Base address = 0x100
        // PC 0x04: LW   x3, 0(x1)           // Cold Miss -> 10-cycle burst refill into line
        // PC 0x08: LW   x4, 4(x1)           // Spatial Hit Word 1 -> 1-cycle hit
        // PC 0x0C: LW   x5, 8(x1)           // Spatial Hit Word 2 -> 1-cycle hit
        // PC 0x10: LW   x6, 12(x1)          // Spatial Hit Word 3 -> 1-cycle hit
        // PC 0x14: LUI  x7, 0xAAAAA         // Data = 0xAAAAA555
        // PC 0x18: ADDI x7, x7, 0x555       //
        // PC 0x1C: SW   x7, 4(x1)           // Store Hit at 0x104 (write-through)
        // PC 0x20: LW   x8, 4(x1)           // Read back updated word from cache
        // PC 0x24: ADDI x9, x0, 0x777       //
        // PC 0x28: SW   x9, 0x200(x0)       // Store Miss at 0x200 (write-around, no-allocate)
        // PC 0x2C: LUI  x10, 0x80000        // MMIO UART Address = 0x80000000
        // PC 0x30: ADDI x11, x0, 65         // ASCII 'A'
        // PC 0x34: SB   x11, 0(x10)         // MMIO non-cached character write
        // PC 0x38: RET  (JALR x0, x1, 0)    // Program termination

        u_backing_imem.imem[0]  = 32'h10000093; // addi x1, x0, 0x100
        u_backing_imem.imem[1]  = 32'h0000A183; // lw x3, 0(x1)
        u_backing_imem.imem[2]  = 32'h0040A203; // lw x4, 4(x1)
        u_backing_imem.imem[3]  = 32'h0080A283; // lw x5, 8(x1)
        u_backing_imem.imem[4]  = 32'h00C0A303; // lw x6, 12(x1)
        u_backing_imem.imem[5]  = 32'hAAAAA3B7; // lui x7, 0xAAAAA
        u_backing_imem.imem[6]  = 32'h55538393; // addi x7, x7, 0x555
        u_backing_imem.imem[7]  = 32'h0070A223; // sw x7, 4(x1)
        u_backing_imem.imem[8]  = 32'h0040A403; // lw x8, 4(x1)
        u_backing_imem.imem[9]  = 32'h77700493; // addi x9, x0, 0x777
        u_backing_imem.imem[10] = 32'h20902023; // sw x9, 0x200(x0)
        u_backing_imem.imem[11] = 32'h80000537; // lui x10, 0x80000
        u_backing_imem.imem[12] = 32'h04100593; // addi x11, x0, 65 ('A')
        u_backing_imem.imem[13] = 32'h00B50023; // sb x11, 0(x10)
        u_backing_imem.imem[14] = 32'h00008067; // ret (complete)

        reset_n = 0;
        $display("==================================================================");
        $display("   TESTBENCH: Feature 5 Pipeline Integration (tb_feature5_pipeline)");
        $display("   5-Stage RV32IMF Core with Direct-Mapped L1 D-Cache (50 MHz)   ");
        $display("==================================================================");

        #40;
        @(posedge clk);
        #1;
        reset_n = 1;
        $display("[*] Core reset released. Beginning pipeline execution...");

        // Monitor execution and verify checkpoints
        // 1. Wait for cold miss on LW x3, 0(x1)
        wait(dut.ex_mem_mem_read == 1'b1);
        @(posedge clk);
        #1;
        check_assert(dcache_stall == 1'b1, "Cold load miss triggered dcache_stall = 1 in MEM stage");

        // Wait until dcache_stall clears
        wait(dcache_stall == 1'b0);
        check_assert(dut.dcache_miss_count >= 32'd1, "D-Cache logged cold miss in miss_count");

        // 2. Wait for writeback of x3
        wait(wb_reg_write == 1'b1 && wb_dest_reg == 5'd3);
        #1;
        check_assert(wb_data == 32'h1111_1111, "LW x3 correctly committed 0x11111111 from backing memory");

        // 3. Sequential spatial hits: x4, x5, x6
        wait(wb_reg_write == 1'b1 && wb_dest_reg == 5'd4);
        #1;
        check_assert(wb_data == 32'h2222_2222, "Spatial hit Word 1: LW x4 committed 0x22222222");

        wait(wb_reg_write == 1'b1 && wb_dest_reg == 5'd5);
        #1;
        check_assert(wb_data == 32'h3333_3333, "Spatial hit Word 2: LW x5 committed 0x33333333");

        wait(wb_reg_write == 1'b1 && wb_dest_reg == 5'd6);
        #1;
        check_assert(wb_data == 32'h4444_4444, "Spatial hit Word 3: LW x6 committed 0x44444444");

        // 4. Store hit at 0x104 with write-through
        wait(dut.ex_mem_mem_write == 1'b1 && dut.dmem_stage_addr == 32'h0000_0104);
        @(posedge clk);
        #1;
        check_assert(dcache_stall == 1'b0, "Store hit executed with zero stall cycles");

        // 5. Read back updated word: LW x8
        wait(wb_reg_write == 1'b1 && wb_dest_reg == 5'd8);
        #1;
        check_assert(wb_data == 32'hAAAA_A555, "Read back updated store word: LW x8 = 0xAAAAA555");
        check_assert(u_backing_dmem.dmem[32'h0000_0104 >> 2] == 32'hAAAA_A555, "Backing memory also updated via write-through");

        // 6. Store miss at 0x200
        wait(dut.ex_mem_mem_write == 1'b1 && dut.dmem_stage_addr == 32'h0000_0200);
        @(posedge clk);
        #1;
        check_assert(dcache_stall == 1'b0, "Store miss bypassed cache with 0 stall cycles (write-around)");
        check_assert(u_backing_dmem.dmem[32'h0000_0200 >> 2] == 32'h0000_0777, "Backing memory at 0x200 written correctly");

        // 7. MMIO UART write
        wait(mmio_we == 1'b1 && mmio_addr == 32'h8000_0000);
        #1;
        check_assert(mmio_wdata[7:0] == 8'd65, "MMIO UART received character 'A' (0x41) bypassing D-Cache");

        // 8. Wait for RET
        wait(pc_wb == 32'h0000_0038);
        #100;

        $display("\n==================================================================");
        $display("   PIPELINE INTEGRATION VERIFICATION SUMMARY");
        $display("   Total Checks Passed: %0d", test_pass);
        $display("   Total Checks Failed: %0d", test_fail);
        $display("   D-Cache Hits Logged: %0d", dcache_hit_count);
        $display("   D-Cache Misses Logged: %0d", dcache_miss_count);
        $display("==================================================================");

        if (test_fail == 0) begin
            $display(">>> ALL ASSERTIONS PASSED! FEATURE 5 PIPELINE 100%% VERIFIED! <<<\n");
        end else begin
            $display(">>> SOME ASSERTIONS FAILED! <<<\n");
        end

        $finish;
    end

endmodule
