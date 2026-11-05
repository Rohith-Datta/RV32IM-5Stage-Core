import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from dashboard import RISCVTelemetryDashboard,HostGoldenModel,SELFTEST_EXPECTED,expected_input_bits,expected_integer_result
class Widget:
 def __init__(self):self.value=None
 def configure(self,**kw): self.value=kw
 def set_data(self,*args):pass
 def set_value(self,x): self.value=x
 def relim(self):pass
 def autoscale_view(self):pass
 def draw_idle(self):pass
class DashboardTest(unittest.TestCase):
 def model(self):
  a=object.__new__(RISCVTelemetryDashboard)
  for n in ['lbl_status','lbl_mode','lbl_fpga_vs_host','line_raw','line_filt','ax','canvas','gauge_ipc','gauge_icache','gauge_dcache','gauge_stalls']:setattr(a,n,Widget())
  a.check_count=0;a.hardware_status=None;a.last_cache_rates=(None,None);a.mirror_labels={};a.received=set();a.failures=0;a.last_iter=-1;a.source='RTL';a.golden_model=HostGoldenModel()
  a.x_iters=[];a.y_raw=[];a.y_filt=[];a.prev_cycles=a.prev_instret=a.prev_dmiss=0;a.logs=[]
  a._append_terminal=lambda *x:a.logs.append(x)
  return a
 def packet(self,i=0,result='3FE00000'):
  return f'CSV,{i:08X},00002032,3FE00000,{result},00000009,0000000E,00000100,00000080,00000001,00000005,12345678'
 def test_exact(self):
  a=self.model();a._handle_uart_line(self.packet());self.assertEqual(a.failures,0);self.assertIsNone(a.gauge_icache.value)
 def test_mismatch(self):
  a=self.model();a._handle_uart_line(self.packet(result='40000000'));self.assertEqual(a.failures,1)
 def test_duplicate(self):
  a=self.model();a._handle_uart_line(self.packet());a._handle_uart_line(self.packet());self.assertEqual(a.failures,1)
 def test_malformed(self):
  a=self.model();a._handle_uart_line('CSV,garbage');self.assertEqual(a.failures,1)
 def test_incomplete(self):
  a=self.model();a._handle_uart_line('DEMO_COMPLETE');self.assertIn('0/100',a.lbl_status.value['text'])
 def test_diagnostic_independent(self):
  expected,_,_=HostGoldenModel().step(0,0xe003,'12345678');self.assertEqual(expected,'7FC00000')
 def test_selftest_failure(self):
  a=self.model();a._handle_uart_line('CHECK,MUL,00000001,00000002');self.assertEqual(a.failures,1);self.assertEqual(a.check_count,1)
 def test_hardware_metadata(self):
  a=self.model();a._handle_uart_line('[CC=0000000001] PC: 0x00000000 | INST: 0x00B50553 | WB: f10 <= 0x3F800000 [WE=1] [VALID=1] | SW=2032 LED=8200 IFPC=00000004 I_HIT=00000009 I_MISS=00000001 D_HIT=00000003 D_MISS=00000001')
  self.assertEqual(a.gauge_icache.value,90)
  self.assertEqual(a.gauge_dcache.value,75)
  self.assertIn('fadd.s fa0, fa0, fa1',a.logs[-1][0])
  self.assertNotIn('WB:',a.logs[-1][0])
 def test_trace_window_contiguous(self):
  a=self.model()
  for cc in range(256):a._handle_uart_line(f'[CC={cc:010d}] PC: 0x00000000 | INST: 0x00000013 | [VALID=1] EVENT: 0000')
  self.assertIn('256/256',a.logs[-1][0]);self.assertFalse(a.__dict__.get('trace_gap',False))
 def test_trace_window_missing_cycle(self):
  a=self.model()
  for cc in [0,2,256]:a._handle_uart_line(f'[CC={cc:010d}] PC: 0x00000000 | INST: 0x00000013 | [VALID=0] EVENT: 9000')
  self.assertTrue(a.trace_gap);self.assertIn('Incomplete',a.logs[-1][0]);self.assertIn('bubble',a.logs[-2][0])
 def test_profile_reference(self):
  a=self.model();a.hardware_status=(0x6032,0,0)
  a._handle_uart_line('PROFILE,FMUL_WINDOW,00000004');self.assertIn('PASS',a.logs[-1][0])
  a._handle_uart_line('PROFILE,FDIV_WINDOW,00000001');self.assertEqual(a.failures,1)
 def test_packet_keeps_proof(self):
  a=self.model();a._handle_uart_line(self.packet())
  self.assertTrue(any('[FPU #00]' in x[0] for x in a.logs));self.assertTrue(any('CPOP FPGA=9 HOST=9' in x[0] for x in a.logs))
 def test_missing_checks_not_green(self):
  a=self.model();a.received=set(range(100));a._handle_uart_line('DEMO_COMPLETE')
  self.assertEqual(a.lbl_status.value['fg_color'],'#8B2635')
 def test_sender_cannot_invent_expected(self):
  a=self.model();a._handle_uart_line('CHECK,MUL,00000001,00000001');self.assertEqual(a.failures,1)
 def test_duplicate_check_rejected(self):
  a=self.model()
  for _ in range(2):a._handle_uart_line('CHECK,MUL,000000C8,000000C8')
  self.assertEqual(a.failures,1);self.assertEqual(a.check_count,1)
 def test_unknown_check_rejected(self):
  a=self.model();a._handle_uart_line('CHECK,UNKNOWN,00000000,00000000');self.assertEqual(a.failures,1)
 def test_full_check_coverage(self):
  a=self.model()
  for name,ref in SELFTEST_EXPECTED.items():
   value=ref[0] if isinstance(ref,tuple) else ref
   a._handle_uart_line(f'CHECK,{name},{value:08X},{value:08X}')
  self.assertEqual(a.check_count,57);self.assertEqual(a.failures,0)
  a.received=set(range(100));a._handle_uart_line('DEMO_COMPLETE')
  self.assertEqual(a.lbl_status.value['fg_color'],'#1B5E20')
 def test_synthetic_never_hardware_green(self):
  a=self.model();a.source='SYNTHETIC preview';a.received=set(range(100));a._handle_uart_line('DEMO_COMPLETE')
  self.assertEqual(a.lbl_status.value['fg_color'],'#805500')
 def test_wrong_division_rejected(self):
  a=self.model();a._handle_uart_line(self.packet().replace('0000000E','DEADBEEF'));self.assertEqual(a.failures,1)
 def test_wrong_raw_rejected_even_if_filter_matches(self):
  a=self.model();a._handle_uart_line(self.packet().replace('3FE00000','3F800000').replace('00000009','00000007'));self.assertEqual(a.failures,1)
 def test_mode_transition_reference(self):
  m=HostGoldenModel();m.step(0,0x2032,'3F800000');m.step(1,0xe006,'80000000')
  self.assertEqual(m.step(2,0x2032,'3F800000')[0],'3E48C8C9')
 def test_stress_integer_oracle(self):
  for i in range(100):
   value=(i+100)//7
   for j in range(16):value^=i+j
   self.assertEqual(expected_integer_result(i,0xa032),value)
 def test_readouts_clear(self):
  a=self.model();a.gauge_ipc.value=1;a._reset_readouts()
  self.assertIsNone(a.gauge_ipc.value);self.assertIn('Awaiting',a.lbl_mode.value['text'])
 def test_float_overflow(self):
  self.assertEqual(HostGoldenModel.float_to_hex(HostGoldenModel.f32(1e50)),'7F800000')
 def test_if_pc_not_wb_pc(self):
  a=self.model();a._handle_uart_line('[CC=0000000000] PC: 0x00000010 | INST: 0x00000013 | [VALID=1] SW=2032 LED=0000 IFPC=00000024 I_HIT=00000000 I_MISS=00000000 D_HIT=00000000 D_MISS=00000000')
  self.assertIn('IF PC 00000024',a.logs[-1][0]);self.assertIn('WB instruction:',a.logs[-1][0])
 def test_profile_summary_at_end(self):
  a=self.model();a._handle_uart_line('PROFILE,FMUL_WINDOW,00000004')
  a.logs.clear();a._handle_uart_line('DEMO_COMPLETE')
  self.assertTrue(any('FMUL_WINDOW: 4 cycles' in x[0] for x in a.logs))
 def test_branch_comparison(self):
  a=self.model();a.received=set(range(100));a.check_results=dict.fromkeys(SELFTEST_EXPECTED,0)
  a._handle_uart_line('RUN_STATS,00002032,00000100,00000080,00000000');a._show_final_summary()
  a._handle_uart_line('RUN_STATS,00002232,00000200,00000080,00000000');a._show_final_summary()
  self.assertIn('bypass extra cycles=+256',a.logs[-1][0])
  self.assertIn('IPC gain=+0.2500',a.logs[-1][0])
 def test_changed_run_excluded(self):
  a=self.model();a.received=set(range(100));a.check_results=dict.fromkeys(SELFTEST_EXPECTED,0)
  a._handle_uart_line('RUN_STATS,00002032,00000100,00000080,00000001');a._show_final_summary()
  self.assertNotIn('bp_runs',a.__dict__)
 def test_bad_stats(self):
  a=self.model();a._handle_uart_line('RUN_STATS,garbage');self.assertEqual(a.failures,1)
if __name__=='__main__':unittest.main()
