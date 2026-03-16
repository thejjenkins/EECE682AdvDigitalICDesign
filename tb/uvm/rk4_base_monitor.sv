class rk4_base_monitor extends uvm_monitor;

    `uvm_component_utils(rk4_base_monitor)

    virtual rk4_if vif;
    int baud_div = 434;

    uvm_analysis_port #(rk4_seq_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db#(virtual rk4_if)::get(this, "", "rk4_vif", vif))
            `uvm_fatal(get_type_name(), "Failed to get rk4_vif from config_db")
        if (!uvm_config_db#(int)::get(this, "", "baud_div", baud_div))
            `uvm_info(get_type_name(), $sformatf("baud_div not in config_db, using default %0d", baud_div), UVM_MEDIUM)
    endfunction

    virtual task run_phase(uvm_phase phase);
        @(posedge vif.rst_n);
        `uvm_info(get_type_name(), "Reset released, monitor active", UVM_MEDIUM)
        forever begin
            rk4_seq_item item;
            bit [7:0]    rx_byte;

            receive_uart_byte(rx_byte);

            item = rk4_seq_item::type_id::create("mon_item");
            item.cmd_type   = RK4_CMD_RAW_BYTES;
            item.payload    = new[1];
            item.payload[0] = rx_byte;
            ap.write(item);
        end
    endtask

    virtual task receive_uart_byte(output bit [7:0] data);
        // Wait for start bit (falling edge on uart_tx)
        @(negedge vif.uart_tx);

        // Advance to mid-bit of start bit
        repeat (baud_div / 2) @(posedge vif.clk);

        // Verify start bit is still low
        if (vif.uart_tx !== 1'b0) begin
            `uvm_warning(get_type_name(), "False start bit detected")
            return;
        end

        // Sample 8 data bits at mid-bit, LSB first
        for (int i = 0; i < 8; i++) begin
            repeat (baud_div) @(posedge vif.clk);
            data[i] = vif.uart_tx;
        end

        // Advance to mid-bit of stop bit
        repeat (baud_div) @(posedge vif.clk);
        if (vif.uart_tx !== 1'b1)
            `uvm_warning(get_type_name(), "Stop bit not detected")
    endtask

endclass
