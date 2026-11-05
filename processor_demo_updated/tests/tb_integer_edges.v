`timescale 1ns/1ps
module tb_integer_edges;
 reg clk=0,rst=0,run=0;always #5 clk=~clk;
 reg [31:0] a,b;reg [2:0] f3;wire [31:0] q,m;wire done;
 divider_unit d(.clk(clk),.reset_n(rst),.is_div(run),.funct3(f3),.op_a(a),.op_b(b),.div_result(q),.div_done(done));
 multiplier_unit u(.clk(clk),.reset_n(rst),.is_mul(1'b1),.use_dsp_sel(1'b1),.funct3(f3),.op_a(a),.op_b(b),.mul_result(m));
 reg [31:0] imm;reg [6:0] f7;reg immediate;wire [31:0] z;
 alu_zbb zbb(.alu_in1(a),.alu_in2(b),.imm_i(imm),.alu_op_i(f3),.arithsubtype_i(1'b0),.immediate_sel_i(immediate),.funct7_i(f7),.alu_result_o(z));
 integer n=0;
 task divide;
 input [2:0] op;input [31:0] x,y,expected;
 begin @(negedge clk);a=x;b=y;f3=op;run=1;wait(done);#1;if(q!==expected)$fatal(1,"DIV f3=%h got=%h expected=%h",op,q,expected);n=n+1;@(negedge clk);run=0;repeat(2)@(negedge clk);end
 endtask
 task zz;
 input [2:0] op;input [6:0] fn;input im;input [31:0] x,y,immediate_value,expected;
 begin a=x;b=y;f3=op;f7=fn;immediate=im;imm=immediate_value;#1;if(z!==expected)$fatal(1,"Zbb f3=%h f7=%h got=%h expected=%h",op,fn,z,expected);n=n+1;end
 endtask
 initial begin
 #12 rst=1;
 divide(4,32'h12345678,0,32'hffffffff);divide(5,32'h12345678,0,32'hffffffff);
 divide(6,32'h12345678,0,32'h12345678);divide(7,32'h12345678,0,32'h12345678);
 divide(4,32'h80000000,32'hffffffff,32'h80000000);divide(6,32'h80000000,32'hffffffff,0);
 a=32'hffffffff;b=32'hffffffff;f3=3;#1;if(m!==32'hfffffffe)$fatal(1,"mulhu");n=n+1;
 f3=1;#1;if(m!==0)$fatal(1,"mulh");n=n+1;
 f3=2;#1;if(m!==32'hffffffff)$fatal(1,"mulhsu");n=n+1;
 zz(1,7'h30,1,0,32'h600,32'h600,32);
 zz(1,7'h30,1,0,32'h601,32'h601,32);
 zz(1,7'h30,1,32'hffffffff,32'h602,32'h602,32);
 zz(1,7'h30,1,0,32'h602,32'h602,0);
 zz(5,7'h34,1,32'h0000803f,32'h698,32'h698,32'h3f800000);
 zz(6,7'h05,0,32'hffffffff,5,0,5);
 zz(7,7'h05,0,32'hffffffff,5,0,32'hffffffff);
 $display("INTEGER EDGE PASS checks=%0d",n);$finish;
 end
 initial begin #10000;$fatal(1,"Timeout");end
endmodule
