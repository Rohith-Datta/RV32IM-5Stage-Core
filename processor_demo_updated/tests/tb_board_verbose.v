`timescale 1ns/1ps
module tb_board_verbose;
 reg clk=0,rst=0;always #5 clk=~clk;wire tx;
 nexys_a7_top #(.UART_DIV_CLOCK(115200)) dut(.CLK100MHZ(clk),.CPU_RESETN(rst),.SW(16'h3032),.UART_TXD_IN(tx));
 reg [7:0] value,line[0:511];integer i,j,length=0,records=0,captured;
 initial begin #110 rst=1;end
 initial begin
 wait(rst);
 forever begin
  @(negedge tx);#30;
  for(i=0;i<8;i=i+1)begin value[i]=tx;#20;end
  if(tx!==1)$fatal(1,"Stop bit");
  if(value==10)begin
   if(line[0]!="[")$fatal(1,"Unexpected preamble record");
   captured=0;for(j=4;j<14;j=j+1)captured=captured*10+line[j]-"0";
   if(captured!=records)$fatal(1,"Lost/duplicated cycle: got=%0d expected=%0d",captured,records);
   records=records+1;length=0;
   if(records==32)begin $display("VERBOSE BOARD PASS: 32 consecutive actual core cycles, UART backpressure preserves every cycle");$finish;end
  end else begin line[length]=value;length=length+1;if(length==511)$fatal(1,"Line length");end
 end
 end
 initial begin #10000000;$fatal(1,"Timeout");end
endmodule
