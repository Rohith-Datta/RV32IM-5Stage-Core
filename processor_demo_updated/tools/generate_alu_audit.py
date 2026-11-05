from pathlib import Path
import random
root=Path(__file__).resolve().parents[1]
r=random.Random(42);mask=(1<<32)-1
signed=lambda x:x-(1<<32) if x>>31 else x
names=['andn','orn','xnor','clz','ctz','cpop','min','minu','max','maxu','sextb','sexth','zexth','rol','ror','rori','orcb','rev8','add','sub','sra','srai','srl','slt']
code=['module tb_alu_audit; reg [31:0] a,b,imm;reg [2:0] f3;reg [6:0] f7;reg im,sub;wire [31:0] z;integer n=0,bad=0; alu_zbb dut(a,b,imm,f3,sub,im,f7,z); initial begin']
for name in names:
 for i in range(80):
  a=r.getrandbits(32);b=r.getrandbits(32);shift=b&31;f7=0;im=0;sub=0;imm=0
  if name in ('andn','orn','xnor'):f7=32;f3={'andn':7,'orn':6,'xnor':4}[name];e={'andn':a&~b,'orn':a|~b,'xnor':~(a^b)}[name]
  elif name in ('clz','ctz','cpop','sextb','sexth'):
   f3=1;f7=48;im=1;imm={'clz':0x600,'ctz':0x601,'cpop':0x602,'sextb':0x604,'sexth':0x605}[name];b=imm
   e={'clz':32-a.bit_length(),'ctz':(a&-a).bit_length()-1 if a else 32,'cpop':a.bit_count(),'sextb':(a&127)-(a&128),'sexth':(a&32767)-(a&32768)}[name]
  elif name in ('min','minu','max','maxu'):f7=5;f3={'min':4,'minu':5,'max':6,'maxu':7}[name];e={'min':min(signed(a),signed(b)),'minu':min(a,b),'max':max(signed(a),signed(b)),'maxu':max(a,b)}[name]
  elif name=='zexth':f7=4;f3=4;b=0;e=a&65535
  elif name in ('rol','ror','rori'):
   f7=48;f3=1 if name=='rol' else 5;im=int(name=='rori');imm=0x600|shift
   if im:b=imm
   e=((a<<shift)|(a>>(32-shift))) if name=='rol' else ((a>>shift)|(a<<(32-shift)))
  elif name=='orcb':f7=20;f3=5;im=1;imm=0x287;b=imm;e=sum((255 if (a>>(8*j))&255 else 0)<<(8*j) for j in range(4))
  elif name=='rev8':f7=52;f3=5;im=1;imm=0x698;b=imm;e=int.from_bytes(a.to_bytes(4,'little'),'big')
  elif name=='add':f3=0;e=a+b
  elif name=='sub':f3=0;sub=1;f7=32;e=a-b
  elif name in ('sra','srai'):f3=5;sub=1;f7=32;im=int(name=='srai');imm=0x400|shift;b=imm if im else b;e=signed(a)>>shift
  elif name=='srl':f3=5;e=a>>shift
  elif name=='slt':f3=2;e=int(signed(a)<signed(b))
  code.append(f"a=32'h{a:08x};b=32'h{b:08x};imm=32'h{imm:08x};f3=3'd{f3};f7=7'd{f7};im={im};sub={sub};#1;n=n+1;if(z!==32'h{e&mask:08x}) begin bad=bad+1;if(bad<8)$display(\"FAIL {name} a=%h b=%h got=%h expected={e&mask:08x}\",a,b,z);end")
code+=['$display("ALU AUDIT cases=%0d failures=%0d",n,bad);if(bad)$fatal(1,"ALU audit mismatch");$finish;end endmodule']
(root/'tests/tb_alu_audit.v').write_text('\n'.join(code))
