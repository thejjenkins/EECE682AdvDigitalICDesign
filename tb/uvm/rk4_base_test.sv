class rk4_base_test extends uvm_test;

    `uvm_component_utils(rk4_base_test)

    rk4_base_env  env;
    virtual rk4_if vif;

    function new(string name = "rk4_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual rk4_if)::get(this, "", "rk4_vif", vif))
            `uvm_fatal(get_type_name(), "Failed to get rk4_vif from config_db")

        env = rk4_base_env::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        rk4_base_sequence seq;
        phase.raise_objection(this, "rk4_base_test");
        `uvm_info(get_type_name(), "run_phase: objection raised", UVM_FULL)

        apply_reset();

        seq = rk4_base_sequence::type_id::create("seq");
        `uvm_info(get_type_name(),
            $sformatf("Starting sequence on sqr @ %0t", $time), UVM_FULL)
        seq.start(env.agent.sqr);

        `uvm_info(get_type_name(), "Sequence complete — waiting for DUT response", UVM_MEDIUM)
        `uvm_info(get_type_name(),
            $sformatf("scb.done_marker_received=%0b  scb.rx_bytes.size=%0d @ %0t",
                env.scb.done_marker_received, env.scb.rx_bytes.size(), $time), UVM_FULL)

        fork
            begin
                `uvm_info(get_type_name(),
                    $sformatf("Polling done_marker (currently %0b) @ %0t",
                        env.scb.done_marker_received, $time), UVM_FULL)
                wait (env.scb.done_marker_received);
                `uvm_info(get_type_name(),
                    $sformatf("Done marker received — total bytes=%0d @ %0t",
                        env.scb.rx_bytes.size(), $time), UVM_MEDIUM)
            end
            begin
                #5ms;
                `uvm_info(get_type_name(),
                    $sformatf("TIMEOUT — scb state: bytes=%0d  pairs=%0d  done=%0b",
                        env.scb.rx_bytes.size(), env.scb.data_pair_count,
                        env.scb.done_marker_received), UVM_FULL)
                `uvm_error(get_type_name(), "Timeout waiting for done marker")
            end
        join_any
        disable fork;

        `uvm_info(get_type_name(),
            $sformatf("Post-wait: dropping objection in 1 us @ %0t", $time), UVM_FULL)
        #1us;
        phase.drop_objection(this, "rk4_base_test");
        `uvm_info(get_type_name(), "run_phase: objection dropped", UVM_FULL)
    endtask

    virtual task apply_reset();
        `uvm_info(get_type_name(), "Applying reset", UVM_MEDIUM)
        `uvm_info(get_type_name(),
            $sformatf("rst_n=%b  uart_rx=%b before reset @ %0t",
                vif.rst_n, vif.uart_rx, $time), UVM_FULL)
        vif.rst_n   = 1'b0;
        vif.uart_rx = 1'b1;
        repeat (20) @(posedge vif.clk);
        vif.rst_n = 1'b1;
        repeat (5) @(posedge vif.clk);
        `uvm_info(get_type_name(), "Reset released", UVM_MEDIUM)
        `uvm_info(get_type_name(),
            $sformatf("rst_n=%b  uart_rx=%b after reset @ %0t",
                vif.rst_n, vif.uart_rx, $time), UVM_FULL)
    endtask

endclass
