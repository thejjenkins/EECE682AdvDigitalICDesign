read library /projects/howard/process/howard/tsmc/tsmc18/oa/v1.3a/IP_HOME/tsmc/STD_CELL/tcb018gbwp7t/290a/digital/Front_End/verilog/tcb018gbwp7t_270a/tcb018gbwp7t.v -verilog -both
read design ../rtl/rk4_top.sv ../rtl/rk4_clk_gen.sv ../rtl/rk4_alu.sv ../rtl/rk4_clock_divider.sv ../rtl/rk4_control_fsm.sv ../rtl/rk4_f_engine.sv ../rtl/rk4_projectile_top.sv ../rtl/rk4_regfile.sv ../rtl/rk4_ring_osc.sv ../rtl/rk4_uart_protocol.sv ../rtl/uart_rx.sv ../rtl/uart_tx.sv -systemverilog -golden
read design ../synthesis/outputs/rk4_top_netlist_dft.v -verilog -revised
add pin constraints 0 SE  -revised
add ignored inputs scan_in -revised
add ignored outputs scan_out -revised
set system mode lec
add compared point -all
compare 