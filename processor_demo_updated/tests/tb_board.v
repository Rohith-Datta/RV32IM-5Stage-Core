`timescale 1ns/1ps
module tb_board;
 reg clk=0,rst=0;always #5 clk=~clk;
 wire tx;wire [15:0] led;
 nexys_a7_top #(.UART_DIV_CLOCK(1152000)) dut(.CLK100MHZ(clk),.CPU_RESETN(rst),.SW(16'h2032),.LED(led),.UART_TXD_IN(tx));
 reg [7:0] value,line[0:511];integer i,length=0,traces=0;
 integer out;
 initial begin out=$fopen("reports/board_uart.log","w");#110 rst=1;end
 initial begin
 wait(rst);
 forever begin
  @(negedge tx);#300;
  for(i=0;i<8;i=i+1)begin value[i]=tx;#200;end
  if(tx!==1)$fatal(1,"UART stop bit");
  $fwrite(out,"%c",value);
  if(value==10) begin
   if(line[0]=="[")traces=traces+1;
   if(line[0]=="C" && line[1]=="S" && line[2]=="V" && line[3]==",")begin
    if(length!=102 || traces==0)$fatal(1,"CSV corruption length=%0d traces=%0d",length,traces);
    $display("BOARD PASS: %0d hardware traces then one intact firmware CSV line through real UART",traces);$fclose(out);$finish;
   end
   length=0;
  end else begin line[length]=value;length=length+1;if(length==511)$fatal(1,"Overlong line");end
 end
 end
 initial begin #100000000;$fatal(1,"Board UART timeout");end
endmodule
