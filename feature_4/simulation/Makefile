# ============================================================================
# Makefile for Feature 4 (RV32IMF Pipeline with IEEE 754 FPU) Simulation Flow
# Vivado Simulator Flow (xvlog -> xelab -> xsim)
# Standard 50 MHz Core Clock ($T_{clk} = 20\text{ ns}$)
# Supports:
#   - tb_fpu: Unit verification of IEEE 754 FPU (FADD 5c, FSUB 5c, FMUL 4c, FDIV 15c)
#   - tb_feature4_pipeline: Full pipeline integration with FPU stalls & RAW forwarding
#   - tb_pipeline_base: Base C program simulation
#   - tb_uart: UART telemetry subsystem simulation
# ============================================================================

INC_DIR   = -i ../modules -i ../modules/pipeline -i ../modules/stages -i ../modules/registers -i ../modules/fpga -i ../modules/uart
XVLOG_FLG = $(INC_DIR) -f filelist.txt
TB_DIR    = ../testbench

XVLOG = xvlog
XELAB = xelab
XSIM  = xsim

.PHONY: all clean sim_fpu sim_pipeline sim_base sim_uart

all: sim_fpu sim_pipeline sim_uart

# ----------------------------------------------------------------------------
# 1. FPU Unit Testbench (FADD 5c, FSUB 5c, FMUL 4c, FDIV 15c)
# ----------------------------------------------------------------------------
sim_fpu:
	@echo "=== [1/3] Compiling tb_fpu ==="
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_fpu.v
	@echo "=== [2/3] Elaborating tb_fpu ==="
	$(XELAB) -top tb_fpu -snapshot snap_tb_fpu -debug typical
	@echo "=== [3/3] Simulating tb_fpu ==="
	$(XSIM) snap_tb_fpu -R -log sim_fpu.log

# ----------------------------------------------------------------------------
# 2. Feature 4 Pipeline Integration Testbench
# ----------------------------------------------------------------------------
sim_pipeline:
	@echo "=== [1/3] Compiling tb_feature4_pipeline ==="
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_feature4_pipeline.v
	@echo "=== [2/3] Elaborating tb_feature4_pipeline ==="
	$(XELAB) -top tb_feature4_pipeline -snapshot snap_tb_feature4 -debug typical
	@echo "=== [3/3] Simulating tb_feature4_pipeline ==="
	$(XSIM) snap_tb_feature4 -R -log sim_feature4.log

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
