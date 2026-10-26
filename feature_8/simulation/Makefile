# ============================================================================
# Makefile for Feature 8 (RV32IMF Pipeline with Passive CSRs) Simulation Flow
# Vivado Simulator Flow (xvlog -> xelab -> xsim)
# Standard 50 MHz Core Clock (T_clk = 20 ns)
# Supports:
#   - tb_csr: Unit verification of Passive Performance CSRs (8 assertions)
#   - tb_feature8_pipeline: Full pipeline integration with CSRRS read instructions
# ============================================================================

INC_DIR   = -i ../modules -i ../modules/pipeline -i ../modules/stages -i ../modules/registers -i ../modules/fpga -i ../modules/uart
XVLOG_FLG = $(INC_DIR) -f filelist.txt
TB_DIR    = ../testbench

XVLOG = xvlog
XELAB = xelab
XSIM  = xsim

.PHONY: all clean sim_csr sim_pipeline

all: sim_csr sim_pipeline

# ----------------------------------------------------------------------------
# 1. CSR Unit Testbench (8 Assertions)
# ----------------------------------------------------------------------------
sim_csr:
	@echo "=== [1/3] Compiling tb_csr ==="
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_csr.v
	@echo "=== [2/3] Elaborating tb_csr ==="
	$(XELAB) -top tb_csr -snapshot snap_tb_csr -debug typical
	@echo "=== [3/3] Simulating tb_csr ==="
	$(XSIM) snap_tb_csr -R -log sim_csr.log

# ----------------------------------------------------------------------------
# 2. Feature 8 Pipeline Integration Testbench
# ----------------------------------------------------------------------------
sim_pipeline:
	@echo "=== [1/3] Compiling tb_feature8_pipeline ==="
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_feature8_pipeline.v
	@echo "=== [2/3] Elaborating tb_feature8_pipeline ==="
	$(XELAB) -top tb_feature8_pipeline -snapshot snap_tb_feature8 -debug typical
	@echo "=== [3/3] Simulating tb_feature8_pipeline ==="
	$(XSIM) snap_tb_feature8 -R -log sim_feature8.log

clean:
	rm -rf *.log *.jou *.pb xsim.dir .Xil snap_*
