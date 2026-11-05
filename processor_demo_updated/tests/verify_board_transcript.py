from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from test_dashboard import DashboardTest
app=DashboardTest().model()
for line in Path('reports/board_full_uart.log').read_text().splitlines():app._handle_uart_line(line)
assert len(app.received)==100 and app.check_count==57 and app.failures==0
print(f'BOARD HOST PASS: packets={len(app.received)} checks={app.check_count} failures={app.failures}; cache rates={app.last_cache_rates}')
