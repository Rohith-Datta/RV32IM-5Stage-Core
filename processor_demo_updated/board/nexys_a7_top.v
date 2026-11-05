`timescale 1ns/1ps
module nexys_a7_top #(parameter MEM_WORDS=16384, MEM_FILE="avionics_demo.mem", parameter SYSTEM_CLOCK_HZ=50000000, parameter UART_DIV_CLOCK=SYSTEM_CLOCK_HZ)(
 input wire CLK100MHZ, CPU_RESETN, input wire [15:0] SW,
 output wire [15:0] LED, output wire [7:0] AN,
 output wire CA,CB,CC,CD,CE,CF,CG,DP, UART_TXD_IN
);
 wire clock50, locked, feedback, core_clk;
 wire pll_clock50,feedback_raw;
`ifdef SYNTHESIS
 MMCME2_BASE #(.CLKIN1_PERIOD(10.0),.CLKFBOUT_MULT_F(10.0),.DIVCLK_DIVIDE(1),.CLKOUT0_DIVIDE_F(1000000000.0/SYSTEM_CLOCK_HZ)) pll
 (.CLKIN1(CLK100MHZ),.RST(!CPU_RESETN),.PWRDWN(1'b0),.CLKFBIN(feedback),.CLKFBOUT(feedback_raw),.CLKOUT0(pll_clock50),.LOCKED(locked));
 BUFG main_clock_buffer(.I(pll_clock50),.O(clock50));
 BUFG feedback_buffer(.I(feedback_raw),.O(feedback));
`else
 reg divided=0;
 generate if(SYSTEM_CLOCK_HZ==50000000) begin
  always @(posedge CLK100MHZ) divided<=~divided;
 end else begin
  // Behavioral model of the MMCM output for fallback-frequency simulation.
  always #(500000000.0/SYSTEM_CLOCK_HZ) divided=~divided;
 end endgenerate
 assign clock50=divided;
 assign locked=CPU_RESETN;
`endif
 wire async_reset=CPU_RESETN && locked;
 (* ASYNC_REG="TRUE" *) reg [1:0] rst_pipe;
 always @(posedge clock50 or negedge async_reset)
   if(!async_reset) rst_pipe<=0; else rst_pipe<={rst_pipe[0],1'b1};
 wire reset_n=rst_pipe[1];
 (* ASYNC_REG="TRUE" *) reg [15:0] sw_meta,sw_sync;
 reg [22:0] step_count;
 always @(posedge clock50 or negedge reset_n) begin
  if(!reset_n) begin sw_meta<=0; sw_sync<=0; step_count<=0; end
  else begin
   sw_meta<=SW; sw_sync<=sw_meta;
   if(step_count==(SYSTEM_CLOCK_HZ/10-1)) step_count<=0; else step_count<=step_count+1;
  end
 end
 reg complete;
 wire trace_hold;
 wire run_clock=!reset_n || (!complete && !trace_hold && (!sw_sync[11] || step_count==0));
`ifdef SYNTHESIS
 BUFGCE #(.SIM_DEVICE("7SERIES")) core_clock_buffer(.I(clock50),.CE(run_clock),.O(core_clk));
`else
 reg gate;
 always @(negedge clock50) gate<=run_clock;
 assign core_clk=clock50 && gate;
`endif
 wire req,we,mmreq,mmwe;
 wire [31:0] addr,wdata,mmaddr,mmdata;
 wire [3:0] strb,mmstrb;
 reg [31:0] rdata;
 (* ram_style="block" *) reg [31:0] ram[0:MEM_WORDS-1];
 initial $readmemh(MEM_FILE,ram);
 integer b;
 always @(posedge core_clk) begin
  if(req && addr < MEM_WORDS*4) begin
   rdata<=ram[addr[31:2]];
   if(we) for(b=0;b<4;b=b+1) if(strb[b]) ram[addr[31:2]][b*8+:8]<=wdata[b*8+:8];
  end else rdata<=0;
 end
 wire [31:0] pc,wbdata,wbpc,wbinst;
 wire [63:0] cycles;
 wire [31:0] ihits,imisses,dhits,dmisses;
 wire [3:0] refill_progress;
 wire [5:0] rd;
 wire wbwe,stall,loaduse,dm,im,flush,fpbusy,divbusy,zbb,retire;
 wire [4:0] flags;
 wire int_divzero,mul_active;
 reg [31:0] override_data;
 wire uart_busy;
 wire busy;
 // Explicit event map: bits 15..8 describe pipeline events, bits 7..0 status.
 wire [15:0] trace_events;
 assign trace_events[15]=stall;
 assign trace_events[14]=loaduse;
 assign trace_events[13]=dm;
 assign trace_events[12]=im;
 assign trace_events[11]=flush;
 assign trace_events[10]=fpbusy;
 assign trace_events[9]=divbusy|mul_active;
 assign trace_events[8]=retire && wbwe && rd!=0;
 assign trace_events[7]=flags[4];
 assign trace_events[6]=flags[3]|int_divzero;
 assign trace_events[5:3]=flags[2:0];
 assign trace_events[2]=zbb;
 assign trace_events[1]=uart_busy;
 assign trace_events[0]=complete;
 reg [31:0] mmread;
 always @(*) case(mmaddr[3:2])
  0:mmread={16'b0,sw_sync};
  1:mmread={busy,31'b0};
  default:mmread=0;
 endcase
 always @(posedge core_clk or negedge reset_n) begin
  if(!reset_n) begin override_data<=0; complete<=0; end
  else if(mmreq && mmwe && mmstrb[0]) case(mmaddr[3:2])
   2:override_data<=mmdata;
   3:complete<=mmdata[0];
  endcase
 end
 uart_trace_transport #(.CLOCK_HZ(UART_DIV_CLOCK)) transport(
 .clk(clock50),.reset_n(reset_n),.core_tick(run_clock),.verbose(sw_sync[12]),
 .switches_i(sw_sync),.leds_i(LED),.if_pc_i(pc),.ihit_i(ihits),.imiss_i(imisses),.dhit_i(dhits),.dmiss_i(dmisses),
 .cycle_i(cycles[31:0]),.pc_i(wbpc),.inst_i(wbinst),.wb_i(wbdata),.rd_i(rd),.valid_i(retire),.write_i(wbwe),
 .events_i(trace_events),.refill_i(refill_progress),
 .software_write(mmreq && mmwe && mmstrb[0] && mmaddr[3:2]==1),.software_byte(mmdata[7:0]),
 .core_hold(trace_hold),.software_busy(busy),.tx_busy(uart_busy),.tx(UART_TXD_IN));
 rv32imf_core core(.clk(core_clk),.reset_n(reset_n),.stall_ext(1'b0),.use_dsp_i(1'b1),
 .icache_bypass_i(!sw_sync[13]),.bp_bypass_i(sw_sync[9]),.dcache_bypass_i(!sw_sync[13]),
 .main_mem_req(req),.main_mem_we(we),.main_mem_addr(addr),.main_mem_wdata(wdata),.main_mem_wstrb(strb),.main_mem_rdata(rdata),
 .mmio_req(mmreq),.mmio_we(mmwe),.mmio_addr(mmaddr),.mmio_wdata(mmdata),.mmio_wstrb(mmstrb),.mmio_rdata(mmread),
 .ihit_o(ihits),.imiss_o(imisses),.dhit_o(dhits),.dmiss_o(dmisses),.cycle_count_o(cycles),.dcache_refill_o(refill_progress),.pc_if(pc),.pc_wb(wbpc),.wb_reg_write(wbwe),.wb_dest_reg(rd),.wb_data(wbdata),
 .hazard_stall(stall),.load_use_o(loaduse),.dcache_miss(dm),.icache_miss(im),.btb_mispredict(flush),
 .fpu_busy(fpbusy),.div_busy(divbusy),.zbb_active_o(zbb),.retire_o(retire),.wb_instruction_o(wbinst),.fp_flags_o(flags),.int_divzero_o(int_divzero),.mul_active_o(mul_active));
 wire [6:0] seg;
 assign {CG,CF,CE,CD,CC,CB,CA}=seg;
 nexys_a7_io_controller #(.CLOCK_HZ(SYSTEM_CLOCK_HZ)) display(.clk_100mhz(clock50),.rst_n(reset_n),.current_pc(pc),
 .wb_write_data(override_data),.sw_show_wb_on_seg7(sw_sync[10]),.pipeline_stall(stall),.load_use_hazard(loaduse),
 .dcache_miss_busy(dm),.icache_miss_busy(im),.btb_mispredict_flush(flush),.fpu_busy(fpbusy),.muldiv_busy(divbusy|mul_active),
 .retire_event(retire),.wb_reg_commit(retire && wbwe && rd!=0),.fpu_exc_nv(flags[4]),.fpu_exc_dz(flags[3]|int_divzero),.fpu_exc_of(flags[2]),
 .fpu_exc_uf(flags[1]),.fpu_exc_nx(flags[0]),.zbb_active(zbb),.uart_tx_active(uart_busy),.demo_complete(complete),
 .led(LED),.an(AN),.seg(seg),.dp(DP));
endmodule
