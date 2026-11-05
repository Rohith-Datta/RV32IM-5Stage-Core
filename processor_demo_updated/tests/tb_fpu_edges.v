`timescale 1ns/1ps
module tb_fpu_edges;
 reg clk=0,rst=0,start=0; always #5 clk=~clk;
 reg [6:0] op; reg [31:0] a,b;
 wire [31:0] y;wire busy,done;wire [4:0] flags;
 integer passed=0,failed=0;
 fpu_single_core dut(.clk(clk),.reset_n(rst),.is_fpu(start),.funct7(op),.funct3(3'b000),.op_a(a),.op_b(b),.fpu_result(y),.fpu_busy(busy),.fpu_done(done),.flags_o(flags));
 task check;
 input [6:0] operation;input [31:0] x,z,expected;input [4:0] expected_flags;
 begin
  @(negedge clk);op=operation;a=x;b=z;start=1;
  wait(done);#1;
  if(y===expected && flags===expected_flags) begin passed=passed+1;$display("PASS op=%02x a=%08x b=%08x out=%08x flags=%02x",op,a,b,y,flags);end
  else begin failed=failed+1;$display("FAIL op=%02x a=%08x b=%08x out=%08x expected=%08x flags=%02x expected_flags=%02x",op,a,b,y,expected,flags,expected_flags);end
  @(negedge clk);start=0;repeat(2) @(negedge clk);
 end endtask
 initial begin
 #12 rst=1;
 check(7'h0c,32'h3f800000,0,32'h7f800000,5'h08);
 check(7'h0c,32'hbf800000,0,32'hff800000,5'h08);
 check(7'h0c,0,0,32'h7fc00000,5'h10);
 check(7'h04,32'h7f800000,32'h7f800000,32'h7fc00000,5'h10);
 check(7'h08,0,32'h7f800000,32'h7fc00000,5'h10);
 check(7'h00,32'h80000000,32'h80000000,32'h80000000,0);
 check(7'h08,32'h3f800001,32'h3f000001,32'h3f000002,5'h01);
 check(7'h00,32'h3f800000,32'h33800000,32'h3f800000,5'h01);
 check(7'h00,32'h3f800001,32'h33800000,32'h3f800002,5'h01);
 check(7'h08,32'h00800000,32'h3f000000,32'h00400000,0);
 check(7'h00,32'h00000001,32'h00000001,32'h00000002,0);
 check(7'h08,32'h00000001,32'h3f000000,32'h00000000,5'h03);
 $display("FPU EDGE TOTAL pass=%0d fail=%0d",passed,failed);
 if(failed) $fatal(1,"FPU compliance failures");$finish;
 end
 initial begin #10000;$fatal(1,"Timeout");end
endmodule
