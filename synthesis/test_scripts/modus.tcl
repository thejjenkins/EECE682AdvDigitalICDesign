proc pause {message} {
    puts -nonewline $message
    flush stdout
    gets stdin
}


build_model -workdir mydir -designsource rk4_projectile_top.test_netlist.v -techlib /projects/howard/process/howard/tsmc/tsmc18/oa/v1.3a/IP_HOME/tsmc/STD_CELL/tcb018gbwp7t/290a/digital/Front_End/verilog/tcb018gbwp7t_270a/tcb018gbwp7t.v -designtop rk4_projectile_top

pause "Hit Enter to Build Test Mode"

build_testmode -workdir mydir -testmode FULLSCAN -assignfile  rk4_projectile_top.FULLSCAN.pinassign
pause "Hit Enter to Verify Test Structures"

verify_test_structures -workdir mydir -testmode FULLSCAN

pause "Hit Enter to Report Test Structures"

report_test_structures -workdir mydir -testmode FULLSCAN

pause "Hit Enter to Build Fault Model"

build_faultmodel -workdir mydir -fullfault yes

pause "Hit Enter to Create Scan Chains"

create_scanchain_tests -workdir mydir -testmode FULLSCAN -experiment scan

pause "Hit Enter to Create Logic Tests"

create_logic_tests -workdir mydir -testmode FULLSCAN -experiment logic -effort high
