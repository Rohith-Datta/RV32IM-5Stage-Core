from pathlib import Path
import subprocess,sys,os
sys.path.insert(0,str(Path.cwd()))
from dashboard import HostGoldenModel
vvp=sys.argv[1] if len(sys.argv)>1 else 'vvp'
modes=[int(x,16) for x in sys.argv[2:]] or [0x2032,0x0032,0x6032,0xa032]+[0xe000+i for i in range(1,12)]
report_root=Path(os.environ.get('REPORT_PREFIX','reports'));report_root.mkdir(parents=True,exist_ok=True)
failures=0
for sw in modes:
 name=str(report_root/f'uart_{sw:04x}.log')
 run=subprocess.run([vvp,'reports/firmware.vvp',f'+SW={sw:04x}',f'+LOG={name}'],capture_output=True,text=True,timeout=360)
 model=HostGoldenModel();count=0;bad=0;checks=0;check_errors=0
 for line in Path(name).read_text(errors='replace').splitlines():
  if line.startswith('CHECK,'):
   parts=line.split(',');checks+=1;check_errors+=parts[2]!=parts[3]
  if not line.startswith('CSV,'):continue
  try:
   p=line.split(',');i=int(p[1],16);expected,cpop,_=model.step(i,sw,p[3]);count+=1
   bad+=expected!=p[4] or cpop!=int(p[5],16) or i!=count-1
  except (ValueError,IndexError):bad+=1
 print(f'SW={sw:04x} exit={run.returncode} packets={count} FPU/Zbb_mismatches={bad} checks={checks} check_errors={check_errors} complete={"DEMO_COMPLETE" in Path(name).read_text(errors="replace")}',flush=True)

 failures+=run.returncode!=0 or count!=100 or checks!=57 or bad!=0 or check_errors!=0 or "DEMO_COMPLETE" not in Path(name).read_text(errors="replace")
if failures:raise SystemExit(1)
