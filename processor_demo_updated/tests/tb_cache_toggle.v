`timescale 1ns/1ps
module tb_cache_toggle;
 reg clk=0,rst=0,bypass=0,wr=0,rd=0;always #5 clk=~clk;
 reg [31:0] data=1;wire stall,mwe,mreq;wire [31:0]ma,md,q;reg [31:0] response;
 reg [31:0] mem[0:3];integer i;
 dcache_controller dut(.clk(clk),.reset_n(rst),.hit_accept_i(1'b1),.mem_grant(1'b1),.counter_reset_i(1'b0),.cache_bypass_i(bypass),
 .cpu_addr(32'b0),.cpu_wdata(data),.cpu_wstrb(4'hf),.cpu_we(wr),.cpu_re(rd),.cpu_rdata(q),.dcache_stall(stall),
 .mem_addr(ma),.mem_rdata(response),.mem_wdata(md),.mem_we(mwe),.mem_req(mreq));
 always @(posedge clk)begin if(mreq)response<=mem[ma[3:2]];if(mwe)mem[ma[3:2]]<=md;end
 task read_check;
 input [31:0] expected;
 begin @(negedge clk);rd=1;#1;while(stall)@(negedge clk);if(q!==expected)$fatal(1,"Read %h expected %h",q,expected);@(negedge clk);rd=0;end
 endtask
 initial begin
 for(i=0;i<4;i=i+1)mem[i]=1;#12 rst=1;
 read_check(1);
 @(negedge clk);bypass=1;wr=1;data=2;#1;while(stall)@(negedge clk);@(negedge clk);wr=0;bypass=0;
 read_check(2);
 @(negedge clk);bypass=1;rd=1;repeat(4)@(negedge clk);bypass=0;
 while(stall)@(negedge clk);if(q!==2)$fatal(1,"Mid-refill bypass toggle corrupted data");
 @(negedge clk);rd=0;$display("CACHE TOGGLE PASS: bypass store invalidates stale line; active refill preserves sampled bypass mode");$finish;
 end
 initial begin #10000;$fatal(1,"Timeout");end
endmodule
