from pathlib import Path
import os, subprocess
root=Path(__file__).resolve().parents[1];os.chdir(root)
iv=os.environ.get('IVERILOG','iverilog');vvp=os.environ.get('VVP','vvp')
flags=['-g2012','-Iintegration/modules/csr']
if os.environ.get('IVERILOG_BASE'):flags+=['-B',os.environ['IVERILOG_BASE']]
files=list(map(str,Path('integration/modules').rglob('*.v')))+list(map(str,Path('board').glob('*.v')))
for name in ['tb_board_verbose','tb_board_full']:
 subprocess.run([iv,*flags,'-s',name,'-o',f'reports/{name}.vvp',*files,f'tests/{name}.v'],check=True)
 with open(f'reports/{name}.log','w') as log:subprocess.run([vvp,f'reports/{name}.vvp'],stdout=log,stderr=subprocess.STDOUT,check=True)
 print(name,'PASS',flush=True)
