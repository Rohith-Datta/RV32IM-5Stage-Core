from pathlib import Path
import os,subprocess,sys
root=Path(__file__).resolve().parents[1];os.chdir(root)
(root/'reports').mkdir(exist_ok=True)
iv=os.environ.get('IVERILOG','iverilog');vvp=os.environ.get('VVP','vvp')
flags=['-g2012','-Iintegration/modules/csr']
if os.environ.get('IVERILOG_BASE'):flags+=['-B',os.environ['IVERILOG_BASE']]
core=list(map(str,Path('integration/modules').rglob('*.v')))
for name,files,cwd in [
 ('tb_bp_bypass',['integration/modules/stages/fetch_stage.v','integration/modules/branch/btb_branch_pred.v','tests/tb_bp_bypass.v'],'.'),
 ('tb_integrated_core',core+['integration/testbench/memory_model.v','integration/testbench/tb_integrated_core.v'],'integration/testbench'),
 ('tb_fpu_edges',['integration/modules/arith/fpu_single_core.v','tests/tb_fpu_edges.v'],'.'),
 ('tb_fpu_vectors',['integration/modules/arith/fpu_single_core.v','tests/tb_fpu_vectors.v'],'.'),
 ('tb_pack_equivalence',['integration/modules/arith/fpu_single_core.v','tests/tb_pack_equivalence.v'],'.'),
 ('tb_zbb_observer',core+['tests/tb_zbb_observer.v'],'.'),
 ('tb_alu_audit',['integration/modules/arith/alu_zbb.v','tests/tb_alu_audit.v'],'.'),
 ('tb_integer_edges',list(map(str,Path('integration/modules/arith').glob('*.v')))+['tests/tb_integer_edges.v'],'.'),
 ('tb_cache_bypass_store',['integration/modules/cache/dcache_controller.v','tests/tb_cache_bypass_store.v'],'.'),
 ('tb_cache_toggle',['integration/modules/cache/dcache_controller.v','tests/tb_cache_toggle.v'],'.'),
 ('tb_cache_latency',['integration/modules/cache/dcache_controller.v','integration/modules/cache/icache_controller.v','tests/tb_cache_latency.v'],'.'),
 ('tb_trace_transport',['board/uart_tx.v','board/uart_trace_transport.v','tests/tb_trace_transport.v'],'.'),
 ('tb_uart',['board/uart_tx.v','tests/tb_uart.v'],'.'),
 ('tb_display',['board/nexys_a7_io_controller.v','tests/tb_display.v'],'.')]:
 out=root/'reports'/f'{name}.vvp'
 subprocess.run([iv,*flags,'-s',name,'-o',str(out),*files],check=True)
 with open(root/'reports'/f'{name}.log','w') as log:subprocess.run([vvp,str(out)],cwd=cwd,stdout=log,stderr=subprocess.STDOUT,check=True)
 print(name,'PASS',flush=True)
subprocess.run([sys.executable,'tests/test_dashboard.py'],check=True)
subprocess.run([iv,*flags,'-s','nexys_a7_top','-o',str(root/'reports/board.vvp'),*core,*map(str,Path('board').glob('*.v'))],check=True)
print('Board wrapper elaboration PASS')
subprocess.run([iv,*flags,'-s','tb_firmware','-o','reports/firmware.vvp',*core,'tests/tb_firmware.v'],check=True)
