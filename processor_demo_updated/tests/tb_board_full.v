`timescale 1ns/1ps
module tb_board_full #(parameter SYS_HZ=50000000);
 localparam real BIT_NS=1000000000.0/SYS_HZ;
 reg clk=0,rst=0;always #5 clk=~clk;
 wire tx;wire [15:0]led;reg [15:0] switches;
 nexys_a7_top #(.SYSTEM_CLOCK_HZ(SYS_HZ),.UART_DIV_CLOCK(115200)) dut(.CLK100MHZ(clk),.CPU_RESETN(rst),.SW(switches),.LED(led),.UART_TXD_IN(tx));
 reg [7:0] value,line[0:511];integer i,length=0,traces=0,checks=0,packets=0,out;
 reg [1023:0] logpath;
 initial begin
 if(!$value$plusargs("SW=%h",switches))switches=16'h2032;
 if(!$value$plusargs("LOG=%s",logpath))logpath="reports/board_full_uart.log";
 out=$fopen(logpath,"w");#110 rst=1;end
 initial begin
 wait(rst);
 forever begin
  @(negedge tx);#(1.5*BIT_NS);
  for(i=0;i<8;i=i+1)begin value[i]=tx;#(BIT_NS);end
  if(tx!==1)$fatal(1,"UART stop bit");
  $fwrite(out,"%c",value);
  if(value==10)begin
   if(line[0]=="[")traces=traces+1;
   if(line[0]=="C" && line[1]=="H")checks=checks+1;
   if(line[0]=="C" && line[1]=="S")begin
    if(length!=102)$fatal(1,"Malformed CSV length=%0d",length);packets=packets+1;
   end
   if(length==13 && line[0]=="D" && line[1]=="E" && line[2]=="M")begin
    if(packets!=100 || checks!=57 || traces<64)$fatal(1,"Missing records: CSV=%0d CHECK=%0d TRACE=%0d",packets,checks,traces);
    wait(led[0]);
    $display("FULL BOARD PASS: %0d CSV packets, %0d self-tests, %0d hardware traces; DEMO_COMPLETE and RTL LED[0] output observed",packets,checks,traces);
    $fclose(out);$finish;
   end
   length=0;
  end else begin line[length]=value;length=length+1;if(length==511)$fatal(1,"Overlong line");end
 end
 end
 initial begin #500000000;$fatal(1,"Full board timeout");end
endmodule
