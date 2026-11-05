"""Validate the two profiler settings through the complete physical-UART model."""
from pathlib import Path
import os,sys,subprocess,importlib.util
root=Path(__file__).resolve().parents[1];os.chdir(root)
spec=importlib.util.spec_from_file_location('dashboard_tests',root/'tests/test_dashboard.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
iv=os.environ.get('IVERILOG','iverilog');vvp=os.environ.get('VVP','vvp')
flags=['-g2012','-Iintegration/modules/csr']
if os.environ.get('IVERILOG_BASE'):flags+=['-B',os.environ['IVERILOG_BASE']]
out=root/'reports/requested_changes';out.mkdir(exist_ok=True)
files=list(map(str,Path('integration/modules').rglob('*.v')))+list(map(str,Path('board').glob('*.v')))
exe=str(out/'board.vvp')
subprocess.run([iv,*flags,'-s','tb_board_full','-o',exe,*files,'tests/tb_board_full.v'],check=True)
history={};counts={}
for sw in (0x6032,0x6232):
 log=out/f'board_{sw:04x}_uart.log'
 if "--reuse" not in sys.argv or not log.exists():
  run=subprocess.run([vvp,exe,f'+SW={sw:04x}',f'+LOG={log}'],check=True,capture_output=True,text=True,timeout=360)
  (out/f'board_{sw:04x}.log').write_text(run.stdout+run.stderr)
 lines=log.read_text().splitlines()
 a=module.DashboardTest().model();a.bp_runs=history
 for line in lines:a._handle_uart_line(line)
 assert a.received==set(range(100)) and a.check_count==57 and a.failures==0,(sw,a.failures,a.logs[-20:])
 assert a.trace_rows==256 and not a.__dict__.get("trace_gap",False)
 assert len(a.profile_records)==6
 assert lines.index(next(x for x in lines if x.startswith('PROFILE,')))>max(i for i,x in enumerate(lines) if x.startswith('CSV,'))
 subprocess.run([sys.executable,'tests/check_profiles.py',str(log)],check=True)
 assert sum('IF PC ' in x[0] and 'WB instruction:' in x[0] for x in a.logs)==256
 assert a.run_stats[0]==sw and a.run_stats[3]==0
 counts[sw]=a.run_stats[1:3]
 (out/f'dashboard_{sw:04x}.log').write_text('\n'.join(x[0] for x in a.logs)+'\n')
 print(f'{sw:04X}: 100 packets, 57 checks, six final timing windows, 256 IF-PC trace rows; cycles={counts[sw][0]}, retired={counts[sw][1]}, IPC={counts[sw][1]/counts[sw][0]:.6f}',flush=True)
assert counts[0x6232][0]>counts[0x6032][0],counts
assert any('[BP COMPARISON] ON:' in x[0] for x in a.logs)
print('Full board/UART comparison PASS')
