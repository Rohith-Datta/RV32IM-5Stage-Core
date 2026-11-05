`timescale 1ns/1ps
module tb_display;
 reg clk=0,rst=0;always #5 clk=~clk;wire [7:0]an;wire [6:0]seg;wire dp;wire [15:0]led;
 reg events=0; integer i;reg [6:0] expected[0:7];
 nexys_a7_io_controller dut(.clk_100mhz(clk),.rst_n(rst),.current_pc(32'h76543210),.wb_write_data(32'hfedcba98),.sw_show_wb_on_seg7(1'b0),
 .pipeline_stall(events),.load_use_hazard(events),.dcache_miss_busy(events),.icache_miss_busy(events),.btb_mispredict_flush(events),.fpu_busy(events),.muldiv_busy(events),.retire_event(events),.wb_reg_commit(events),.fpu_exc_nv(events),.fpu_exc_dz(events),.fpu_exc_of(events),.fpu_exc_uf(events),.fpu_exc_nx(events),.zbb_active(events),.uart_tx_active(1'b0),.demo_complete(1'b0),.led(led),.an(an),.seg(seg),.dp(dp));
 initial begin
 expected[0]=7'b1000000;expected[1]=7'b1111001;expected[2]=7'b0100100;expected[3]=7'b0110000;
 expected[4]=7'b0011001;expected[5]=7'b0010010;expected[6]=7'b0000010;expected[7]=7'b1111000;
 #12 rst=1;
 for(i=0;i<8;i=i+1)begin @(negedge clk);dut.refresh_counter=i<<14;#1;if(seg!==expected[i] || an!==~(8'b1<<i))$fatal(1,"Digit %0d",i);end
 events=1;@(negedge clk);events=0;repeat(10)@(negedge clk);if(led[15:2]!==14'h3fff)$fatal(1,"Pulse stretch");
 $display("DISPLAY PASS: all eight PC nibbles, active-low anodes and LED event hold");$finish;
 end
endmodule
