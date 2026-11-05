`timescale 1ns/1ps
module tb_cache_latency;
 reg clk=0,rst=0,bypass=0,rd=0;always #5 clk=~clk;
 reg [31:0] addr=0;wire ds,is,dr,ir;wire[31:0] da,ia,dq,iq;reg[31:0] dm,im;
 wire[3:0] progress;integer n,total,b,k;
 dcache_controller d(.clk(clk),.reset_n(rst),.hit_accept_i(1'b1),.mem_grant(1'b1),.counter_reset_i(1'b0),.cache_bypass_i(bypass),.cpu_addr(addr),.cpu_re(rd),.cpu_we(1'b0),.cpu_wdata(32'b0),.cpu_wstrb(4'b0),.cpu_rdata(dq),.dcache_stall(ds),.mem_addr(da),.mem_rdata(dm),.mem_req(dr),.refill_progress_o(progress));
 icache_controller i(.clk(clk),.reset_n(rst),.hit_accept_i(1'b1),.mem_grant(1'b1),.flush_i(1'b0),.counter_reset_i(1'b0),.cache_bypass_i(bypass),.cpu_addr(addr),.cpu_rdata(iq),.icache_stall(is),.mem_addr(ia),.mem_rdata(im),.mem_req(ir));
 always @(posedge clk)begin if(dr)dm<=32'h12340000+da;if(ir)im<=32'h12340000+ia;end
 initial begin
 for(b=0;b<2;b=b+1)begin
 total=0;
 for(k=0;k<4;k=k+1)begin
 @(negedge clk);rst=0;rd=0;addr=k*4;bypass=b;repeat(2)@(negedge clk);
 rst=1;rd=1;#1;n=0;
 while(ds || is)begin
 if(!ds || !is)$fatal(1,"I/D stall mismatch");
 if(progress!==n+1)$fatal(1,"Refill progress %d expected %d",progress,n+1);
 @(posedge clk);n=n+1;@(negedge clk);
 end
 if(n!=9)$fatal(1,"Expected 9 stalls, got %d",n);
 if(dq!==32'h12340000+addr || iq!==32'h12340000+addr)$fatal(1,"Word offset data mismatch");
 // The following edge services the request: nine stalled edges plus one service.
 @(posedge clk);total=total+n;@(negedge clk);rd=0;
 end
 if(total!=36)$fatal(1,"Four accesses must accumulate 36 stalls");
 end
 $display("CACHE LATENCY PASS: I/D cold and bypass, all four word offsets: 9 stalls + 1 service = 10 occupancy; four bypass accesses = 36 stalls");$finish;
 end
 initial begin #10000;$fatal(1,"Timeout");end
endmodule
