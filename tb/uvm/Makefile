XRUN          = xrun
IMC           = imc
TOP           = tb_top
RTL_FLIST     = rtl_filelist.f
UVM_VERBOSITY ?= UVM_MEDIUM
TEST          ?= rk4_base_test
REGRESS_DIR   = regress_results

comma := ,

# Auto-discover tests: any file named *_test.sv becomes a test name.
ALL_TESTS     = $(basename $(wildcard *_test.sv))

# make regress tests=rk4_base_test,rk4_projectile_test  (comma-delimited)
# If 'tests' is not set, run all discovered tests.
ifdef tests
  RUN_TESTS = $(subst $(comma), ,$(tests))
else
  RUN_TESTS = $(ALL_TESTS)
endif

# Args shared by RTL and gate-level simulations
COMMON_ARGS = \
    -uvm \
    -uvmhome CDNS-1.2 \
    -timescale 1ns/1ps \
    -access +rwc \
    -coverage all \
    -covoverwrite \
    rk4_if.sv \
    rk4_tb_pkg.sv \
    tb_top.sv \
    -top $(TOP) \
    +UVM_VERBOSITY=$(UVM_VERBOSITY)

# RTL simulation args
BASE_ARGS    = -sv -f $(RTL_FLIST) $(COMMON_ARGS)
SIM_ARGS     = $(BASE_ARGS) +UVM_TESTNAME=$(TEST)

# Gate-level simulation args (no -sv; .v netlist parsed as Verilog)
GATE_FLIST       = gate_filelist.f
GATE_BASE_ARGS   = -f $(GATE_FLIST) $(COMMON_ARGS)
GATE_SIM_ARGS    = $(GATE_BASE_ARGS) +UVM_TESTNAME=$(TEST)
GATE_REGRESS_DIR = regress_gate_results
GATE_COV_WORKDIR = $(CURDIR)/$(GATE_REGRESS_DIR)/cov_work

.PHONY: sim gui uvm-full uvm-full-gui regress cov-report cov-gui \
       sim-gate gui-gate regress-gate cov-report-gate cov-gui-gate clean-gate clean

sim:
	$(XRUN) $(SIM_ARGS)

gui:
	$(XRUN) $(SIM_ARGS) -gui

uvm-full:
	$(MAKE) sim UVM_VERBOSITY=UVM_FULL

uvm-full-gui:
	$(MAKE) gui UVM_VERBOSITY=UVM_FULL

# All tests share one covworkdir; each test is named via -covtest.
# IMC merge operates relative to cov_work/scope/, so we cd into REGRESS_DIR.
COV_WORKDIR = $(CURDIR)/$(REGRESS_DIR)/cov_work

