set_db lib_search_path /projects/howard/process/howard/tsmc/tsmc18/oa/v1.3a/IP_HOME/tsmc/STD_CELL/tcb018gbwp7t/290a/digital/Front_End/timing_power_noise/NLDM/tcb018gbwp7t_270a/
set_db lef_library /projects/howard/process/howard/tsmc/tsmc18/oa/v1.3a/IP_HOME/tsmc/STD_CELL/tcb018gbwp7t/290a/digital/Back_End/lef/tcb018gbwp7t_270a/lef/tcb018gbwp7t_6lm.lef/

set_db library {tcb018gbwp7twcl.lib}
set_db init_hdl_search_path ../rtl/

read_hdl -sv {rk4_top.sv rk4_alu.sv rk4_clk_gen.sv rk4_ring_osc.sv rk4_clock_divider.sv rk4_control_fsm.sv rk4_f_engine.sv rk4_projectile_top.sv rk4_regfile.sv rk4_uart_protocol.sv uart_rx.sv uart_tx.sv jtag_tap.sv}
elaborate

read_sdc constraints.sdc

# DFT
set_db dft_scan_style muxed_scan 
set_db dft_prefix dft_
define_shift_enable -name SE -active high -create_port SE

# This is what was missing - tells DFT engine which clock to use for scan shift
define_test_clock -name clk_100MHz -period 10000 [get_ports clk_100MHz]

# Define the internally driven clocks so DFT recognizes them as valid
define_clock -name clk_div -period 10000 [get_pins clock_unit/divider/clk_out_reg/q]
define_clock -name clk_mux -period 10000 [get_pins clock_unit/mux_osc_out_18_15/g1/z]

check_dft_rules

set_db syn_generic_effort medium
set_db syn_map_effort medium
set_db syn_opt_effort medium

syn_generic
syn_map
# Fix uncontrollable clock violations by inserting test muxes
fix_dft_violations -clock -test_control SE
syn_opt

# Check the DFT Rules
check_dft_rules 
set_db design:rk4_top .dft_min_number_of_scan_chains 1 
define_scan_chain -name top_chain -sdi scan_in -sdo scan_out -create_ports

connect_scan_chains -auto_create_chains
syn_opt -incremental


#reports 
report_timing > reports/rk4_top_dft_timing.rpt
report_power  > reports/rk4_top_dft_power.rpt
report_area   > reports/rk4_top_dft_area.rpt
report_gates  > reports/rk4_top_dft_gates.rpt
report_qor    > reports/rk4_top_dft_qor.rpt

#Outputs
report_scan_chains
write_dft_atpg -library outputs/basiccells.v -directory outputs/atpg
write_hdl > outputs/rk4_top_netlist_dft.v
write_sdc > outputs/rk4_top_sdc_dft.sdc
write_sdf -nonegchecks -edges check_edge -timescale ns -recrem split  -setuphold split > outputs/dft_delays.sdf
write_scandef > outputs/rk4_top_scanDEF.scandef
