`timescale 1ns/1ps
module tb_firmware;
 reg clk=0,reset_n=0;
 always #10 clk=~clk;
 wire req,we; wire [31:0] addr,wdata; wire [3:0] strb; reg [31:0] rdata;
 wire mreq,mwe; wire [31:0] ma,md; wire [3:0] ms;
 reg [15:0] switches, later_switches;
 integer switch_cycle=0;
 wire [31:0] mr=ma[3:2]==0 ? {16'b0,switches} : 0;
 reg [31:0] ram[0:16383];
 wire [31:0] pc,wbpc,wd,wi; wire [5:0] rd; wire retire,ww,stall;
 reg [1023:0] log_name;
 integer c=0,b,out,trace;
 reg full_trace;
 rv32imf_core dut(.clk(clk),.reset_n(reset_n),.stall_ext(1'b0),.use_dsp_i(1'b1),
 .icache_bypass_i(!switches[13]),.bp_bypass_i(switches[9]),.dcache_bypass_i(!switches[13]),
 .main_mem_req(req),.main_mem_addr(addr),.main_mem_we(we),.main_mem_wdata(wdata),.main_mem_wstrb(strb),.main_mem_rdata(rdata),
 .mmio_req(mreq),.mmio_we(mwe),.mmio_addr(ma),.mmio_wdata(md),.mmio_wstrb(ms),.mmio_rdata(mr),
 .pc_if(pc),.pc_wb(wbpc),.wb_data(wd),.wb_dest_reg(rd),.wb_reg_write(ww),.wb_instruction_o(wi),.retire_o(retire),.hazard_stall(stall));
 always @(posedge clk) begin
  if(req && addr<65536) begin
   rdata<=ram[addr>>2];
   if(we) for(b=0;b<4;b=b+1) if(strb[b]) ram[addr>>2][b*8+:8]<=wdata[b*8+:8];
  end else rdata<=0;
  if(reset_n) begin
   c=c+1;
   if(switch_cycle!=0 && c==switch_cycle) switches=later_switches;
   if((full_trace || c<5000) && retire) $fdisplay(trace,"[CC=%8d] PC: 0x%08x | INST: 0x%08x | WB: bank=%0d reg=%0d <= 0x%08x [WE=%0d]",c,wbpc,wi,rd[5],rd[4:0],wd,ww);
   if((full_trace || c<5000) && stall) begin
    if(dut.u_pipeline.dcache_stall) $fdisplay(trace,"[CC=%8d] ---------stall--------- <-- [D-CACHE: state=%0d refill_counter=%0d grant=%0d]",c,dut.u_pipeline.u_dcache.state,dut.u_pipeline.u_dcache.refill_cnt,dut.u_pipeline.dcache_mem_grant);
    else if(dut.u_pipeline.load_use_o) $fdisplay(trace,"[CC=%8d] ---------stall--------- <-- [LOAD-USE DATA HAZARD STALL]",c);
    else $fdisplay(trace,"[CC=%8d] ---------stall--------- <-- [WAIT: I=%0d FPU=%0d DIV=%0d]",c,dut.u_pipeline.icache_stall,dut.fpu_busy,dut.div_busy);
   end
   if((full_trace || c<5000) && dut.btb_mispredict) $fdisplay(trace,"[CC=%8d] ---------flush--------- <-- [BTB MISPREDICTION redirect=0x%08x]",c,dut.u_pipeline.ex_redirect_pc);
   if(mreq && mwe && ma==32'h80000004) $fwrite(out,"%c",md[7:0]);
   if(mreq && mwe && ma==32'h8000000c && md[0]) begin $display("FIRMWARE COMPLETE cycles=%0d",c); $fclose(out);$fclose(trace);$finish;end
   if(c==6000000) begin $fclose(out);$fclose(trace);$fatal(1,"Firmware timeout pc=%08x",pc);end
  end
 end
 initial begin
  full_trace=$test$plusargs("TRACE");
  if(!$value$plusargs("SW_CYCLE=%d",switch_cycle))switch_cycle=0;
  if(!$value$plusargs("SW_LATER=%h",later_switches))later_switches=16'h6032;
  if(!$value$plusargs("SW=%h",switches)) switches=16'h2032;
  $readmemh("avionics_demo.mem",ram);
  if(!$value$plusargs("LOG=%s",log_name)) log_name="reports/firmware_uart.log";
  out=$fopen(log_name,"w");trace=$fopen($sformatf("%0s.trace",log_name),"w");
  #110 reset_n=1;
 end
endmodule
