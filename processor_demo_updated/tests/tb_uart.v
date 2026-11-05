`timescale 1ns/1ps
module tb_uart;
 reg clk=0,rst=0,start=0;reg [7:0] data;wire tx,busy;
 always #10 clk=~clk;
 uart_tx dut(.clk(clk),.reset_n(rst),.start(start),.data(data),.tx(tx),.busy(busy));
 integer k;reg [7:0] got;
 initial begin
 #35 rst=1;@(negedge clk);data=8'ha5;start=1;@(negedge clk);start=0;
 repeat(217)@(posedge clk); if(tx!==0)$fatal(1,"Start bit");
 for(k=0;k<8;k=k+1)begin repeat(434)@(posedge clk);got[k]=tx;end
 repeat(434)@(posedge clk);if(tx!==1 || got!==8'ha5)$fatal(1,"8N1 frame %h",got);
 wait(!busy);$display("UART PASS: 115200 baud at 50 MHz, byte A5, start/data/stop");$finish;
 end
endmodule
