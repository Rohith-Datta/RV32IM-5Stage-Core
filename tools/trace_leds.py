import os
import subprocess

tb_code = """`timescale 1ns/1ps

module tb_led_cycle_trace;
    reg clk;
    reg reset_n;
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    wire [31:0] imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_rdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we, dmem_re;
    wire [31:0] pc_if, pc_id, pc_ex, pc_mem, pc_wb;
    wire        wb_reg_write;
    wire [4:0]  wb_dest_reg;
    wire [31:0] wb_data;
    wire        hazard_stall, hazard_flush_id, hazard_flush_ex;
    wire [1:0]  forward_a, forward_b;
    wire        mul_active, div_active, div_busy, fpu_active, fpu_busy;
    wire        exception;

    reg [31:0] imem [0:1023];
    reg [31:0] dmem [0:1023];
    assign imem_rdata = (imem_addr[11:2] < 1024) ? imem[imem_addr[11:2]] : 32'h00000013;
    assign dmem_rdata = (dmem_addr[11:2] < 1024) ? dmem[dmem_addr[11:2]] : 32'h0;

    always @(posedge clk) begin
        if (dmem_we) begin
            if (dmem_wstrb[0]) dmem[dmem_addr[11:2]][7:0]   <= dmem_wdata[7:0];
            if (dmem_wstrb[1]) dmem[dmem_addr[11:2]][15:8]  <= dmem_wdata[15:8];
            if (dmem_wstrb[2]) dmem[dmem_addr[11:2]][23:16] <= dmem_wdata[23:16];
            if (dmem_wstrb[3]) dmem[dmem_addr[11:2]][31:24] <= dmem_wdata[31:24];
        end
    end

    pipeline_5stage dut (
        .clk(clk), .reset_n(reset_n), .stall_ext(1'b0), .use_dsp_i(1'b1),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_wstrb(dmem_wstrb),
        .dmem_we(dmem_we), .dmem_re(dmem_re), .dmem_rdata(dmem_rdata),
        .pc_if(pc_if), .pc_id(pc_id), .pc_ex(pc_ex), .pc_mem(pc_mem), .pc_wb(pc_wb),
        .wb_reg_write(wb_reg_write), .wb_dest_reg(wb_dest_reg), .wb_data(wb_data),
        .hazard_stall(hazard_stall), .hazard_flush_id(hazard_flush_id), .hazard_flush_ex(hazard_flush_ex),
        .forward_a(forward_a), .forward_b(forward_b),
        .mul_active(mul_active), .div_active(div_active), .div_busy(div_busy),
        .fpu_active(fpu_active), .fpu_busy(fpu_busy), .exception(exception)
    );

    wire fwd_active = (forward_a != 2'b00) || (forward_b != 2'b00);

    wire [15:0] led;
    assign led[0] = hazard_stall;
    assign led[1] = fwd_active;
    assign led[2] = hazard_flush_id;
    assign led[3] = wb_reg_write;
    assign led[4] = mul_active;
    assign led[5] = div_active || div_busy;
    assign led[6] = fpu_active || fpu_busy;
    assign led[7] = (pc_wb == 32'h00000094);
    assign led[15:8] = wb_data[7:0];

    integer i, cycle;
    initial begin
        for (i=0; i<1024; i=i+1) begin
            imem[i] = 32'h00000013;
            dmem[i] = 32'h0;
        end
        $readmemh("mem/imem.hex", imem);

        reset_n = 0;
        #30;
        @(posedge clk);
        #1;
        reset_n = 1;
        cycle = 0;
    end

    always @(posedge clk) begin
        if (reset_n) begin
            cycle = cycle + 1;
            $display("CYCLE=%0d | PC_IF=0x%08h | PC_EX=0x%08h | PC_WB=0x%08h | LED=%016b | WB_REG=x%0d | WB_DATA=0x%08h",
                     cycle, pc_if, pc_ex, pc_wb, led, wb_dest_reg, wb_data);
            if (pc_wb == 32'h00000094 || cycle > 180) begin
                $finish;
            end
        end
    end
endmodule
"""

f4_dir = "/Users/siddharthmisro/Documents/RISCV/feature_4"
tb_path = os.path.join(f4_dir, "testbench", "tb_led_cycle_trace.v")
with open(tb_path, "w") as f:
    f.write(tb_code)

cmd = [
    "iverilog", "-g2012", "-o", "sim_led_trace",
    "-I", "modules", "-I", "modules/pipeline", "-I", "modules/stages", "-I", "modules/registers",
    "modules/pipeline/pipe.v", "modules/pipeline/pipeline_5stage.v",
    "modules/registers/if_id_reg.v", "modules/registers/id_ex_reg.v",
    "modules/registers/ex_mem_reg.v", "modules/registers/mem_wb_reg.v",
    "modules/stages/decode_stage.v", "modules/stages/execute_stage.v",
    "modules/stages/memory.v", "modules/stages/memory_stage.v",
    "modules/stages/writeback_stage.v", "modules/stages/multiplier_unit.v",
    "modules/stages/multiplier_dsp.v", "modules/stages/booth_radix4_multiplier.v",
    "modules/stages/divider_unit.v", "modules/stages/fpu_single_core.v",
    "modules/hazard_unit.v", "testbench/tb_led_cycle_trace.v"
]

subprocess.check_call(cmd, cwd=f4_dir)
out = subprocess.check_output(["./sim_led_trace"], cwd=f4_dir).decode()
log_path = os.path.join(f4_dir, "led_trace.log")
with open(log_path, "w") as f:
    f.write(out)
print(f"Logged {len(out.splitlines())} lines to {log_path}")
