XRUN     = xrun

# Remote project paths on Cadence server
PROJ_ROOT    = /projects/howard/2026/team_ode
SYNTH_DIR    = $(PROJ_ROOT)/synthesis
TEST_DIR     = $(SYNTH_DIR)/test_scripts
EQUIV_DIR    = $(PROJ_ROOT)/equivalence

RTL_DIR  = rtl
RTL_SRC  = $(RTL_DIR)/rk4_projectile_top.sv \
           $(RTL_DIR)/rk4_regfile.sv        \
           $(RTL_DIR)/rk4_alu.sv            \
           $(RTL_DIR)/rk4_f_engine.sv       \
           $(RTL_DIR)/rk4_control_fsm.sv    \
           $(RTL_DIR)/rk4_uart_protocol.sv  \
           $(RTL_DIR)/uart_rx.sv            \
           $(RTL_DIR)/uart_tx.sv            \
           $(RTL_DIR)/jtag_tap.sv           \
           $(RTL_DIR)/inverter.sv

TOP      = rk4_projectile_top

XRUN_ARGS = -sv -timescale 1ns/1ps -access +rwc

.PHONY: compile sim gui lint sim-chip \
       uvm uvm-gui uvm-regress uvm-cov uvm-cov-gui uvm-full uvm-full-gui uvm-clean \
       uvm-gate uvm-gate-gui uvm-gate-regress uvm-gate-cov uvm-gate-cov-gui uvm-gate-clean \
       synth synth-dft synth-chip atpg lec lec-dft \
       innovus-setup check-setup \
       clean clean-all

compile:
	$(XRUN) -compile $(XRUN_ARGS) -top $(TOP) $(RTL_SRC)

sim:
	$(XRUN) $(XRUN_ARGS) -top $(TOP) $(RTL_SRC)

gui:
	$(XRUN) $(XRUN_ARGS) -top $(TOP) $(RTL_SRC) -gui

lint:
	$(XRUN) -lint $(XRUN_ARGS) -top $(TOP) $(RTL_SRC)

# --- Chip-level sim (with IO pads + standard cells) ---
sim-chip:
	$(XRUN) -timescale 1ns/1ps $(RTL_DIR)/chip.v $(TSMC_PDK_V)/tcb018gbwp7t.v $(IO_PIN)/tpd018nv.v

sim-chip-final:
	$(XRUN) -timescale 1ns/1ps $(RTL_DIR)/final_chip.v $(TSMC_PDK_V)/tcb018gbwp7t.v $(IO_PIN)/tpd018nv.v

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
	cd $(SYNTH_DIR) && genus -f rk4_script.tcl -log debug.log

synth-dft:
	cd $(SYNTH_DIR) && genus -f rk4_dft_script.tcl -log dft_debug.log

synth-chip:
	cd $(SYNTH_DIR) && genus -f chip_script_adv.tcl

# --- ATPG (Modus) ---
atpg:
	cd $(TEST_DIR) && modus -f modus.tcl

# --- Equivalence checking (Conformal LEC) ---
lec:
	cd $(EQUIV_DIR) && lec -Dofile rk4_top.do -NOGui -XL -Color

lec-dft:
	cd $(EQUIV_DIR) && lec -Dofile rk4_top_dft.do -NOGui -XL -Color

# --- Innovus P&R setup ---
PHYS_DIR     = $(PROJ_ROOT)/physical_synth

innovus-setup:
	mkdir -p $(PHYS_DIR)
	cp $(SYNTH_DIR)/outputs/chip_netlist.v $(PHYS_DIR)/
	cp $(SYNTH_DIR)/outputs/chip_sdc.sdc $(PHYS_DIR)/
	cp /projects/howard/innovus/chip_timing.tcl $(PHYS_DIR)/
	cp /projects/howard/innovus/power.tcl $(PHYS_DIR)/

# --- Environment check ---
check-setup:
	@echo "TSMC_PDK_V = $(TSMC_PDK_V)"
	@echo "IO_PIN     = $(IO_PIN)"
	@which innovus
	@which xrun

clean:
	rm -rf xcelium.d INCA_libs xrun.log xrun.history waves.shm

clean-all: clean uvm-clean uvm-gate-clean
