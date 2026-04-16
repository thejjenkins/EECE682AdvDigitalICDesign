set log file rk4_top_lec.log -replace
read library /projects/howard/process/howard/tsmc/tsmc18/oa/v1.3a/IP_HOME/tsmc/STD_CELL/tcb018gbwp7t/290a/digital/Front_End/verilog/tcb018gbwp7t_270a/tcb018gbwp7t.v -verilog -both
read design ../rtl/rk4_top.sv ../rtl/rk4_alu.sv ../rtl/rk4_control_fsm.sv ../rtl/rk4_f_engine.sv ../rtl/rk4_projectile_top.sv ../rtl/rk4_regfile.sv ../rtl/rk4_uart_protocol.sv ../rtl/uart_rx.sv ../rtl/uart_tx.sv ../rtl/jtag_tap.sv ../rtl/inverter.sv ../rtl/jtag_debug_controller.sv ../rtl/jtag_snapshot_ctrl.sv -systemverilog -golden
read design ../synthesis/outputs/rk4_top_netlist.v -verilog -revised
// add pin constraints 1 sel[0] -both
// add pin constraints 1 sel[1] -both
set flatten model -seq_constant
set flatten model -seq_redundant
set flatten model -gated_clock
set analyze option -auto
set system mode lec
add compared point -all
compare
report unmapped points
report compare data -nonequivalent
