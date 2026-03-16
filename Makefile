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

# Icarus Verilog
VVP      = sim.vvp
VCD      = dump.vcd

.PHONY: compile sim wave clean lint

compile:
	iverilog -g2012 -o $(VVP) -s $(TOP) $(RTL_SRC)

sim: compile
	vvp $(VVP)

wave: sim
	open -a gtkwave $(VCD) 2>/dev/null || gtkwave $(VCD)

lint:
	verilator --lint-only -Wall --top-module $(TOP) $(RTL_SRC)

clean:
	rm -f $(VVP) $(VCD)
