from pathlib import Path
import os,sys,subprocess,concurrent.futures
root=Path(__file__).resolve().parents[1];os.chdir(root)
iv=os.environ.get('IVERILOG','iverilog');vvp=os.environ.get('VVP','vvp')
flags=['-g2012','-Iintegration/modules/csr']
if os.environ.get('IVERILOG_BASE'):flags+=['-B',os.environ['IVERILOG_BASE']]
files=list(map(str,Path('integration/modules').rglob('*.v')))+list(map(str,Path('board').glob('*.v')))
def run(hz):
 stem=f'reports/timing_board_{hz}';exe=stem+'.vvp'
 subprocess.run([iv,*flags,'-s','tb_board_full',f'-Ptb_board_full.SYS_HZ={hz}','-o',exe,*files,'tests/tb_board_full.v'],check=True)
 with open(stem+'.log','w') as f:subprocess.run([vvp,exe,f'+LOG={stem}_uart.log'],stdout=f,stderr=subprocess.STDOUT,check=True)
 sys.path.insert(0,str(root/'tests'))
 from test_dashboard import DashboardTest
 a=DashboardTest().model()
 for line in Path(stem+'_uart.log').read_text().splitlines():a._handle_uart_line(line)
 assert len(a.received)==100 and a.check_count==57 and a.failures==0
 print(hz,'Hz: 100 packets, 57 checks, zero host failures',flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:list(pool.map(run,[50000000,40000000]))
