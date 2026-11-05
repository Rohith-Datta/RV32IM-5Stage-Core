`timescale 1ns/1ps
module tb_fpu_vectors;
 reg clk=0,rst=0,start=0; always #5 clk=~clk;
 reg [6:0] op; reg [31:0] a,b; wire [31:0] y;wire done;
 reg [103:0] vectors[0:2783];integer i,failures=0;
 fpu_single_core dut(.clk(clk),.reset_n(rst),.is_fpu(start),.funct7(op),.funct3(3'b000),.op_a(a),.op_b(b),.fpu_result(y),.fpu_done(done));
 initial begin
 $readmemh("tests/fp_vectors.mem",vectors);#12 rst=1;
 for(i=0;i<2784;i=i+1) begin
 @(negedge clk);op=vectors[i][102:96];a=vectors[i][95:64];b=vectors[i][63:32];start=1;
 wait(done);#1;
 if(y!==vectors[i][31:0]) begin failures=failures+1;if(failures<20)$display("FAIL %0d op=%h a=%h b=%h got=%h expected=%h",i,op,a,b,y,vectors[i][31:0]);end
 @(negedge clk);start=0;repeat(2)@(negedge clk);
 end
 $display("FPU DIFFERENTIAL vectors=2784 failures=%0d",failures);
 if(failures)$fatal(1,"FPU mismatch");$finish;
 end
endmodule
