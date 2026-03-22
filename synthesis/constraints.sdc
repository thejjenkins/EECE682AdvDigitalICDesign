create_clock -name clk_100MHz -period 10 -waveform {0 5} [get_ports clk_100MHz]

set_clock_transition -rise 0.1 [get_clocks clk_100MHz]
set_clock_transition -fall 0.1 [get_clocks clk_100MHz]
set_clock_uncertainty 0.1      [get_clocks clk_100MHz]

set_false_path -from [get_ports clk_100MHz] -to [get_ports clk_1Hz]

# Also constrain the top-level clk_1Hz output port
create_generated_clock -name clk_1Hz \
    -source [get_pins clock_unit/divider/clk_out] \
    -divide_by 1 \
    [get_ports clk_1Hz]

###############################################
# Input / Output Delays
# Referenced to the primary clock
###############################################
# Exclude clock ports and the generated clk_1Hz output
set_input_delay  -clock clk_100MHz 2.0 [remove_from_collection [all_inputs]  [get_ports {clk_100MHz}]]
set_output_delay -clock clk_100MHz 2.0 [remove_from_collection [all_outputs] [get_ports {clk_1Hz}]]

