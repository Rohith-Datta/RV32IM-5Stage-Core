# ============================================================================
# Makefile for Feature 7 (RV32IMF Pipeline with 32-Entry BTB) Simulation Flow
# Vivado Simulator Flow (xvlog -> xelab -> xsim)
# Standard 50 MHz Core Clock (T_clk = 20 ns)
# Supports:
#   - tb_btb: Unit verification of Static 32-Entry BTB (8 assertions)
#   - tb_feature7_pipeline: Full pipeline integration with BTB 0-bubble acceleration
# ============================================================================

INC_DIR   = -i ../modules -i ../modules/pipeline -i ../modules/stages -i ../modules/registers -i ../modules/fpga -i ../modules/uart
XVLOG_FLG = $(INC_DIR) -f filelist.txt
TB_DIR    = ../testbench

XVLOG = xvlog
XELAB = xelab
XSIM  = xsim

.PHONY: all clean sim_btb sim_pipeline

all: sim_btb sim_pipeline

# ----------------------------------------------------------------------------
# 1. BTB Unit Testbench (8 Assertions)
# ----------------------------------------------------------------------------
sim_btb:
	@echo "=== [1/3] Compiling tb_btb ==="
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_btb.v
	@echo "=== [2/3] Elaborating tb_btb ==="
	$(XELAB) -top tb_btb -snapshot snap_tb_btb -debug typical
	@echo "=== [3/3] Simulating tb_btb ==="
	$(XSIM) snap_tb_btb -R -log sim_btb.log

# ----------------------------------------------------------------------------
# 2. Feature 7 Pipeline Integration Testbench
# ----------------------------------------------------------------------------
sim_pipeline:
	@echo "=== [1/3] Compiling tb_feature7_pipeline ==="
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_feature7_pipeline.v
	@echo "=== [2/3] Elaborating tb_feature7_pipeline ==="
	$(XELAB) -top tb_feature7_pipeline -snapshot snap_tb_feature7 -debug typical
	@echo "=== [3/3] Simulating tb_feature7_pipeline ==="
	$(XSIM) snap_tb_feature7 -R -log sim_feature7.log

clean:
	rm -rf *.log *.jou *.pb xsim.dir .Xil snap_*
