class rk4_base_agent extends uvm_agent;

    `uvm_component_utils(rk4_base_agent)

    rk4_base_sequencer sqr;
    rk4_base_driver    drv;
    rk4_base_monitor   mon;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = rk4_base_monitor::type_id::create("mon", this);
        if (get_is_active() == UVM_ACTIVE) begin
            sqr = rk4_base_sequencer::type_id::create("sqr", this);
            drv = rk4_base_driver::type_id::create("drv", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (get_is_active() == UVM_ACTIVE)
            drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction

endclass
