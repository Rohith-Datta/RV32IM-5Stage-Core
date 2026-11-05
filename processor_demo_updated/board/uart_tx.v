`timescale 1ns/1ps
module uart_tx #(parameter CLOCK_HZ=50000000, BAUD=115200)(
 input wire clk, reset_n, start, input wire [7:0] data,
 output reg tx, output wire busy
);
 localparam DIVISOR=(CLOCK_HZ+BAUD/2)/BAUD;
 reg [31:0] count;
 reg [3:0] remaining;
 reg [9:0] shift;
 assign busy=remaining!=0;
 always @(posedge clk or negedge reset_n) begin
  if(!reset_n) begin tx<=1; count<=0; remaining<=0; shift<=10'h3ff; end
  else if(!busy) begin
   tx<=1;
   if(start) begin shift<={1'b1,data,1'b0}; tx<=0; remaining<=10; count<=DIVISOR-1; end
  end else if(count!=0) count<=count-1;
  else begin
   count<=DIVISOR-1; shift<={1'b1,shift[9:1]}; remaining<=remaining-1;
   tx <= remaining==1 ? 1'b1 : shift[1];
  end
 end
endmodule
