set log file rk4_top_lec.log -replace
read library /projects/howard/process/howard/tsmc/tsmc18/oa/v1.3a/IP_HOME/tsmc/STD_CELL/tcb018gbwp7t/290a/digital/Front_End/verilog/tcb018gbwp7t_270a/tcb018gbwp7t.v -verilog -both
read design ../rtl/rk4_top.sv ../rtl/rk4_clk_gen.sv ../rtl/rk4_alu.sv ../rtl/rk4_clock_divider.sv ../rtl/rk4_control_fsm.sv ../rtl/rk4_f_engine.sv ../rtl/rk4_projectile_top.sv ../rtl/rk4_regfile.sv ../rtl/rk4_ring_osc.sv ../rtl/rk4_uart_protocol.sv ../rtl/uart_rx.sv ../rtl/uart_tx.sv ../rtl/jtag_tap.sv -systemverilog -golden
read design ../synthesis/outputs/rk4_top_netlist.v ../rtl/rk4_ring_osc.sv -verilog -revised
add pin constraints 0 en -both
add pin constraints 1 sel[0] -both
add pin constraints 1 sel[1] -both
add pin constraints 1 trst_n -both
add pin constraints 0 tms -both
add pin constraints 0 tdi -both
set flatten model -seq_constant
set flatten model -seq_redundant
set flatten model -gated_clock
set analyze option -auto
set system mode lec
add compared point -all
compare
report unmapped points
report compare data -nonequivalent
