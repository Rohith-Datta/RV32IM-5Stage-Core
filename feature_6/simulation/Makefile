# ============================================================================
# Makefile for Feature 6 (RV32IMF Pipeline with L1 Harvard Caches) Simulation Flow
# Vivado Simulator Flow (xvlog -> xelab -> xsim)
# Standard 50 MHz Core Clock (T_clk = 20 ns)
# Supports:
#   - tb_icache: Unit verification of Direct-Mapped 2 KB L1 I-Cache (9 tests)
#   - tb_feature6_pipeline: Full Harvard pipeline integration with I-Cache & D-Cache
#   - tb_pipeline_base: Base integer ALU program simulation
#   - tb_uart: UART telemetry subsystem simulation
# ============================================================================

INC_DIR   = -i ../modules -i ../modules/pipeline -i ../modules/stages -i ../modules/registers -i ../modules/fpga -i ../modules/uart
XVLOG_FLG = $(INC_DIR) -f filelist.txt
TB_DIR    = ../testbench

XVLOG = xvlog
XELAB = xelab
XSIM  = xsim

.PHONY: all clean sim_icache sim_pipeline sim_base sim_uart

all: sim_icache sim_pipeline sim_base sim_uart

# ----------------------------------------------------------------------------
# 1. I-Cache Unit Testbench (9 Comprehensive Tests)
# ----------------------------------------------------------------------------
sim_icache:
	@echo "=== [1/3] Compiling tb_icache ==="
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_icache.v
	@echo "=== [2/3] Elaborating tb_icache ==="
	$(XELAB) -top tb_icache -snapshot snap_tb_icache -debug typical
	@echo "=== [3/3] Simulating tb_icache ==="
	$(XSIM) snap_tb_icache -R -log sim_icache.log

# ----------------------------------------------------------------------------
# 2. Feature 6 Harvard Pipeline Integration Testbench
# ----------------------------------------------------------------------------
sim_pipeline:
	@echo "=== [1/3] Compiling tb_feature6_pipeline ==="
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_feature6_pipeline.v
	@echo "=== [2/3] Elaborating tb_feature6_pipeline ==="
	$(XELAB) -top tb_feature6_pipeline -snapshot snap_tb_feature6 -debug typical
	@echo "=== [3/3] Simulating tb_feature6_pipeline ==="
	$(XSIM) snap_tb_feature6 -R -log sim_feature6.log

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
