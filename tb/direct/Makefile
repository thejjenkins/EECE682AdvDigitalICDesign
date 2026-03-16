# ─────────────────────────────────────────────────────────────
#  Makefile — UART directed testbench (Cadence Xcelium / xrun)
# ─────────────────────────────────────────────────────────────

RTL_DIR  = ../../rtl
TB_FILE  = tb_uart.sv
TOP      = tb_uart

RTL_SRC  = $(RTL_DIR)/uart_rx.sv            \
           $(RTL_DIR)/uart_tx.sv            \
           $(RTL_DIR)/rk4_uart_protocol.sv  \
           $(RTL_DIR)/rk4_alu.sv            \
           $(RTL_DIR)/rk4_regfile.sv        \
           $(RTL_DIR)/rk4_f_engine.sv       \
           $(RTL_DIR)/rk4_control_fsm.sv    \
           $(RTL_DIR)/rk4_projectile_top.sv

XRUN     = xrun
XFLAGS   = -sv -64bit -timescale 1ns/1ps -top $(TOP)

.PHONY: sim waves clean

sim:
	$(XRUN) $(XFLAGS) $(RTL_SRC) $(TB_FILE) -l sim.log

waves:
	$(XRUN) $(XFLAGS) -access +rwc -input "database -open waves.shm -default; probe -create $(TOP) -all -depth all; run; exit" \
		$(RTL_SRC) $(TB_FILE) -l sim_waves.log

clean:
	rm -rf xcelium.d *.shm *.log *.key *.dsn *.trn .simvision INCA_libs
