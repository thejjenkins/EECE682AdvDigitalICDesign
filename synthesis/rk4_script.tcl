# Name: rk4_script.tcl
# Author: James Jenkins
# Date: 3/21/26
#
# This file is a tcl script for running the genus synthesis flow "genus -f rk4_script.tcl"
# This file uses "counter_script.tcl" as a reference written by Matthew Morrison

set_db lib_search_path /projects/howard/process/howard/tsmc/tsmc18/oa/v1.3a/IP_HOME/tsmc/STD_CELL/tcb018gbwp7t/290a/digital/Front_End/timing_power_noise/NLDM/tcb018gbwp7t_270a/
set_db lef_library /projects/howard/process/howard/tsmc/tsmc18/oa/v1.3a/IP_HOME/tsmc/STD_CELL/tcb018gbwp7t/290a/digital/Back_End/lef/tcb018gbwp7t_270a/lef/tcb018gbwp7t_6lm.lef/

set_db library {tcb018gbwp7twcl.lib}
set_db init_hdl_search_path ../rtl/

read_hdl -sv {rk4_top.sv rk4_alu.sv rk4_clk_gen.sv rk4_clock_divider.sv rk4_control_fsm.sv rk4_f_engine.sv rk4_projectile_top.sv rk4_regfile.sv rk4_ring_osc.sv rk4_uart_protocol.sv uart_rx.sv uart_tx.sv}
elaborate

read_sdc constraints.sdc

set_db syn_generic_effort medium
set_db syn_map_effort medium
set_db syn_opt_effort medium

syn_generic
syn_map
# Add this after syn_map, before syn_opt
set_db [get_cells -hierarchical clock_unit/Oscillator*] .dont_touch true
syn_opt


#reports
report_timing > reports/rk4_top_timing.rpt
report_power  > reports/rk4_top_power.rpt
report_area   > reports/rk4_top_area.rpt
report_gates  > reports/rk4_top_gates.rpt
report_qor    > reports/rk4_top_qor.rpt

#Outputs
write_hdl > outputs/rk4_top_netlist.v
write_sdc > outputs/rk4_top_sdc.sdc
write_sdf -timescale ns -nonegchecks -recrem split -edges check_edge  -setuphold split > outputs/delays.sdf

write_db -common rk4_to