# ============================================================================
# Makefile for Feature 1 (5-Stage RISC-V Pipeline) Simulation Flow
# Vivado Simulator Flow (xvlog -> xelab -> xsim)
# Supports C test compilation (addition, fibonacci, sort, negative, xor)
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

.PHONY: all clean sim_hazard sim_feature1 sim_pipeline sim_uart addition fibonacci sort negative xor

all: sim_feature1 sim_pipeline sim_uart

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
# Unit Hazard Testbench
# ----------------------------------------------------------------------------
sim_hazard:
	@echo "=== [1/3] Compiling tb_hazard.v ==="
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_hazard.v
	@echo "=== [2/3] Elaborating tb_hazard ==="
	$(XELAB) -top tb_hazard -snapshot sim_hazard_snap -debug typical
	@echo "=== [3/3] Simulating tb_hazard ==="
	$(XSIM) sim_hazard_snap -runall -log sim_hazard.log

# ----------------------------------------------------------------------------
# Feature 1 Pipeline Integration Testbench
# ----------------------------------------------------------------------------
sim_feature1:
	@echo "=== [1/3] Compiling tb_feature1_pipeline.v ==="
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_feature1_pipeline.v
	@echo "=== [2/3] Elaborating tb_feature1_pipeline ==="
	$(XELAB) -top tb_feature1_pipeline -snapshot sim_feature1_snap -debug typical
	@echo "=== [3/3] Simulating tb_feature1_pipeline ==="
	$(XSIM) sim_feature1_snap -runall -log sim_feature1.log

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

# ----------------------------------------------------------------------------
# Direct C Programs: Compile C -> Generate Hex -> Run Vivado Simulation
# ----------------------------------------------------------------------------
addition:
	@echo "=== Building and Simulating addition (code_addition.c) ==="
	python $(C_TESTS)/build_hex.py addition
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_pipeline_base.v
	$(XELAB) -top $(TOP_MOD) -snapshot $(SNAPSHOT) -debug typical
	$(XSIM) $(SNAPSHOT) -runall

fibonacci:
	@echo "=== Building and Simulating fibonacci (code_fibonacci.c) ==="
	python $(C_TESTS)/build_hex.py fibonacci
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_pipeline_base.v
	$(XELAB) -top $(TOP_MOD) -snapshot $(SNAPSHOT) -debug typical
	$(XSIM) $(SNAPSHOT) -runall

sort:
	@echo "=== Building and Simulating sort (code_sort.c) ==="
	python $(C_TESTS)/build_hex.py sort
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_pipeline_base.v
	$(XELAB) -top $(TOP_MOD) -snapshot $(SNAPSHOT) -debug typical
	$(XSIM) $(SNAPSHOT) -runall

negative:
	@echo "=== Building and Simulating negative (code_negative.c) ==="
	python $(C_TESTS)/build_hex.py negative
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_pipeline_base.v
	$(XELAB) -top $(TOP_MOD) -snapshot $(SNAPSHOT) -debug typical
	$(XSIM) $(SNAPSHOT) -runall

xor:
	@echo "=== Building and Simulating xor (code_xor.c) ==="
	python $(C_TESTS)/build_hex.py xor
	$(XVLOG) $(XVLOG_FLG) $(TB_DIR)/tb_pipeline_base.v
	$(XELAB) -top $(TOP_MOD) -snapshot $(SNAPSHOT) -debug typical
	$(XSIM) $(SNAPSHOT) -runall

clean:
	@rm -rf xsim.dir/ .Xil/
	@rm -f xvlog.log xvlog.pb xelab.log xelab.pb xsim.log xsim.jou xsim.pb
	@rm -f sim_hazard.log sim_pipeline.log pipeline_5stage.vcd
