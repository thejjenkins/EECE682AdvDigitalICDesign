# Clock Tree Synthesis Script

# Uncomment next two lines once the CTS fully runs
eval_legacy "setTieHiLoMode -cell {{TIEHBWP7T} {TIELBWP7T} {TIELBWP7T} {TIEHBWP7T} {GTIELBWP7T} {GTIELBWP7T} {GTIEHBWP7T} {GTIEHBWP7T}} -maxFanout 10 -maxDistance 20"

eval_legacy "addTieHiLo"


set_db timing_analysis_type ocv


# Note: The script outputs the following as possible valid inverters: 

set CTS_REF_LIST "{{CKND0BWP7T} {CKND1BWP7T} {CKND2BWP7T} {CKND2D0BWP7T} {CKND2D1BWP7} {CKND2D2BWP7T} {CKND2D3BWP7T} {CKND2D4BWP7T} {CKND2D8BWP7T} {CKND3BWP7T} {CKND4BWP7T} {CKND6BWP7T} {CKND8BWP7T} {CKND10BWP7T} {CKND12BWP7T}}"

# Note: The setup script outputs the follwoing as possible valid buffers: CKND0BWP7T CKND1BWP7T CKND2BWP7T CKND2D0BWP7T CKND2D1BWP7T CKND2D2BWP7T CKND2D3BWP7T CKND2D4BWP7T CKND2D8BWP7T CKND3BWP7T CKND4BWP7T CKND6BWP7T CKND8BWP7T CKND10BWP7T CKND12BWP7

set CTS_BUF_LIST {CKBD1BWP7T CKBD2BWP7T CKBD3BWP7T CKBD4BWP7T CKBD6BWP7T CKBD8BWP7T CKBD10BWP7T CKBD12BWP7T}

# Note: The setup script identifies the following as valid delay cells: CKND0BWP7T CKND1BWP7T CKND2BWP7T CKND2D0BWP7T CKND2D1BWP7T CKND2D2BWP7T CKND2D3BWP7T CKND2D4BWP7T CKND2D8BWP7T CKND3BWP7T CKND4BWP7T CKND6BWP7T CKND8BWP7T CKND10BWP7T CKND12BWP7

set CTS_LOGIC_LIST {CKAN2D0BWP7T CKAN2D1BWP7T CKAN2D2BWP7T CKAN2D0BWP7T CKMUX2D0BWP7T CKMUX2D4BWP7T CKAN2D8BWP7T CKMUX2D2BWP7T}

set cts_ref_list $CTS_REF_LIST
set cts_buf_list $CTS_BUF_LIST
set cts_logic_list $CTS_LOGIC_LIST


########## Create Leaf Rule

create_route_rule -name cts_spec_1w_2s_leaf -width {METAL1 0.23 METAL2 0.28 METAL3 0.28 METAL4 0.28 METAL5 0.28 METAL6 0.44} -spacing {METAL1 0.23 METAL2 0.28 METAL3 0.28 METAL4 0.28 METAL5 0.28 METAL6 0.46} 


create_route_type -name RT_LEAF_RULE -route_rule cts_spec_1w_2s_leaf -top_preferred_layer METAL6 -bottom_preferred_layer METAL2 -preferred_routing_layer_effort high

 
########## Create Trunk Rule



create_route_rule -name cts_spec_2w_2s_shield -width {METAL1 0.46 METAL2 0.56 METAL3 0.56 METAL4 0.56 METAL5 0.56 METAL6 0.88} -spacing {METAL1 0.46 METAL2 0.56 METAL3 0.56 METAL4 0.56 METAL5 0.56 METAL6 0.92} 


create_route_type -name RT_TRUNK_RULE -route_rule cts_spec_2w_2s_shield -shield_net VSS -top_preferred_layer METAL4 -bottom_preferred_layer METAL3 -preferred_routing_layer_effort high


########## Set Up

set_db cts_route_type_top "default"

set_db cts_route_type_trunk "RT_TRUNK_RULE"

set_db cts_route_type_leaf "RT_LEAF_RULE"

commit_clock_tree_route_attributes




eval_legacy "set_ccopt_property primary_delay_corner max_delay"
eval_legacy "set_ccopt_property target_max_trans 400ps"
eval_legacy "set_ccopt_property target_max_trans 400ps -net_type leaf"
eval_legacy "set_ccopt_property max_fanout 32"
eval_legacy "set_ccopt_property target_skew 400ps"
eval_legacy "set_ccopt_property buffer_cells {{CKBD1BWP7T} {CKBD2BWP7T} {CKBD3BWP7T} {CKBD4BWP7T} {CKBD6BWP7T} {CKBD8BWP7T} {CKBD10BWP7T} {CKBD12BWP7T}}"
eval_legacy "set_ccopt_property inverter_cells {{CKND0BWP7T} {CKND1BWP7T} {CKND2BWP7T} {CKND2D0BWP7T} {CKND2D1BWP7T} {CKND2D2BWP7T} {CKND2D3BWP7T} {CKND2D4BWP7T} {CKND2D8BWP7T} {CKND3BWP7T} {CKND4BWP7T} {CKND6BWP7T}{CKND8BWP7T} {CKND10BWP7T} {CKND12BWP7}}"
eval_legacy "set_ccopt_property use_inverters true"
eval_legacy "set_ccopt_property logic_cells {{CKAN2D0BWP7T} {CKAN2D1BWP7T} {CKAN2D2BWP7T} {CKAN2D0BWP7T} {CKMUX2D0BWP7T} {CKMUX2D4BWP7T} {CKAN2D8BWP7T} {CKMUX2D2BWP7T}}"


##########  Run the Synthesis 

eval_legacy "create_ccopt_clock_tree_spec -file final_ccopt/final_chip.ccopt.spec"

eval_legacy "ccopt_design -cts -outDir final_ccopt/ -prefix postcts"


eval_legacy "timeDesign -postCTS -expandedViews -outDir final_ccopt/timing"
eval_legacy "report_ccopt_clock_trees -file final_ccopt/final_chip.clock_trees.rpt"
eval_legacy "report_ccopt_skew_groups -file final_ccopt/final_chip.skew_groups.rpt"