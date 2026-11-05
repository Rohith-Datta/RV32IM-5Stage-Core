`timescale 1ns/1ps
module tb_bp_bypass;
 reg clk=0,rst=0,stall=0,bypass=0,redirect=0,update=0;
 always #5 clk=~clk;
 wire [31:0] pc,target;wire hit,taken;
 fetch_stage dut(.clk(clk),.reset_n(rst),.stall_if(stall),.bp_bypass_i(bypass),
 .ex_mispredict(redirect),.ex_redirect_pc(32'h0),
 .btb_update_en(update),.btb_update_pc(32'h0),.btb_update_target(32'h40),.btb_update_taken(1'b1),
 .icache_rdata(32'h13),.pc_o(pc),.pred_hit_o(hit),.pred_taken_o(taken),.pred_target_o(target));
 initial begin
 #2;rst=0;#10;rst=1;stall=1;update=1;
 @(negedge clk);update=0;stall=0;#1;
 if(!hit || !taken || target!=64)$fatal(1,"Trained BTB not predicting");
 @(negedge clk);if(pc!=64)$fatal(1,"Enabled fetch did not use target");
 redirect=1;@(negedge clk);redirect=0;bypass=1;#1;
 if(hit || taken || target!=4)$fatal(1,"Bypass leaked prediction metadata");
 @(negedge clk);if(pc!=4)$fatal(1,"Bypass did not fetch sequentially");
 stall=1;redirect=1;@(negedge clk);redirect=0;#1;
 if(pc!=0)$fatal(1,"Recovery must work during bypass and stall");
 bypass=0;stall=0;#1;if(!taken)$fatal(1,"Re-enable failed");
 $display("BP BYPASS PASS: prediction, sequential fetch, metadata and stalled recovery");$finish;
 end
endmodule
