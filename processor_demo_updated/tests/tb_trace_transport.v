`timescale 1ns/1ps
module tb_trace_transport;
 reg clk=0,rst=0,tick=0,sw_write=0;always #10 clk=~clk;
 reg [15:0] event_bits; reg [7:0] sw_byte;reg [31:0] cycle=0;
 wire hold,busy,tx;integer k,trace_lines=0,csv_lines=0,total_bytes=0;
 reg [7:0] line[0:511];integer length=0,i,j; reg [455:0] expected_reason;reg [7:0] value;
 reg [55:0] message="CSV,AB\n";
 uart_trace_transport #(.CLOCK_HZ(1152000)) dut(.clk(clk),.reset_n(rst),.core_tick(tick),.verbose(1'b1),
 .switches_i(16'h3032),.leds_i(16'h8200),.if_pc_i(32'h1234567c),.ihit_i(32'd9),.imiss_i(32'd1),.dhit_i(32'd3),.dmiss_i(32'd1),.cycle_i(cycle),.pc_i(32'h12345678),.inst_i(32'h00b50553),.wb_i(32'h3f800000),.rd_i(6'd33),
 .valid_i(1'b1),.write_i(1'b1),.events_i(event_bits),.refill_i(4'd9),
 .software_write(sw_write),.software_byte(sw_byte),.core_hold(hold),.software_busy(busy),.tx(tx));
 initial begin
  #35 rst=1;
  for(k=0;k<8;k=k+1)begin
   @(negedge clk);wait(!hold);@(negedge clk);
   case(k)
    0:event_bits=16'ha000; // D miss and stall
    1:event_bits=16'h9400; // I miss overlaps FPU busy: cache reason wins
    2:event_bits=16'hc000; // load use
    3:event_bits=16'h8400; // FPU
    4:event_bits=16'h8200; // integer mul/div
    5:event_bits=16'h0800; // flush
    6:event_bits=16'h0000; // running
    7:event_bits=16'h2000; // cached store miss without a stall
   endcase
   cycle=0+k;sw_byte=k<7 ? message[(6-k)*8+:8] : 0;tick=1;sw_write=k<7;
   @(negedge clk);tick=0;sw_write=0;wait(!hold);
  end
  #1000;
  if(trace_lines!=8 || csv_lines!=1)$fatal(1,"Lost trace/CSV records: traces=%0d CSV=%0d",trace_lines,csv_lines);
  $display("TRACE TRANSPORT PASS: eight distinct core snapshots and one intact CSV line, no byte interleaving");$finish;
 end
 initial forever begin
  @(negedge tx);#300;
  for(i=0;i<8;i=i+1)begin value[i]=tx;#200;end
  if(tx!==1)$fatal(1,"Bad UART stop bit");
  total_bytes=total_bytes+1;
  if(value==10)begin
   if(line[0]=="[")begin
    if(line[13]!=="0"+trace_lines)$fatal(1,"Incorrect captured cycle digit %h",line[13]);
    case(trace_lines)
     0:expected_reason=" ---------stall--------- <-- [D-CACHE MISS / BYPASS WAIT]";
     1:expected_reason=" ---------stall--------- <-- [I-CACHE MISS REFILL]       ";
     2:expected_reason=" ---------stall--------- <-- [LOAD-USE DATA HAZARD STALL]";
     3:expected_reason=" ---------stall--------- <-- [FPU MULTI-CYCLE WAIT]      ";
     4:expected_reason=" ---------stall--------- <-- [INTEGER MUL/DIV WAIT]      ";
     5:expected_reason=" ---------flush--------- <-- [BTB MISPREDICTION FLUSH]   ";
     6,7:expected_reason=" [RUN]                                                   ";
    endcase
    for(j=0;j<57;j=j+1)if(line[213+j]!==expected_reason[(56-j)*8+:8])$fatal(1,"Trace reason mismatch case=%0d char=%0d got=%h",trace_lines,j,line[213+j]);
    if(line[93]!=="E" || line[116]!=="0" || line[117]!=="9")$fatal(1,"Event label/refill count mismatch");
    trace_lines=trace_lines+1;
   end else if(length==6 && line[0]=="C" && line[1]=="S" && line[2]=="V" && line[3]=="," && line[4]=="A" && line[5]=="B")csv_lines=csv_lines+1;
   else $fatal(1,"Interleaved/corrupt serial line length=%0d",length);
   length=0;
  end else begin line[length]=value;length=length+1;if(length==511)$fatal(1,"Overlong line");end
 end
 initial begin #10000000;$fatal(1,"Timeout");end
endmodule
