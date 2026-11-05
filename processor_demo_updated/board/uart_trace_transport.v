`timescale 1ns/1ps
// Line-atomic UART arbitration and lossless per-active-cycle snapshot transport.
// The entire core clock is stopped while a record is serialized. No core-cycle
// events are synthesized by software. Software CSV lines are buffered separately.
module uart_trace_transport #(parameter CLOCK_HZ=50000000, parameter HYBRID_EVENT_LIMIT=64, parameter TRACE_WINDOW_CYCLES=256)(
 input wire clk,reset_n,core_tick,verbose,
 input wire [31:0] cycle_i,pc_i,inst_i,wb_i,
 input wire [15:0] switches_i,leds_i,
 input wire [31:0] if_pc_i,ihit_i,imiss_i,dhit_i,dmiss_i,
 input wire [5:0] rd_i,
 input wire valid_i,write_i,
 input wire [15:0] events_i,
 input wire [3:0] refill_i,
 input wire software_write,input wire [7:0] software_byte,
 output wire core_hold, software_busy,tx_busy,tx
);
 reg [7:0] line_buffer[0:127];
 reg [7:0] line_length;
 reg line_pending,trace_pending;
 reg [7:0] hybrid_events;
 reg quiet;
 reg [31:0] saved_cycle,saved_pc,saved_inst,saved_wb;
 reg [39:0] cycle_bcd,saved_bcd;
 reg carry;integer digit;
 reg [15:0] saved_switches,saved_leds;
 reg [31:0] saved_ifpc,saved_ihit,saved_imiss,saved_dhit,saved_dmiss;
 reg [5:0] saved_rd;
 reg saved_valid,saved_write;
 reg [15:0] saved_events;
 reg [3:0] saved_refill;
 reg [2:0] saved_reason;
 reg active,trace_frame,finishing;
 reg [8:0] char_index;
 reg uart_start;reg [7:0] uart_data;
 wire shifting;
 assign core_hold=active || trace_pending || line_pending;
 assign software_busy=line_pending || line_length==128;
 assign tx_busy=shifting || active || line_pending || trace_pending;
 uart_tx #(.CLOCK_HZ(CLOCK_HZ)) transmitter(.clk(clk),.reset_n(reset_n),.start(uart_start),.data(uart_data),.tx(tx),.busy(shifting));
 function [7:0] hex_digit;
  input [3:0] nibble;
  begin hex_digit=nibble<10 ? "0"+nibble : "A"+nibble-10;end
 endfunction
 function [7:0] small_decimal;
  input [5:0] value;input tens;
  begin small_decimal="0"+(tens ? value/10 : value%10);end
 endfunction
 localparam integer PREFIX_LENGTH=213, REASON_LENGTH=57, TRACE_LENGTH=PREFIX_LENGTH+REASON_LENGTH+1;
 function [7:0] trace_char;
  input [8:0] index;
  reg [1703:0] prefix;
  reg [455:0] reason_text;
  begin
   prefix="[CC=CCCCCCCCCC] PC: 0xPPPPPPPP | INST: 0xIIIIIIII | WB: BDD <= 0xWWWWWWWW [WE=E] [VALID=V] | EVENT: FFFF | DREFILL: RR | SW=SSSS LED=LLLL IFPC=QQQQQQQQ I_HIT=AAAAAAAA I_MISS=BBBBBBBB D_HIT=DDDDDDDD D_MISS=EEEEEEEE";
   case(saved_reason)
                3'd0: reason_text=" [RUN]                                                   ";
                3'd1: reason_text=" ---------stall--------- <-- [LOAD-USE DATA HAZARD STALL]";
                3'd2: reason_text=" ---------stall--------- <-- [D-CACHE MISS / BYPASS WAIT]";
                3'd3: reason_text=" ---------stall--------- <-- [I-CACHE MISS REFILL]       ";
                3'd4: reason_text=" ---------stall--------- <-- [FPU MULTI-CYCLE WAIT]      ";
                3'd5: reason_text=" ---------stall--------- <-- [INTEGER MUL/DIV WAIT]      ";
                3'd6: reason_text=" ---------flush--------- <-- [BTB MISPREDICTION FLUSH]   ";
                3'd7: reason_text=" [PIPELINE BUBBLE]                                       ";
   endcase
   if(index<PREFIX_LENGTH) trace_char=prefix[(PREFIX_LENGTH-1-index)*8+:8];
   else if(index<PREFIX_LENGTH+REASON_LENGTH) trace_char=reason_text[(PREFIX_LENGTH+REASON_LENGTH-1-index)*8+:8];
   else trace_char=8'h0a;
   if(index>=4 && index<14) trace_char="0"+saved_bcd[(9-(index-4))*4+:4]; if(index>=22 && index<30) trace_char=hex_digit(saved_pc >> ((7-(index-22))*4)); if(index>=41 && index<49) trace_char=hex_digit(saved_inst >> ((7-(index-41))*4)); if(index>=65 && index<73) trace_char=hex_digit(saved_wb >> ((7-(index-65))*4)); if(index>=100 && index<104) trace_char=hex_digit(saved_events >> ((3-(index-100))*4)); if(index>=116 && index<118) trace_char=small_decimal({2'b0,saved_refill},index==116); if(index==56) trace_char=saved_rd[5] ? "f" : "x"; if(index==57 || index==58) trace_char=small_decimal({1'b0,saved_rd[4:0]},index==57); if(index==78) trace_char=saved_write ? "1" : "0"; if(index==88) trace_char=saved_valid ? "1" : "0";
   if(index>=124 && index<128) trace_char=hex_digit(saved_switches >> ((3-(index-124))*4));
   if(index>=133 && index<137) trace_char=hex_digit(saved_leds >> ((3-(index-133))*4));
   if(index>=143 && index<151) trace_char=hex_digit(saved_ifpc >> ((7-(index-143))*4));
   if(index>=158 && index<166) trace_char=hex_digit(saved_ihit >> ((7-(index-158))*4));
   if(index>=174 && index<182) trace_char=hex_digit(saved_imiss >> ((7-(index-174))*4));
   if(index>=189 && index<197) trace_char=hex_digit(saved_dhit >> ((7-(index-189))*4));
   if(index>=205 && index<213) trace_char=hex_digit(saved_dmiss >> ((7-(index-205))*4));
  end
 endfunction
 wire fp_commit=valid_i && inst_i[6:0]==7'h53;
 wire key_event=events_i[15] || events_i[11];
 wire capture=!quiet && (verbose || fp_commit || cycle_i < TRACE_WINDOW_CYCLES);
 // Payload RAM has no asynchronous reset; length/pending reset discards old data.
 always @(posedge clk) begin
  if(reset_n && core_tick && !core_hold && software_write && !software_busy)
   line_buffer[line_length[6:0]]<=software_byte;
 end
 always @(posedge clk or negedge reset_n) begin
  if(!reset_n) begin
   line_length<=0;line_pending<=0;trace_pending<=0;hybrid_events<=0;quiet<=0;
   cycle_bcd<=0;saved_bcd<=0;saved_switches<=0;saved_leds<=0;saved_ifpc<=0;saved_ihit<=0;saved_imiss<=0;saved_dhit<=0;saved_dmiss<=0;
   saved_cycle<=0;saved_pc<=0;saved_inst<=0;saved_wb<=0;saved_rd<=0;
   saved_valid<=0;saved_write<=0;saved_events<=0;saved_refill<=0;saved_reason<=0;
   active<=0;trace_frame<=0;finishing<=0;char_index<=0;uart_start<=0;uart_data<=0;
  end else begin
   uart_start<=0;
   if(core_tick && !core_hold) begin
    carry=1;
    for(digit=0;digit<10;digit=digit+1) begin
     if(carry) begin
      if(cycle_bcd[digit*4+:4]==9) cycle_bcd[digit*4+:4]<=0;
      else begin cycle_bcd[digit*4+:4]<=cycle_bcd[digit*4+:4]+1;carry=0;end
     end
    end
    if(cycle_i==32'hffffffff) cycle_bcd<=0;
    if(software_write && !software_busy) begin
     line_length<=line_length+1;
     if(software_byte==10 || line_length==127) begin
      line_pending<=1;
      if(line_length==13 && line_buffer[0]=="D" && line_buffer[1]=="E" && line_buffer[2]=="M" && line_buffer[3]=="O") quiet<=1;
     end
    end
    if(capture) begin
     trace_pending<=1;
     if(!verbose && key_event && hybrid_events<HYBRID_EVENT_LIMIT) hybrid_events<=hybrid_events+1;
     saved_bcd<=cycle_bcd;saved_switches<=switches_i;saved_leds<=leds_i;
     saved_ifpc<=if_pc_i;saved_ihit<=ihit_i;saved_imiss<=imiss_i;saved_dhit<=dhit_i;saved_dmiss<=dmiss_i;
     saved_cycle<=cycle_i;saved_pc<=pc_i;saved_inst<=inst_i;saved_wb<=wb_i;
     saved_rd<=rd_i;saved_valid<=valid_i;saved_write<=valid_i && write_i && rd_i!=0;
     saved_events<=events_i;saved_refill<=refill_i;
     if(events_i[13] && events_i[15]) saved_reason<=2;
     else if(events_i[12]) saved_reason<=3;
     else if(events_i[14]) saved_reason<=1;
     else if(events_i[10]) saved_reason<=4;
     else if(events_i[9] && events_i[15]) saved_reason<=5;
     else if(events_i[11]) saved_reason<=6;
     else if(!valid_i) saved_reason<=7;
     else saved_reason<=0;
    end
   end
   if(!active) begin
    if(trace_pending || line_pending) begin
     active<=1;trace_frame<=trace_pending;char_index<=0;finishing<=0;
    end
   end else if(!shifting && !uart_start) begin
    if(finishing) begin
     active<=0;finishing<=0;
     if(trace_frame) trace_pending<=0;
     else begin line_pending<=0;line_length<=0;end
    end else begin
     uart_data<=trace_frame ? trace_char(char_index) : line_buffer[char_index[6:0]];
     uart_start<=1;
     if(char_index==(trace_frame ? TRACE_LENGTH-1 : line_length-1)) finishing<=1;
     else char_index<=char_index+1;
    end
   end
  end
 end
endmodule
