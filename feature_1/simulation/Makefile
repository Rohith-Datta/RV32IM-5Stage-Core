# ============================================================================
# Makefile for Feature 1 (5-Stage RISC-V Pipeline) Simulation Flow
# Vivado Simulator Flow (xvlog -> xelab -> xsim)
# ============================================================================

INC_DIR   = ../modules
XVLOG_FLG = -i $(INC_DIR) -f filelist.txt

XVLOG = xvlog
XELAB = xelab
XSIM  = xsim

.PHONY: all clean sim_hazard sim_pipeline

all: sim_hazard sim_pipeline

# Target 1: Hazard and Forwarding Unit Testbench
sim_hazard:
	@echo "--- [1/3] Analyzing RTL and tb_hazard.v with xvlog ---"
	$(XVLOG) $(XVLOG_FLG) tb_hazard.v
	@echo "--- [2/3] Elaborating tb_hazard with xelab ---"
	$(XELAB) -top tb_hazard -snapshot sim_hazard_snap -debug typical
	@echo "--- [3/3] Running Simulation with xsim ---"
	$(XSIM) sim_hazard_snap -runall -log sim_hazard.log

# Target 2: Full System Base Pipeline Testbench
sim_pipeline:
	@echo "--- [1/3] Analyzing RTL and tb_pipeline_base.v with xvlog ---"
	$(XVLOG) $(XVLOG_FLG) tb_pipeline_base.v
	@echo "--- [2/3] Elaborating tb_pipeline_base with xelab ---"
	$(XELAB) -top tb_pipeline_base -snapshot sim_pipeline_snap -debug typical
	@echo "--- [3/3] Running Simulation with xsim ---"
	$(XSIM) sim_pipeline_snap -runall -log sim_pipeline.log

clean:
	@rm -rf xsim.dir/ .Xil/
	@rm -f xvlog.log xvlog.pb xelab.log xelab.pb xsim.log xsim.jou xsim.pb
	@rm -f sim_hazard.log sim_pipeline.log pipeline_5stage.vcd
