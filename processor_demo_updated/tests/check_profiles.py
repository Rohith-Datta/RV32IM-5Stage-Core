from pathlib import Path
import sys
expected={'REV8_WINDOW':1,'DCACHE_MISS_PENALTY':9,'DCACHE_HIT_SERVICE':1,'FMUL_WINDOW':4,'FDIV_WINDOW':15,'DIV_WINDOW':32}
p=Path(sys.argv[1] if len(sys.argv)>1 else 'reports/final/uart_6032.log')
found={parts[1]:int(parts[2],16) for line in p.read_text().splitlines() if line.startswith('PROFILE,') for parts in [line.split(',')]}
for name,value in expected.items():
 if found.get(name)!=value:raise SystemExit(f'{name}: got {found.get(name)}, expected {value}')
 print(f'{name}={value} PASS')
