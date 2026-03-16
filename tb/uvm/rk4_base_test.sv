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

        apply_reset();

        seq = rk4_base_sequence::type_id::create("seq");
        seq.start(env.agent.sqr);

        `uvm_info(get_type_name(), "Sequence complete — waiting for DUT response", UVM_MEDIUM)

        fork
            begin
                wait (env.scb.done_marker_received);
                `uvm_info(get_type_name(), "Done marker received", UVM_MEDIUM)
            end
            begin
                #50ms;
                `uvm_error(get_type_name(), "Timeout waiting for done marker")
            end
        join_any
        disable fork;

        #1us;
        phase.drop_objection(this, "rk4_base_test");
    endtask

    virtual task apply_reset();
        `uvm_info(get_type_name(), "Applying reset", UVM_MEDIUM)
        vif.rst_n   = 1'b0;
        vif.uart_rx = 1'b1;
        repeat (20) @(posedge vif.clk);
        vif.rst_n = 1'b1;
        repeat (5) @(posedge vif.clk);
        `uvm_info(get_type_name(), "Reset released", UVM_MEDIUM)
    endtask

endclass
