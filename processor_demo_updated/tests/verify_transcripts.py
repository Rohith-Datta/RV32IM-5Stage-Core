from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from test_dashboard import DashboardTest
report_root=Path(sys.argv[1]) if len(sys.argv)>1 else Path('reports')
failures=0
for sw in [0x2032,0x0032,0x6032,0xa032]+[0xe000+i for i in range(1,12)]:
 p=report_root/f'uart_{sw:04x}.log';a=DashboardTest().model();raw_errors=0
 for line in p.read_text().splitlines():
  a._handle_uart_line(line)
  if line.startswith('CSV,') and sw>>14!=3:
   parts=line.split(',');i=int(parts[1],16)
   expected_raw=0x3f800000+(i%16)*0x100000+(0x600000 if i%7==0 else 0)
   raw_errors+=int(parts[3],16)!=expected_raw
 errors=a.failures+raw_errors
 ok=len(a.received)==100 and a.check_count==57 and errors==0 and 'DEMO_COMPLETE' in p.read_text()
 failures+=not ok
 print(f'{sw:04X}: packets={len(a.received)} checks={a.check_count} verification_errors={errors} PASS={ok}')
if failures:raise SystemExit(1)
