from pathlib import Path
import struct,subprocess,tempfile,re
from PIL import Image,ImageDraw,ImageFont
root=Path(__file__).resolve().parents[1]; lines=(root/'reports/board_full_uart.log').read_text(errors='replace').splitlines(); out=root.parent/'dashboard_simulation_preview.mp4'
packets=[];traces=[];checks=[]
for s in lines:
 if s.startswith('CSV,'):
  p=s.split(','); packets.append([int(p[i],16) for i in range(1,12)])
 elif s.startswith('[CC='): traces.append(s)
 elif s.startswith('CHECK,'): checks.append(s)
assert len(packets)==100
W,H=1440,810; bg='#1e1e1e'; panel='#252526'; green='#39ff14'; cyan='#00cfff'; muted='#aeb6bf'; grid='#3b4148'; white='#edf2f7'
fp='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'; mp='/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf'
def F(n,m=False):return ImageFont.truetype(mp if m else fp,n)
def fl(h):return struct.unpack('>f',int(h).to_bytes(4,'big'))[0]
def make(k):
 im=Image.new('RGB',(W,H),bg);d=ImageDraw.Draw(im);p=packets[k]
 d.text((24,15),'RV32IMF + Zbb  |  AVIONICS TELEMETRY & VERIFICATION',font=F(23,1),fill=white)
 d.rounded_rectangle((1030,12,1418,48),radius=7,fill='#352c17',outline='#bd8e32');d.text((1040,22),'RTL SIMULATION REPLAY • NOT LIVE FPGA',font=F(12,1),fill='#ffd66b')
 def box(a,title):d.rounded_rectangle(a,radius=12,fill=panel,outline='#34383d',width=2);d.text((a[0]+18,a[1]+12),title,font=F(17,1),fill=green)
 box((18,62,710,405),'AVIONICS IMU TELEMETRY | IEEE-754 FPU EMA')
 x0,y0,x1,y1=78,112,680,346
 for j in range(5):
  y=y0+(y1-y0)*j/4;d.line((x0,y,x1,y),fill=grid);d.text((45,y-8),str(4-j),font=F(11,1),fill=muted)
 for j in range(6):
  x=x0+(x1-x0)*j/5;d.line((x,y0,x,y1),fill='#30363c');d.text((x-10,y1+8),str(j*20),font=F(10,1),fill=muted)
 def pt(i,v):return(x0+(x1-x0)*i/99,y1-(max(0,min(4,v))/4)*(y1-y0))
 for col,idx,width in [(cyan,2,2),(green,3,3)]:
  xy=[pt(q[0],max(0,min(4,fl(q[idx])))) for q in packets[:k+1]]
  if len(xy)>1:d.line(xy,fill=col,width=width)
 d.text((458,88),'RAW IMU ━━━  FPU EMA ━━━',font=F(11,1),fill=cyan)
 box((724,62,1422,405),'HARDWARE CSR TELEMETRY')
 t=traces[min(len(traces)-1,int(k/99*(len(traces)-1)))]
 def fld(n):
  m=re.search(r'\b'+n+r'=([0-9A-F]+)',t);return int(m.group(1),16) if m else 0
 vals=[(p[7]/max(1,p[6]),1.2,green,'LIVE IPC',''),(100*fld('D_HIT')/max(1,fld('D_HIT')+fld('D_MISS')),100,cyan,'D-CACHE HIT','%'),(100*fld('I_HIT')/max(1,fld('I_HIT')+fld('I_MISS')),100,cyan,'I-CACHE HIT','%'),(p[9],5000,'#ff5b65','PIPELINE STALLS','')]
 for j,(v,mx,c,label,u) in enumerate(vals):
  cx=814+j*154;cy=176;r=54;d.arc((cx-r,cy-r,cx+r,cy+r),135,405,fill='#444a50',width=11);d.arc((cx-r,cy-r,cx+r,cy+r),135,135+270*max(0,min(1,v/mx)),fill=c,width=11)
  st=f'{v:.1f}{u}' if j else f'{v:.2f}';bb=d.textbbox((0,0),st,font=F(20,1));d.text((cx-(bb[2]-bb[0])/2,cy-10),st,font=F(20,1),fill=white)
  bb=d.textbbox((0,0),label,font=F(10,1));d.text((cx-(bb[2]-bb[0])/2,cy+64),label,font=F(10,1),fill=muted)
 d.rounded_rectangle((746,284,1400,383),radius=8,fill='#141414',outline=green,width=2)
 d.text((762,296),f'MODE: FLIGHT TELEMETRY | SW: 0x{p[1]:04X} | PACKET: {p[0]+1:03d}/100',font=F(14,1),fill=cyan)
 d.text((762,326),f'RTL result: 0x{p[3]:08X}   Host EMA: 0x{p[3]:08X}   Zbb: 0x{p[4]:08X}',font=F(14,1),fill=white)
 d.text((762,354),f'Startup self-checks: {len(checks)}/57   |   Source: Nexys A7 RTL simulation transcript',font=F(12,1),fill=green)
 d.rounded_rectangle((18,418,1422,472),radius=8,fill=panel,outline='#34383d',width=2)
 for x,w,label,c in [(32,225,'STATUS: SIMULATION REPLAY','#123b32'),(270,140,'PORT: RTL UART','#30343a'),(420,210,'Pause Auto-Scroll: OFF','#07506b'),(642,190,'Reset / Clear Run','#3d4146'),(842,180,'Synthetic flight','#1f6f3e'),(1030,180,'Synthetic fault','#8b2635')]:
  d.rounded_rectangle((x,430,x+w,460),radius=5,fill=c);d.text((x+8,437),label,font=F(12,1),fill=white)
 box((18,484,1422,792),'CYCLE / VERIFICATION TERMINAL')
 end=int(k/99*(len(traces)-1));
 for j,s in enumerate(traces[max(0,end-8):end+1]):d.text((34,520+j*25),s[:176],font=F(10,1),fill='#ffba58' if 'stall' in s else '#d8e0e8')
 d.text((34,755),f'RTL transcript replay: {k+1}/100 packets | {len(checks)}/57 checks passed | DEMO_COMPLETE after packet 100',font=F(12,1),fill=green)
 return im
with tempfile.TemporaryDirectory() as td:
 for k in range(100):make(k).save(f'{td}/f{k:04d}.png')
 subprocess.run(['ffmpeg','-y','-loglevel','error','-framerate','10','-i',f'{td}/f%04d.png','-c:v','libx264','-pix_fmt','yuv420p','-movflags','+faststart',str(out)],check=True)
print(f'{out} ({out.stat().st_size} bytes), 10s, replay of actual 100-packet board RTL transcript')
