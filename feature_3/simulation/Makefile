# ============================================================================
# Makefile for Feature 3 (RV32IM Pipeline with Hardware Divider) Simulation Flow
# Vivado Simulator Flow (xvlog -> xelab -> xsim)
# Supports:
#   - tb_divider: Unit verification of RV32M divider and corner cases
#   - tb_feature3_pipeline: Full pipeline integration with divider stalls
#   - tb_pipeline_base: Base C program simulation (division.c, etc.)
# ============================================================================

INC_DIR   = -i ../modules -i ../modules/pipeline -i ../modules/stages -i ../modules/registers -i ../modules/fpga -i ../modules/uart
XVLOG_FLG = $(INC_DIR) -f filelist.txt
SNAPSHOT  = sim_pipeline_snap
C_TESTS   = ../../c_tests
TB_DIR    = ../testbench

XVLOG = xvlog
XELAB = xelab
XSIM  = xsim

.PHONY: all clean sim_divider sim_pipeline sim_base sim_uart division

all: sim_divider sim_pipeline sim_uart

# ----------------------------------------------------------------------------
# 0. UART Subsystem Testbench
# ----------------------------------------------------------------------------
sim_uart:
	@echo "=== [1/3] Compiling tb_uart.v ==="
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_uart.v
	@echo "=== [2/3] Elaborating tb_uart ==="
	$(XELAB) -top tb_uart -snapshot sim_uart_snap -debug typical
	@echo "=== [3/3] Simulating tb_uart ==="
	$(XSIM) sim_uart_snap -runall -log sim_uart.log

# ----------------------------------------------------------------------------
# 1. Divider Unit Testbench
# ----------------------------------------------------------------------------
sim_divider:
	@echo "=== [1/3] Compiling tb_divider ==="
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_divider.v
	@echo "=== [2/3] Elaborating tb_divider ==="
	$(XELAB) -top tb_divider -snapshot snap_tb_divider -debug typical
	@echo "=== [3/3] Simulating tb_divider ==="
	$(XSIM) snap_tb_divider -runall -log sim_divider.log

# ----------------------------------------------------------------------------
# 2. Feature 3 Pipeline Integration Testbench
# ----------------------------------------------------------------------------
sim_pipeline:
	@echo "=== [1/3] Compiling tb_feature3_pipeline ==="
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_feature3_pipeline.v
	@echo "=== [2/3] Elaborating tb_feature3_pipeline ==="
	$(XELAB) -top tb_feature3_pipeline -snapshot snap_tb_feature3 -debug typical
	@echo "=== [3/3] Simulating tb_feature3_pipeline ==="
	$(XSIM) snap_tb_feature3 -runall -log sim_feature3.log

# ----------------------------------------------------------------------------
# 3. Base Pipeline Full-System Testbench
# ----------------------------------------------------------------------------
sim_base:
	@echo "=== [1/3] Compiling tb_pipeline_base.v ==="
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_pipeline_base.v
	@echo "=== [2/3] Elaborating tb_pipeline_base ==="
	$(XELAB) -top tb_pipeline_base -snapshot $(SNAPSHOT) -debug typical
	@echo "=== [3/3] Simulating tb_pipeline_base ==="
	$(XSIM) $(SNAPSHOT) -runall -log sim_pipeline.log

# ----------------------------------------------------------------------------
# 4. Division C Program Test
# ----------------------------------------------------------------------------
division:
	@echo "=== Building and Simulating division (division.c) ==="
	python $(C_TESTS)/build_hex.py division
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_pipeline_base.v
	$(XELAB) -top tb_pipeline_base -snapshot $(SNAPSHOT) -debug typical
	$(XSIM) $(SNAPSHOT) -runall

clean:
	@rm -rf xsim.dir/ .Xil/
	@rm -f xvlog.log xvlog.pb xelab.log xelab.pb xsim.log xsim.jou xsim.pb
	@rm -f sim_divider.log sim_feature3.log sim_pipeline.log pipeline_5stage.vcd
