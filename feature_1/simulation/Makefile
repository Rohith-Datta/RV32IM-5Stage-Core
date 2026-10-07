# ============================================================================
# Makefile for Feature 1 (5-Stage RISC-V Pipeline) Simulation Flow
# Vivado Simulator Flow (xvlog -> xelab -> xsim)
# Supports C test compilation (addition, fibonacci, sort, negative, xor)
# ============================================================================

INC_DIR   = ../modules
XVLOG_FLG = -i $(INC_DIR) -f filelist.txt
TOP_MOD   = tb_pipeline_base
SNAPSHOT  = sim_pipeline_snap
C_TESTS   = ../../c_tests

XVLOG = xvlog
XELAB = xelab
XSIM  = xsim

.PHONY: all clean sim_hazard sim_pipeline addition fibonacci sort negative xor

all: sim_hazard sim_pipeline

# ----------------------------------------------------------------------------
# Unit Hazard Testbench
# ----------------------------------------------------------------------------
sim_hazard:
	@echo "=== [1/3] Compiling tb_hazard.v ==="
	$(XVLOG) $(XVLOG_FLG) tb_hazard.v
	@echo "=== [2/3] Elaborating tb_hazard ==="
	$(XELAB) -top tb_hazard -snapshot sim_hazard_snap -debug typical
	@echo "=== [3/3] Simulating tb_hazard ==="
	$(XSIM) sim_hazard_snap -runall -log sim_hazard.log

# ----------------------------------------------------------------------------
# Base Pipeline Full-System Testbench
# ----------------------------------------------------------------------------
sim_pipeline:
	@echo "=== [1/3] Compiling tb_pipeline_base.v ==="
	$(XVLOG) $(XVLOG_FLG) tb_pipeline_base.v
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
	$(XVLOG) $(XVLOG_FLG) tb_pipeline_base.v
	$(XELAB) -top $(TOP_MOD) -snapshot $(SNAPSHOT) -debug typical
	$(XSIM) $(SNAPSHOT) -runall

fibonacci:
	@echo "=== Building and Simulating fibonacci (code_fibonacci.c) ==="
	python $(C_TESTS)/build_hex.py fibonacci
	$(XVLOG) $(XVLOG_FLG) tb_pipeline_base.v
	$(XELAB) -top $(TOP_MOD) -snapshot $(SNAPSHOT) -debug typical
	$(XSIM) $(SNAPSHOT) -runall

sort:
	@echo "=== Building and Simulating sort (code_sort.c) ==="
	python $(C_TESTS)/build_hex.py sort
	$(XVLOG) $(XVLOG_FLG) tb_pipeline_base.v
	$(XELAB) -top $(TOP_MOD) -snapshot $(SNAPSHOT) -debug typical
	$(XSIM) $(SNAPSHOT) -runall

negative:
	@echo "=== Building and Simulating negative (code_negative.c) ==="
	python $(C_TESTS)/build_hex.py negative
	$(XVLOG) $(XVLOG_FLG) tb_pipeline_base.v
	$(XELAB) -top $(TOP_MOD) -snapshot $(SNAPSHOT) -debug typical
	$(XSIM) $(SNAPSHOT) -runall

xor:
	@echo "=== Building and Simulating xor (code_xor.c) ==="
	python $(C_TESTS)/build_hex.py xor
	$(XVLOG) $(XVLOG_FLG) tb_pipeline_base.v
	$(XELAB) -top $(TOP_MOD) -snapshot $(SNAPSHOT) -debug typical
	$(XSIM) $(SNAPSHOT) -runall

clean:
	@rm -rf xsim.dir/ .Xil/
	@rm -f xvlog.log xvlog.pb xelab.log xelab.pb xsim.log xsim.jou xsim.pb
	@rm -f sim_hazard.log sim_pipeline.log pipeline_5stage.vcd
