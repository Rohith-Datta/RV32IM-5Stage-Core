`timescale 1ns/1ps
module tb_zbb_observer;
 reg clk=0;always #5 clk=~clk;
 reg [31:0] instruction;reg active=1,held=0;
 wire event_z;
 pipeline_5stage dut(.clk(clk),.reset_n(1'b0),.stall_ext(1'b0),.bp_bypass_i(1'b0),.zbb_active_o(event_z));
 integer n=0;
 task check;
 input [31:0] word;input expected;
 begin instruction=word;#1;if(event_z!==expected)$fatal(1,"Zbb observer word=%h event=%b expected=%b",word,event_z,expected);n=n+1;end
 endtask
 initial begin
  force dut.ex_instruction_trace=instruction;force dut.ex_valid=active;force dut.stall_id_ex=held;
  check(32'h60000013,0); // ADDI immediate mimics Zbb funct7
  check(32'h60001013,1); // CLZ
  check(32'h60101013,1);check(32'h60201013,1); // CTZ CPOP
  check(32'h60401013,1);check(32'h60501013,1); // SEXT
  check(32'h69805013,1);check(32'h28705013,1); // REV8 ORC.B
  check(32'h60105013,1); // RORI
  check(32'h60001033,1);check(32'h60005033,1); // ROL ROR
  check(32'h40004033,1);check(32'h40006033,1);check(32'h40007033,1);
  check(32'h0a004033,1);check(32'h0a005033,1);check(32'h0a006033,1);check(32'h0a007033,1);
  check(32'h08004033,1); // ZEXT.H with rs2 zero
  check(32'h08104033,0);check(32'h40005033,0);check(32'h60000063,0);check(32'h60002003,0);
  held=1;check(32'h69805013,0);held=0;active=0;check(32'h69805013,0);
  $display("ZBB OBSERVER PASS checks=%0d",n);$finish;
 end
endmodule
