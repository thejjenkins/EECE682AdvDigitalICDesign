XRUN     = xrun

# Remote project paths on Cadence server
PROJ_ROOT    = /projects/howard/2026/team_ode
SYNTH_DIR    = $(PROJ_ROOT)/synthesis
TEST_DIR     = $(SYNTH_DIR)/test_scripts
EQUIV_DIR    = $(PROJ_ROOT)/equivalence

RTL_DIR  = rtl
RTL_SRC  = $(RTL_DIR)/rk4_top.sv           \
           $(RTL_DIR)/rk4_clk_gen.sv        \
           $(RTL_DIR)/rk4_ring_osc.sv       \
           $(RTL_DIR)/rk4_clock_divider.sv  \
           $(RTL_DIR)/rk4_projectile_top.sv \
           $(RTL_DIR)/rk4_regfile.sv        \
           $(RTL_DIR)/rk4_alu.sv            \
           $(RTL_DIR)/rk4_f_engine.sv       \
           $(RTL_DIR)/rk4_control_fsm.sv    \
           $(RTL_DIR)/rk4_uart_protocol.sv  \
           $(RTL_DIR)/uart_rx.sv            \
           $(RTL_DIR)/uart_tx.sv

TOP      = rk4_top

XRUN_ARGS = -sv -timescale 1ns/1ps -access +rwc

.PHONY: compile sim gui lint \
       uvm uvm-gui uvm-regress uvm-cov uvm-cov-gui uvm-full uvm-full-gui uvm-clean \
       uvm-gate uvm-gate-gui uvm-gate-regress uvm-gate-cov uvm-gate-cov-gui uvm-gate-clean \
       synth synth-dft atpg lec lec-dft \
       clean clean-all

compile:
	$(XRUN) -compile $(XRUN_ARGS) -top $(TOP) $(RTL_SRC)

sim:
	$(XRUN) $(XRUN_ARGS) -top $(TOP) $(RTL_SRC)

gui:
	$(XRUN) $(XRUN_ARGS) -top $(TOP) $(RTL_SRC) -gui

lint:
	$(XRUN) -lint $(XRUN_ARGS) -top $(TOP) $(RTL_SRC)

# --- UVM testbench ---
uvm:
	$(MAKE) -C tb/uvm sim

uvm-gui:
	$(MAKE) -C tb/uvm gui

uvm-regress:
	$(MAKE) -C tb/uvm regress $(if $(tests),tests=$(tests))

uvm-cov:
	$(MAKE) -C tb/uvm cov-report

uvm-cov-gui:
	$(MAKE) -C tb/uvm cov-gui

uvm-full:
	$(MAKE) -C tb/uvm uvm-full

uvm-full-gui:
	$(MAKE) -C tb/uvm uvm-full-gui

uvm-clean:
	$(MAKE) -C tb/uvm clean

# --- UVM gate-level simulation ---
uvm-gate:
	$(MAKE) -C tb/uvm sim-gate

uvm-gate-gui:
	$(MAKE) -C tb/uvm gui-gate

uvm-gate-regress:
	$(MAKE) -C tb/uvm regress-gate $(if $(tests),tests=$(tests))

uvm-gate-cov:
	$(MAKE) -C tb/uvm cov-report-gate

uvm-gate-cov-gui:
	$(MAKE) -C tb/uvm cov-gui-gate

uvm-gate-clean:
	$(MAKE) -C tb/uvm clean-gate

# --- Synthesis (Genus) ---
synth:
	cd $(SYNTH_DIR) && genus -f rk4_script.tcl

synth-dft:
	cd $(SYNTH_DIR) && genus -f rk4_dft_script.tcl

# --- ATPG (Modus) ---
atpg:
	cd $(TEST_DIR) && modus -f modus.tcl

# --- Equivalence checking (Conformal LEC) ---
lec:
	cd $(EQUIV_DIR) && lec -Dofile rk4_top.do -NOGui -XL -Color

lec-dft:
	cd $(EQUIV_DIR) && lec -Dofile rk4_top_dft.do -NOGui -XL -Color

clean:
	rm -rf xcelium.d INCA_libs xrun.log xrun.history waves.shm

clean-all: clean uvm-clean uvm-gate-clean
