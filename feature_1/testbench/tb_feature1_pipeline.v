// ============================================================================
// File: tb_feature1_pipeline.v
// Module: tb_feature1_pipeline
// Description: Full 5-Stage Pipeline Integration Testbench for Feature 1
// Project: Pipelined RV32I Core (Feature 1: 5-Stage Pipeline & Hazard Unit)
// Tests:
//   1. EX-to-EX Data Forwarding (RAW Hazard back-to-back)
//   2. MEM-to-EX Data Forwarding (RAW Hazard 1 instruction separated)
//   3. Back-to-Back Hazard Priority (EX/MEM prioritized over MEM/WB)
//   4. Load-Use Hazard Detection & 1-Cycle Pipeline Stall
//   5. Store Data Forwarding (Forwarding to RS2 store data)
//   6. Branch Resolution & 2-Cycle Pipeline Flush (Squashing delay instructions)
//   7. Hardwired Zero Register (x0 never forwarded or modified)
// ============================================================================

`timescale 1ns/1ps

module tb_feature1_pipeline;

    reg clk;
    reg reset_n;

    // 50 MHz clock generation (20 ns period)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // Memory wires
    wire [31:0] imem_addr;
    reg  [31:0] imem_rdata;

    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we;
    wire        dmem_re;
    wire [31:0] dmem_rdata;

    // Diagnostic wires
    wire [31:0] pc_if, pc_id, pc_ex, pc_mem, pc_wb;
    wire        wb_reg_write;
    wire [4:0]  wb_dest_reg;
    wire [31:0] wb_data;
    wire        hazard_stall;
    wire        hazard_flush_id;
    wire        hazard_flush_ex;
    wire [1:0]  forward_a;
    wire [1:0]  forward_b;
    wire        exception;

    // Test instruction memory array (holds test program)
    reg [31:0] test_imem [0:63];

    // DUT Instantiation
    pipeline_5stage #(
        .RESET_PC(32'h0000_0000)
    ) DUT (
        .clk            (clk),
        .reset_n        (reset_n),
        .stall_ext      (1'b0),
        .imem_addr      (imem_addr),
        .imem_rdata     (imem_rdata),
        .dmem_addr      (dmem_addr),
        .dmem_wdata     (dmem_wdata),
        .dmem_wstrb     (dmem_wstrb),
        .dmem_we        (dmem_we),
        .dmem_re        (dmem_re),
        .dmem_rdata     (dmem_rdata),
        .pc_if          (pc_if),
        .pc_id          (pc_id),
        .pc_ex          (pc_ex),
        .pc_mem         (pc_mem),
        .pc_wb          (pc_wb),
        .wb_reg_write   (wb_reg_write),
        .wb_dest_reg    (wb_dest_reg),
        .wb_data        (wb_data),
        .hazard_stall   (hazard_stall),
        .hazard_flush_id(hazard_flush_id),
        .hazard_flush_ex(hazard_flush_ex),
        .forward_a      (forward_a),
        .forward_b      (forward_b),
        .exception      (exception)
    );

    // Data Memory Instantiation
    data_mem #(
        .HEX_FILE(""), // Blank init for testbench
        .WORDS(1024)
    ) DMEM (
        .clk  (clk),
        .re   (dmem_re),
        .raddr(dmem_addr),
        .rdata(dmem_rdata),
        .we   (dmem_we),
        .waddr(dmem_addr),
        .wdata(dmem_wdata),
        .wstrb(dmem_wstrb)
    );

    // Instruction Memory combinational read from test_imem
    always @(*) begin
        if (imem_addr[11:2] < 64)
            imem_rdata = test_imem[imem_addr[11:2]];
        else
            imem_rdata = 32'h0000_0013; // NOP
    end

    // Error counter
    integer errors = 0;
    integer load_use_stall_detected = 0;
    integer branch_flush_detected = 0;

    // Track hazard signals on clock edge
    always @(posedge clk) begin
        if (reset_n) begin
            if (hazard_stall) begin
                load_use_stall_detected = load_use_stall_detected + 1;
                $display("[HAZARD EVENT @ %0t ps] Load-Use Hazard Stall detected! PC_IF=%08h, PC_ID=%08h",
                         $time, pc_if, pc_id);
            end
            if (hazard_flush_id) begin
                branch_flush_detected = branch_flush_detected + 1;
                $display("[HAZARD EVENT @ %0t ps] Branch/Jump Flush detected! Squashing IF/ID and ID/EX",
                         $time);
            end
            if (wb_reg_write && wb_dest_reg != 0) begin
                $display("[WB @ %0t ps] x%0d <= 0x%08h (%0d)", $time, wb_dest_reg, wb_data, $signed(wb_data));
            end
        end
    end

    // Initialize test program
    initial begin
        // --------------------------------------------------------------------
        // Test 1: EX-to-EX Data Forwarding
        // 0: addi x1, x0, 10        (x1 = 10)
        // 1: addi x2, x1, 5         (x2 = 10 + 5 = 15, RAW hazard on x1, EX->EX)
        test_imem[0] = 32'h00a00093;
        test_imem[1] = 32'h00508113;

        // --------------------------------------------------------------------
        // Test 2: MEM-to-EX Data Forwarding
        // 2: addi x3, x0, 20        (x3 = 20)
        // 3: nop                    (NOP bubble)
        // 4: addi x4, x3, 7         (x4 = 20 + 7 = 27, RAW hazard on x3, MEM->EX)
        test_imem[2] = 32'h01400193;
        test_imem[3] = 32'h00000013;
        test_imem[4] = 32'h00718213;

        // --------------------------------------------------------------------
        // Test 3: Hazard Priority (EX/MEM prioritized over MEM/WB)
        // 5: addi x5, x0, 1         (x5 = 1)
        // 6: addi x5, x0, 2         (x5 = 2, overwrites x5)
        // 7: addi x6, x5, 10        (x6 = 2 + 10 = 12; MUST read newest x5=2 from EX, not x5=1 from MEM)
        test_imem[5] = 32'h00100293;
        test_imem[6] = 32'h00200293;
        test_imem[7] = 32'h00a28313;

        // --------------------------------------------------------------------
        // Test 4: Load-Use Hazard Detection & Pipeline Stall
        // 8:  addi x7, x0, 64       (x7 = 64, data address)
        // 9:  addi x8, x0, 99       (x8 = 99, data value to store)
        // 10: sw   x8, 0(x7)        (Store 99 at address 64)
        // 11: lw   x9, 0(x7)        (Load 99 into x9)
        // 12: addi x10, x9, 1       (x10 = 99 + 1 = 100, IMMEDIATE USE: Must stall 1 cycle!)
        test_imem[8]  = 32'h04000393;
        test_imem[9]  = 32'h06300413;
        test_imem[10] = 32'h0083a023;
        test_imem[11] = 32'h0003a483;
        test_imem[12] = 32'h00148513;

        // --------------------------------------------------------------------
        // Test 5: Store Data Forwarding (Store RS2 forwarding)
        // 13: addi x15, x0, 77      (x15 = 77)
        // 14: sw   x15, 4(x7)       (sw uses x15 immediately in MEM stage; EX->MEM forward)
        // 15: lw   x16, 4(x7)       (x16 = 77)
        test_imem[13] = 32'h04d00793;
        test_imem[14] = 32'h00f3a223;
        test_imem[15] = 32'h0043a803;

        // --------------------------------------------------------------------
        // Test 6: Branch Flush & Resolution in EX Stage
        // 16: beq  x0, x0, target   (Always taken, offset +12 bytes = +3 instructions -> target at index 19)
        // 17: addi x11, x0, 999     (DELAY SLOT 1: Must be SQUASHED / FLUSHED)
        // 18: addi x12, x0, 888     (DELAY SLOT 2: Must be SQUASHED / FLUSHED)
        // 19: addi x13, x0, 42      (TARGET: x13 = 42, MUST EXECUTE)
        // Branch imm: +12 = 0x00c -> imm[12]=0, imm[10:5]=000000, imm[4:1]=0110, imm[11]=0 -> 0x00000663
        test_imem[16] = 32'h00000663;
        test_imem[17] = 32'h3e700593;
        test_imem[18] = 32'h37800613;
        test_imem[19] = 32'h02a00693;

        // --------------------------------------------------------------------
        // Test 7: Zero Register (x0) Hardwiring Check
        // 20: addi x0, x0, 99       (Attempt to write 99 to x0; must be ignored)
        // 21: addi x14, x0, 5       (x14 = 0 + 5 = 5; must NOT receive 99 from x0 forwarding)
        test_imem[20] = 32'h06300013;
        test_imem[21] = 32'h00500713;

        // Padding with NOPs for pipeline drain
        test_imem[22] = 32'h00000013;
        test_imem[23] = 32'h00000013;
        test_imem[24] = 32'h00000013;
        test_imem[25] = 32'h00000013;
        test_imem[26] = 32'h00000013;
        test_imem[27] = 32'h00000013;
        test_imem[28] = 32'h00000013;
        test_imem[29] = 32'h00000013;
        test_imem[30] = 32'h00000013;
    end

    // Test sequence execution
    initial begin
        $display("\n=================================================================");
        $display(" STARTING FEATURE 1 PIPELINE INTEGRATION TESTBENCH (tb_feature1_pipeline.v)");
        $display(" Verifying: Data Forwarding, Load-Use Stalls, Branch Flushes & RegFile");
        $display("=================================================================");

        reset_n = 0;
        #50;
        reset_n = 1;
        $display("[TB @ %0t ps] Master Reset released. Pipeline starting...", $time);

        // Run sufficient cycles for complete execution and drain (50 cycles @ 20ns = 1000ns)
        #1000;

        $display("\n=================================================================");
        $display("                   VERIFICATION RESULTS SUMMARY                  ");
        $display("=================================================================");

        // Test 1 Check: x2 == 15 (EX->EX Forwarding)
        if (DUT.u_decode_stage.regs[2] === 32'd15) begin
            $display("[PASS] Test 1: EX->EX Data Forwarding verified! (x2 = %0d, expected 15)",
                     DUT.u_decode_stage.regs[2]);
        end else begin
            $display("[FAIL] Test 1: EX->EX Data Forwarding failed! (x2 = %0d, expected 15)",
                     DUT.u_decode_stage.regs[2]);
            errors = errors + 1;
        end

        // Test 2 Check: x4 == 27 (MEM->EX Forwarding)
        if (DUT.u_decode_stage.regs[4] === 32'd27) begin
            $display("[PASS] Test 2: MEM->EX Data Forwarding verified! (x4 = %0d, expected 27)",
                     DUT.u_decode_stage.regs[4]);
        end else begin
            $display("[FAIL] Test 2: MEM->EX Data Forwarding failed! (x4 = %0d, expected 27)",
                     DUT.u_decode_stage.regs[4]);
            errors = errors + 1;
        end

        // Test 3 Check: x6 == 12 (Hazard Priority: EX > MEM)
        if (DUT.u_decode_stage.regs[6] === 32'd12) begin
            $display("[PASS] Test 3: Hazard Priority (EX over MEM) verified! (x6 = %0d, expected 12)",
                     DUT.u_decode_stage.regs[6]);
        end else begin
            $display("[FAIL] Test 3: Hazard Priority check failed! (x6 = %0d, expected 12)",
                     DUT.u_decode_stage.regs[6]);
            errors = errors + 1;
        end

        // Test 4 Check: x10 == 100 AND Load-Use stall detected
        if (DUT.u_decode_stage.regs[10] === 32'd100 && load_use_stall_detected >= 1) begin
            $display("[PASS] Test 4: Load-Use Hazard & 1-Cycle Stall verified! (x10 = %0d, stalls = %0d)",
                     DUT.u_decode_stage.regs[10], load_use_stall_detected);
        end else begin
            $display("[FAIL] Test 4: Load-Use Hazard failed! (x10 = %0d, expected 100, stalls = %0d)",
                     DUT.u_decode_stage.regs[10], load_use_stall_detected);
            errors = errors + 1;
        end

        // Test 5 Check: x16 == 77 (Store Data Forwarding)
        if (DUT.u_decode_stage.regs[16] === 32'd77) begin
            $display("[PASS] Test 5: Store Data RS2 Forwarding verified! (x16 = %0d, expected 77)",
                     DUT.u_decode_stage.regs[16]);
        end else begin
            $display("[FAIL] Test 5: Store Data RS2 Forwarding failed! (x16 = %0d, expected 77)",
                     DUT.u_decode_stage.regs[16]);
            errors = errors + 1;
        end

        // Test 6 Check: Branch Squashing (x11==0, x12==0, x13==42, branch_flush >= 1)
        if (DUT.u_decode_stage.regs[11] === 32'd0 &&
            DUT.u_decode_stage.regs[12] === 32'd0 &&
            DUT.u_decode_stage.regs[13] === 32'd42 &&
            branch_flush_detected >= 1) begin
            $display("[PASS] Test 6: Branch Flush & Instruction Squashing verified! (x11=%0d, x12=%0d, x13=%0d, flushes=%0d)",
                     DUT.u_decode_stage.regs[11], DUT.u_decode_stage.regs[12],
                     DUT.u_decode_stage.regs[13], branch_flush_detected);
        end else begin
            $display("[FAIL] Test 6: Branch Flush failed! (x11=%0d [exp 0], x12=%0d [exp 0], x13=%0d [exp 42], flushes=%0d)",
                     DUT.u_decode_stage.regs[11], DUT.u_decode_stage.regs[12],
                     DUT.u_decode_stage.regs[13], branch_flush_detected);
            errors = errors + 1;
        end

        // Test 7 Check: Hardwired x0 remains 0, x14 == 5
        if (DUT.u_decode_stage.regs[14] === 32'd5) begin
            $display("[PASS] Test 7: Register x0 hardwired zero verified! (x14 = %0d, expected 5)",
                     DUT.u_decode_stage.regs[14]);
        end else begin
            $display("[FAIL] Test 7: Register x0 check failed! (x14 = %0d, expected 5)",
                     DUT.u_decode_stage.regs[14]);
            errors = errors + 1;
        end

        $display("=================================================================");
        if (errors == 0) begin
            $display("   >>> ALL 7 FEATURE 1 PIPELINE TESTS PASSED (100%% SUCCESS) <<<");
        end else begin
            $display("   >>> VERIFICATION FAILED WITH %0d ERRORS <<<", errors);
        end
        $display("=================================================================\n");

        $finish;
    end

endmodule
