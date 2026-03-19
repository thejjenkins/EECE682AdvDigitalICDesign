class rk4_clk_gen_test extends rk4_base_test;

    `uvm_component_utils(rk4_clk_gen_test)

    function new(string name = "rk4_clk_gen_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        rk4_base_sequence seq;
        phase.raise_objection(this, "rk4_clk_gen_test");

        apply_reset();

        // -----------------------------------------------------------
        //  Exercise all clock mux paths and ring oscillator toggles.
        //  Each sel value routes a different ring osc through the
        //  divider — waiting 2 us per path lets the divider counter
        //  cycle through its full range for toggle coverage.
        // -----------------------------------------------------------
        `uvm_info(get_type_name(), "Cycling clock mux sel=00 (ring osc 1)", UVM_MEDIUM)
        vif.sel = 2'b00;
        #2us;

        `uvm_info(get_type_name(), "Cycling clock mux sel=01 (ring osc 2)", UVM_MEDIUM)
        vif.sel = 2'b01;
        #2us;

        `uvm_info(get_type_name(), "Cycling clock mux sel=10 (ring osc 3)", UVM_MEDIUM)
        vif.sel = 2'b10;
        #2us;

        // -----------------------------------------------------------
        //  Toggle en (1 -> 0 -> 1) for ring oscillator enable coverage
        // -----------------------------------------------------------
        `uvm_info(get_type_name(), "Disabling ring oscillators (en=0)", UVM_MEDIUM)
        vif.en = 1'b0;
        #1us;

        `uvm_info(get_type_name(), "Re-enabling ring oscillators (en=1)", UVM_MEDIUM)
        vif.en = 1'b1;
        #1us;

        // -----------------------------------------------------------
        //  Return to external clock and re-apply reset so the
        //  divider re-synchronises to the external clock before
        //  running the UART-based base sequence.
        // -----------------------------------------------------------
        `uvm_info(get_type_name(), "Returning to external clock (sel=11)", UVM_MEDIUM)
        vif.sel = 2'b11;
        apply_reset();

        // -----------------------------------------------------------
        //  Run the normal base sequence to prove the DUT is fully
        //  functional after clock switching.
        // -----------------------------------------------------------
        `uvm_info(get_type_name(), "Running base sequence to verify recovery", UVM_MEDIUM)
        seq = rk4_base_sequence::type_id::create("seq");
        seq.start(env.agent.sqr);

        fork
            begin
                wait (env.scb.done_marker_received);
                `uvm_info(get_type_name(),
                    $sformatf("Done marker received, bytes=%0d",
                        env.scb.rx_bytes.size()), UVM_MEDIUM)
            end
            begin
                #5ms;
                `uvm_error(get_type_name(), "Timeout waiting for done marker")
            end
        join_any
        disable fork;

        #1us;
        phase.drop_objection(this, "rk4_clk_gen_test");
    endtask

endclass