regress:
	@rm -rf $(REGRESS_DIR); mkdir -p $(REGRESS_DIR)
	@pass=0; fail=0; \
	for t in $(RUN_TESTS); do \
		echo ""; \
		echo "======== Running $$t ========"; \
		$(XRUN) $(BASE_ARGS) +UVM_TESTNAME=$$t \
			-covworkdir $(COV_WORKDIR) \
			-covtest $$t \
			-l $(REGRESS_DIR)/$$t.log; \
		xrun_rc=$$?; \
		if [ $$xrun_rc -eq 0 ] && \
		   grep -q 'UVM_ERROR :    0' $(REGRESS_DIR)/$$t.log && \
		   grep -q 'UVM_FATAL :    0' $(REGRESS_DIR)/$$t.log; then \
			echo "-------- $$t PASSED --------"; \
			pass=$$((pass + 1)); \
		else \
			echo "-------- $$t FAILED --------"; \
			fail=$$((fail + 1)); \
		fi; \
	done; \
	echo ""; \
	echo "======== Regression Summary ========"; \
	echo "  PASSED: $$pass / $$(( pass + fail ))"; \
	echo "  FAILED: $$fail / $$(( pass + fail ))"; \
	echo ""; \
	echo "Merging coverage..."; \
	cd $(CURDIR)/$(REGRESS_DIR) && \
		tnames=$$(ls -d cov_work/scope/*/ 2>/dev/null | xargs -n1 basename | tr '\n' ' ') && \
		$(IMC) -execcmd "merge $$tnames -out merged -metrics all -initial_model union_all; exit" && \
		echo "Merged coverage: $(REGRESS_DIR)/cov_work/scope/merged/"; \
	if [ $$fail -ne 0 ]; then exit 1; fi

# Generate a text report from the merged coverage data.
cov-report:
	cd $(CURDIR)/$(REGRESS_DIR) && \
		$(IMC) -execcmd "load -run cov_work/scope/merged; \
			report -metrics all -out $(CURDIR)/$(REGRESS_DIR)/coverage_report.txt; exit"
	@echo "Report written to $(REGRESS_DIR)/coverage_report.txt"

# Open the merged coverage in the IMC GUI.
cov-gui:
	cd $(CURDIR)/$(REGRESS_DIR) && $(IMC) -load cov_work/scope/merged

# ---- Gate-level simulation targets ----

sim-gate:
	$(XRUN) $(GATE_SIM_ARGS)

gui-gate:
	$(XRUN) $(GATE_SIM_ARGS) -gui

regress-gate:
	@rm -rf $(GATE_REGRESS_DIR); mkdir -p $(GATE_REGRESS_DIR)
	@pass=0; fail=0; \
	for t in $(RUN_TESTS); do \
		echo ""; \
		echo "======== [GATE] Running $$t ========"; \
		$(XRUN) $(GATE_BASE_ARGS) +UVM_TESTNAME=$$t \
			-covworkdir $(GATE_COV_WORKDIR) \
			-covtest $$t \
			-l $(GATE_REGRESS_DIR)/$$t.log; \
		xrun_rc=$$?; \
		if [ $$xrun_rc -eq 0 ] && \
		   grep -q 'UVM_ERROR :    0' $(GATE_REGRESS_DIR)/$$t.log && \
		   grep -q 'UVM_FATAL :    0' $(GATE_REGRESS_DIR)/$$t.log; then \
			echo "-------- $$t PASSED --------"; \
			pass=$$((pass + 1)); \
		else \
			echo "-------- $$t FAILED --------"; \
			fail=$$((fail + 1)); \
		fi; \
	done; \
	echo ""; \
	echo "======== Gate-Level Regression Summary ========"; \
	echo "  PASSED: $$pass / $$(( pass + fail ))"; \
	echo "  FAILED: $$fail / $$(( pass + fail ))"; \
	echo ""; \
	echo "Merging coverage..."; \
	cd $(CURDIR)/$(GATE_REGRESS_DIR) && \
		tnames=$$(ls -d cov_work/scope/*/ 2>/dev/null | xargs -n1 basename | tr '\n' ' ') && \
		$(IMC) -execcmd "merge $$tnames -out merged -metrics all -initial_model union_all; exit" && \
		echo "Merged coverage: $(GATE_REGRESS_DIR)/cov_work/scope/merged/"; \
	if [ $$fail -ne 0 ]; then exit 1; fi

cov-report-gate:
	cd $(CURDIR)/$(GATE_REGRESS_DIR) && \
		$(IMC) -execcmd "load -run cov_work/scope/merged; \
			report -metrics all -out $(CURDIR)/$(GATE_REGRESS_DIR)/coverage_report.txt; exit"
	@echo "Report written to $(GATE_REGRESS_DIR)/coverage_report.txt"

cov-gui-gate:
	cd $(CURDIR)/$(GATE_REGRESS_DIR) && $(IMC) -load cov_work/scope/merged

clean-gate:
	rm -rf $(GATE_REGRESS_DIR)

clean:
	rm -rf xcelium.d INCA_libs xrun.log xrun.history waves.shm $(REGRESS_DIR) $(GATE_REGRESS_DIR)
