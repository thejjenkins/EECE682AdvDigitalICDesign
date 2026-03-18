XRUN     = xrun

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

.PHONY: compile sim gui lint uvm uvm-gui uvm-clean clean clean-all

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

uvm-full:
	$(MAKE) -C tb/uvm uvm-full

uvm-full-gui:
	$(MAKE) -C tb/uvm uvm-full-gui

uvm-clean:
	$(MAKE) -C tb/uvm clean

clean:
	rm -rf xcelium.d INCA_libs xrun.log xrun.history waves.shm

clean-all: clean uvm-clean
