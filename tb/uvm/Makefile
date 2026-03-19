XRUN          = xrun
IMC           = imc
TOP           = tb_top
RTL_FLIST     = rtl_filelist.f
UVM_VERBOSITY ?= UVM_MEDIUM
TEST          ?= rk4_base_test
REGRESS_DIR   = regress_results

# Auto-discover tests: any file named *_test.sv becomes a test name.
ALL_TESTS     = $(basename $(wildcard *_test.sv))

# make regress tests=rk4_base_test,rk4_projectile_test  (comma-delimited)
# If 'tests' is not set, run all discovered tests.
ifdef tests
  RUN_TESTS = $(subst ,, ,$(tests))
else
  RUN_TESTS = $(ALL_TESTS)
endif

# Shared compile/sim flags (no test name or coverage directory)
BASE_ARGS = \
    -uvm \
    -uvmhome CDNS-1.2 \
    -sv \
    -timescale 1ns/1ps \
    -access +rwc \
    -coverage all \
    -f $(RTL_FLIST) \
    rk4_if.sv \
    rk4_tb_pkg.sv \
    tb_top.sv \
    -top $(TOP) \
    +UVM_VERBOSITY=$(UVM_VERBOSITY)

# Single-test args (used by sim/gui targets)
SIM_ARGS = $(BASE_ARGS) +UVM_TESTNAME=$(TEST)

.PHONY: sim gui uvm-full uvm-full-gui regress cov-report clean

sim:
	$(XRUN) $(SIM_ARGS)

gui:
	$(XRUN) $(SIM_ARGS) -gui

uvm-full:
	$(MAKE) sim UVM_VERBOSITY=UVM_FULL

uvm-full-gui:
	$(MAKE) gui UVM_VERBOSITY=UVM_FULL

# Run every test, each into its own coverage directory, then merge.
regress:
	@rm -rf $(REGRESS_DIR); mkdir -p $(REGRESS_DIR)
	@pass=0; fail=0; \
	for t in $(RUN_TESTS); do \
		echo ""; \
		echo "======== Running $$t ========"; \
		if $(XRUN) $(BASE_ARGS) +UVM_TESTNAME=$$t \
			-covworkdir $(REGRESS_DIR)/$$t/cov_work \
			-l $(REGRESS_DIR)/$$t.log; then \
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
	$(IMC) -execcmd " \
		merge $(REGRESS_DIR)/*/cov_work/scope/* -out $(REGRESS_DIR)/merged; \
		load $(REGRESS_DIR)/merged; \
		report -metrics all -out $(REGRESS_DIR)/coverage_report.txt; \
		exit"; \
	echo "Coverage report: $(REGRESS_DIR)/coverage_report.txt"; \
	if [ $$fail -ne 0 ]; then exit 1; fi

# Re-generate a text report from previously merged data.
cov-report:
	$(IMC) -load $(REGRESS_DIR)/merged -execcmd " \
		report -metrics all -out $(REGRESS_DIR)/coverage_report.txt; exit"
	@echo "Report written to $(REGRESS_DIR)/coverage_report.txt"

# Open the merged coverage in the IMC GUI.
cov-gui:
	$(IMC) -load $(REGRESS_DIR)/merged

clean:
	rm -rf xcelium.d INCA_libs xrun.log xrun.history waves.shm $(REGRESS_DIR)
