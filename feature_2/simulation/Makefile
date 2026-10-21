# ============================================================================
# Makefile for Feature 2 (RV32IM Pipeline with Hardware Multiplier) Simulation Flow
# Vivado Simulator Flow (xvlog -> xelab -> xsim)
# Supports C test compilation (multiplication, addition, fibonacci, sort, negative, xor)
# ============================================================================

INC_DIR   = -i ../modules -i ../modules/pipeline -i ../modules/stages -i ../modules/registers -i ../modules/fpga -i ../modules/uart
XVLOG_FLG = $(INC_DIR) -f filelist.txt
TOP_MOD   = tb_pipeline_base
SNAPSHOT  = sim_pipeline_snap
C_TESTS   = ../../c_tests
TB_DIR    = ../testbench

XVLOG = xvlog
XELAB = xelab
XSIM  = xsim

.PHONY: all clean sim_pipeline sim_uart multiplication addition fibonacci sort negative xor

all: sim_pipeline sim_uart

# ----------------------------------------------------------------------------
# Unit UART Subsystem Testbench
# ----------------------------------------------------------------------------
sim_uart:
	@echo "=== [1/3] Compiling tb_uart.v ==="
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_uart.v
	@echo "=== [2/3] Elaborating tb_uart ==="
	$(XELAB) -top tb_uart -snapshot sim_uart_snap -debug typical
	@echo "=== [3/3] Simulating tb_uart ==="
	$(XSIM) sim_uart_snap -runall -log sim_uart.log

# ----------------------------------------------------------------------------
# Base Pipeline Full-System Testbench
# ----------------------------------------------------------------------------
sim_pipeline:
	@echo "=== [1/3] Compiling tb_pipeline_base.v ==="
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_pipeline_base.v
	@echo "=== [2/3] Elaborating tb_pipeline_base ==="
	$(XELAB) -top $(TOP_MOD) -snapshot $(SNAPSHOT) -debug typical
	@echo "=== [3/3] Simulating tb_pipeline_base ==="
	$(XSIM) $(SNAPSHOT) -runall -log sim_pipeline.log

multiplication:
	@echo "=== Building and Simulating multiplication (multiplication.c) ==="
	python $(C_TESTS)/build_hex.py multiplication
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_pipeline_base.v
	$(XELAB) -top $(TOP_MOD) -snapshot $(SNAPSHOT) -debug typical
	$(XSIM) $(SNAPSHOT) -runall

addition:
	@echo "=== Building and Simulating addition (addition.c) ==="
	python $(C_TESTS)/build_hex.py addition
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_pipeline_base.v
	$(XELAB) -top $(TOP_MOD) -snapshot $(SNAPSHOT) -debug typical
	$(XSIM) $(SNAPSHOT) -runall

clean:
	@rm -rf xsim.dir/ .Xil/
	@rm -f xvlog.log xvlog.pb xelab.log xelab.pb xsim.log xsim.jou xsim.pb
	@rm -f sim_pipeline.log pipeline_5stage.vcd
