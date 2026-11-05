module tb_pack_equivalence;
fpu_single_core dut();
    function [36:0] pack_reference;
        input sign_bit;
        input [63:0] magnitude;
        input integer scale;
        input extra_sticky;
        integer top, e, shift, k;
        reg found,g,sticky,nx,uf,of;
        reg [63:0] rounded;
        reg [31:0] packed_value;
        begin
            top=0;found=0;g=0;sticky=extra_sticky;nx=0;uf=0;of=0;
            for(k=63;k>=0;k=k-1) if(magnitude[k] && !found) begin top=k;found=1;end
            e=top+scale+127;
            shift = e>0 ? top-23 : -149-scale;
            if(shift>0) begin
                rounded=shift>=64 ? 0 : magnitude>>shift;
                if(shift<=64) g=magnitude[shift-1];
                for(k=0;k<64;k=k+1) if(k<shift-1) sticky=sticky|magnitude[k];
                nx=g|sticky;
                if(g && (sticky || rounded[0])) rounded=rounded+1;
            end else begin rounded=magnitude<<(-shift); nx=extra_sticky; end
            if(!found) packed_value={sign_bit,31'b0};
            else if(e<=0) begin
                if(rounded[23]) packed_value={sign_bit,8'h01,23'b0};
                else begin packed_value={sign_bit,8'b0,rounded[22:0]}; uf=nx;end
            end else begin
                if(rounded[24]) begin rounded=rounded>>1;e=e+1;end
                if(e>=255) begin packed_value={sign_bit,8'hff,23'b0};of=1;nx=1;end
                else packed_value={sign_bit,e[7:0],rounded[22:0]};
            end
            pack_reference={2'b00,of,uf,nx,packed_value};
        end
    endfunction
reg [63:0] magnitude;integer scale,i;reg sign_bit,sticky;
reg [36:0] old_value,new_value;
initial begin
 for(i=0;i<20000;i=i+1)begin
  magnitude={$random,$random};
  // Multiplication and division actually pass 48- and 26-bit magnitudes.
  if(i%2==0)magnitude=magnitude & 64'hffffffffffff;
  else magnitude=magnitude & 64'h3ffffff;
  scale=$random % 600;sign_bit=$random;sticky=$random;
  old_value=pack_reference(sign_bit,magnitude,scale,sticky);
  new_value=dut.pack_rne(sign_bit,magnitude,scale,sticky);
  if(old_value!==new_value)$fatal(1,"Packing mismatch magnitude=%h scale=%0d ref=%h got=%h",magnitude,scale,old_value,new_value);
 end
 $display("PACK EQUIVALENCE PASS: 20000 magnitudes/exponents with result and exception bits identical");$finish;
end
endmodule
