`timescale 1ns/1ps
module tb_cache_bypass_store;
 reg clk=0,rst=0,bypass=1,wr=0,rd=0;always #5 clk=~clk;
 reg [31:0] addr=0,data=32'h12345678;wire stall,mwe,mreq;wire [31:0]ma,md,q;wire [3:0]ms;
 reg [31:0] memory[0:1023];reg [31:0] response;integer n=0,writes=0;
 dcache_controller dut(.hit_accept_i(1'b1),.clk(clk),.reset_n(rst),.mem_grant(1'b1),.counter_reset_i(1'b0),.cache_bypass_i(bypass),
 .cpu_addr(addr),.cpu_wdata(data),.cpu_wstrb(4'hf),.cpu_we(wr),.cpu_re(rd),.cpu_rdata(q),.dcache_stall(stall),
 .mem_addr(ma),.mem_rdata(response),.mem_wdata(md),.mem_wstrb(ms),.mem_we(mwe),.mem_req(mreq));
 always @(posedge clk)begin
  if(mreq)response<=memory[ma>>2];
  if(mwe)begin memory[ma>>2]<=md;writes=writes+1;end
 end
 initial begin
 #12 rst=1;@(negedge clk);wr=1;
 while(stall!==1) #1;
 while(stall)begin @(posedge clk);n=n+1;@(negedge clk);end
 if(n!=9 || writes!=1 || memory[0]!==data)$fatal(1,"Bypass store cycles=%0d writes=%0d",n,writes);
 wr=0;@(negedge clk);rd=1;n=0;
 while(stall!==1)#1;
 while(stall)begin @(posedge clk);n=n+1;@(negedge clk);end
 if(n!=9 || q!==data)$fatal(1,"Bypass load cycles=%0d data=%h",n,q);
 rd=0;$display("CACHE BYPASS PASS: store=9 stall cycles, one write; load=9 stall cycles, correct data");$finish;
 end
 initial begin #10000;$fatal(1,"Timeout");end
endmodule
