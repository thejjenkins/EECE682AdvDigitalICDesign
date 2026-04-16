# create_clock -name clk_100MHz -period 10 -waveform {0 5} [get_ports clk_100MHz]

# set_clock_transition -rise 0.1 [get_clocks clk_100MHz]
# set_clock_transition -fall 0.1 [get_clocks clk_100MHz]
# set_clock_uncertainty 0.1      [get_clocks clk_100MHz]

# set_false_path -from [get_ports clk_100MHz] -to [get_ports clk_1Hz]

# # Also constrain the top-level clk_1Hz output port
# create_generated_clock -name clk_1Hz \
#     -source [get_pins clock_unit/divider/clk_out] \
#     -divide_by 1 \
#     [get_ports clk_1Hz]

# ###############################################
# # Input / Output Delays
# # Referenced to the primary clock
# ###############################################
# # Exclude clock ports and the generated clk_1Hz output
# set_input_delay  -clock clk_100MHz 2.0 [remove_from_collection [all_inputs]  [get_ports {clk_100MHz}]]
# set_output_delay -clock clk_100MHz 2.0 [remove_from_collection [all_outputs] [get_ports {clk_1Hz}]]

create_clock -name clk -period 10 -waveform {0 5} [get_port "clk"]

set_clock_transition -rise 0.1 [get_clocks "clk"]
set_clock_transition -fall 0.1 [get_clocks "clk"]

set_clock_uncertainty 0.01 [get_clocks "clk"]

set_input_delay -clock clk 2 [all_inputs]
set_output_delay -clock clk 2 [all_outputs]

# ===========================================================================
#  JTAG TCK clock (20 MHz max, conservative for lab use)
# ===========================================================================
create_clock -name tck -period 50 -waveform {0 25} [get_ports tck]

set_clock_transition -rise 0.1 [get_clocks tck]
set_clock_transition -fall 0.1 [get_clocks tck]
set_clock_uncertainty 0.5      [get_clocks tck]

# Declare clk and tck as asynchronous — no timing relationship
set_clock_groups -asynchronous \
    -group [get_clocks clk] \
    -group [get_clocks tck]

# Belt-and-suspenders: explicit false paths on synchronizer first-stage inputs
set_false_path -from [get_clocks tck] -to [get_cells {snap_req_tgl_pipe_reg[0] halt_req_pipe_reg[0] resume_req_tgl_pipe_reg[0] single_step_tgl_pipe_reg[0]}]
set_false_path -from [get_clocks clk] -to [get_cells {snap_ack_tgl_pipe_reg[0] dbg_halted_pipe_reg[0]}]

# Keep synchronizer FFs close together
set_max_delay -datapath_only 2.0 \
    -from [get_pins {*_tgl_pipe_reg[0]/Q}] \
    -to   [get_pins {*_tgl_pipe_reg[1]/D}]
set_max_delay -datapath_only 2.0 \
    -from [get_pins {*_pipe_reg[0]/Q}] \
    -to   [get_pins {*_pipe_reg[1]/D}]