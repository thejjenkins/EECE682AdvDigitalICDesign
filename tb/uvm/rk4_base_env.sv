class rk4_base_env extends uvm_env;

    `uvm_component_utils(rk4_base_env)

    rk4_base_agent      agent;
    rk4_base_scoreboard scb;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = rk4_base_agent::type_id::create("agent", this);
        scb   = rk4_base_scoreboard::type_id::create("scb", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.mon.ap.connect(scb.analysis_export);
    endfunction

endclass
