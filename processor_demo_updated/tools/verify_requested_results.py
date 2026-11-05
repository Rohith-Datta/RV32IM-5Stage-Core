"""Strict host validation of completed firmware logs for this revision."""
from pathlib import Path
import os,importlib.util
root=Path(__file__).resolve().parents[1];os.chdir(root)
spec=importlib.util.spec_from_file_location('dashboard_tests',root/'tests/test_dashboard.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
folder=Path('reports/requested_changes')
for name in ['uart_'+sw+'.log' for sw in ['2032','2232','6032','6232','0032','0232','a032','a232','e203']]+['late_profiler_uart.log']:
 a=m.DashboardTest().model();lines=(folder/name).read_text().splitlines()
 for line in lines:a._handle_uart_line(line)
 assert lines[-1]=='DEMO_COMPLETE',name
 assert a.failures==0 and a.check_count==57 and a.received==set(range(100)),(name,a.failures)
 if '6032' in name or '6232' in name or name.startswith('late_'):
  assert len(a.profile_records)==6,name
  assert max(i for i,x in enumerate(lines) if x.startswith('CSV,'))<min(i for i,x in enumerate(lines) if x.startswith('PROFILE,')),name
 if name.startswith('late_'):
  assert a.run_stats[3]==1 and a.last_switches==0x6032
  assert not a.__dict__.get('bp_runs'), 'Changed configuration must not enter comparison history'
 sw,cycles,instret,changed=a.run_stats
 print(f'{name}: PASS all 100 independent packet checks, 57 self-tests; cycles={cycles}, retired={instret}, IPC={instret/cycles:.6f}, changed={changed}')
