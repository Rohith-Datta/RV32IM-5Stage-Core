`timescale 1ns/1ps

module tb_btb_trace;
    reg clk;
    reg reset_n;

    always #10 clk = ~clk;

    wire [31:0] imem_addr;
    reg  [31:0] imem_rdata;
    wire [31:0] dmem_addr, dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we, dmem_re;
    wire [31:0] dmem_rdata = 32'd0;

    wire [31:0] pc_if, pc_id, pc_ex, pc_mem, pc_wb;
    wire        wb_reg_write;
    wire [4:0]  wb_dest_reg;
    wire [31:0] wb_data;
    wire        hazard_stall, hazard_flush_id, hazard_flush_ex;
    wire [1:0]  forward_a, forward_b;
    wire        mul_active, div_active, div_busy, fpu_active, fpu_busy, exception;
    wire        btb_pred_hit, btb_pred_taken, btb_mispredict;

    pipeline_5stage #(
        .RESET_PC(32'h0000_0000)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .stall_ext(1'b0),
        .use_dsp_i(1'b1),
        .imem_addr(imem_addr),
        .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_wstrb(dmem_wstrb),
        .dmem_we(dmem_we),
        .dmem_re(dmem_re),
        .dmem_rdata(dmem_rdata),
        .pc_if(pc_if),
        .pc_id(pc_id),
        .pc_ex(pc_ex),
        .pc_mem(pc_mem),
        .pc_wb(pc_wb),
        .wb_reg_write(wb_reg_write),
        .wb_dest_reg(wb_dest_reg),
        .wb_data(wb_data),
        .hazard_stall(hazard_stall),
        .hazard_flush_id(hazard_flush_id),
        .hazard_flush_ex(hazard_flush_ex),
        .forward_a(forward_a),
        .forward_b(forward_b),
        .mul_active(mul_active),
        .div_active(div_active),
        .div_busy(div_busy),
        .fpu_active(fpu_active),
        .fpu_busy(fpu_busy),
        .exception(exception),
        .btb_pred_hit(btb_pred_hit),
        .btb_pred_taken(btb_pred_taken),
        .btb_mispredict(btb_mispredict)
    );

    reg [31:0] rom [0:63];
    integer j;
    initial begin
        for (j = 0; j < 64; j = j + 1) rom[j] = 32'h0000_0013; // nop
        rom[0] = 32'h0020_0093; // 0x00: addi x1, x0, 2
        rom[1] = 32'h0000_0113; // 0x04: addi x2, x0, 0
        rom[2] = 32'h0011_0113; // 0x08: addi x2, x2, 1
        rom[3] = 32'hFFF0_8093; // 0x0C: addi x1, x1, -1
        rom[4] = 32'hFE00_9CE3; // 0x10: bne  x1, x0, -8
        rom[5] = 32'h0000_0013; // 0x14: nop
        rom[6] = 32'h0000_0013; // 0x18: nop
    end

    always @(*) begin
        imem_rdata = rom[imem_addr[7:2]];
    end

    integer cycle = 0;
    initial begin
        clk = 0;
        reset_n = 0;
        #25;
        reset_n = 1;
    end

    always @(posedge clk) begin
        if (reset_n) begin
            cycle = cycle + 1;
            $display("[Cycle %2d] pc_if=0x%08h | pc_id=0x%08h | pc_ex=0x%08h | mispred=%b | btb_hit=%b | btb_taken=%b | flush_id=%b",
                     cycle, pc_if, pc_id, pc_ex, btb_mispredict, btb_pred_hit, btb_pred_taken, hazard_flush_id);
            if (cycle >= 25) $finish;
        end
    end
endmodule
