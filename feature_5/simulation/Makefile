# ============================================================================
# Makefile for Feature 5 (RV32IMF Pipeline with L1 D-Cache) Simulation Flow
# Vivado Simulator Flow (xvlog -> xelab -> xsim)
# Standard 50 MHz Core Clock (T_clk = 20 ns)
# Supports:
#   - tb_dcache: Unit verification of Direct-Mapped 2 KB L1 D-Cache (18 assertions)
#   - tb_feature5_pipeline: Full pipeline integration with D-Cache miss/hit & write-through
#   - tb_pipeline_base: Base C program simulation
#   - tb_uart: UART telemetry subsystem simulation
# ============================================================================

INC_DIR   = -i ../modules -i ../modules/pipeline -i ../modules/stages -i ../modules/registers -i ../modules/fpga -i ../modules/uart
XVLOG_FLG = $(INC_DIR) -f filelist.txt
TB_DIR    = ../testbench

XVLOG = xvlog
XELAB = xelab
XSIM  = xsim

.PHONY: all clean sim_dcache sim_pipeline sim_base sim_uart

all: sim_dcache sim_pipeline sim_uart

# ----------------------------------------------------------------------------
# 1. D-Cache Unit Testbench (18 Assertions)
# ----------------------------------------------------------------------------
sim_dcache:
	@echo "=== [1/3] Compiling tb_dcache ==="
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_dcache.v
	@echo "=== [2/3] Elaborating tb_dcache ==="
	$(XELAB) -top tb_dcache -snapshot snap_tb_dcache -debug typical
	@echo "=== [3/3] Simulating tb_dcache ==="
	$(XSIM) snap_tb_dcache -R -log sim_dcache.log

# ----------------------------------------------------------------------------
# 2. Feature 5 Pipeline Integration Testbench
# ----------------------------------------------------------------------------
sim_pipeline:
	@echo "=== [1/3] Compiling tb_feature5_pipeline ==="
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_feature5_pipeline.v
	@echo "=== [2/3] Elaborating tb_feature5_pipeline ==="
	$(XELAB) -top tb_feature5_pipeline -snapshot snap_tb_feature5 -debug typical
	@echo "=== [3/3] Simulating tb_feature5_pipeline ==="
	$(XSIM) snap_tb_feature5 -R -log sim_feature5.log

# ----------------------------------------------------------------------------
# 3. Base Pipeline Full-System Testbench
# ----------------------------------------------------------------------------
sim_base:
	@echo "=== [1/3] Compiling tb_pipeline_base ==="
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_pipeline_base.v
	@echo "=== [2/3] Elaborating tb_pipeline_base ==="
	$(XELAB) -top tb_pipeline_base -snapshot snap_tb_base -debug typical
	@echo "=== [3/3] Simulating tb_pipeline_base ==="
	$(XSIM) snap_tb_base -R -log sim_base.log

# ----------------------------------------------------------------------------
# 4. UART Subsystem Testbench
# ----------------------------------------------------------------------------
sim_uart:
	@echo "=== [1/3] Compiling tb_uart.v ==="
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_uart.v
	@echo "=== [2/3] Elaborating tb_uart ==="
	$(XELAB) -top tb_uart -snapshot snap_tb_uart -debug typical
	@echo "=== [3/3] Simulating tb_uart ==="
	$(XSIM) snap_tb_uart -R -log sim_uart.log

clean:
	rm -rf *.log *.jou *.pb *.wdb xsim.dir .Xil
