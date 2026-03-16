class rk4_base_driver extends uvm_driver #(rk4_seq_item);

    `uvm_component_utils(rk4_base_driver)

    virtual rk4_if vif;
    int baud_div = 434;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual rk4_if)::get(this, "", "rk4_vif", vif))
            `uvm_fatal(get_type_name(), "Failed to get rk4_vif from config_db")
        if (!uvm_config_db#(int)::get(this, "", "baud_div", baud_div))
            `uvm_info(get_type_name(), $sformatf("baud_div not in config_db, using default %0d", baud_div), UVM_MEDIUM)
    endfunction

    virtual task run_phase(uvm_phase phase);
        rk4_seq_item item;
        vif.uart_rx = 1'b1;
        forever begin
            seq_item_port.get_next_item(item);
            `uvm_info(get_type_name(), {"Driving: ", item.convert2string()}, UVM_HIGH)
            drive_item(item);
            seq_item_port.item_done();
        end
    endtask

    virtual task drive_item(rk4_seq_item item);
        bit [7:0] cmd_byte;

        case (item.cmd_type)
            RK4_CMD_LOAD_PROG: cmd_byte = 8'h01;
            RK4_CMD_RUN:       cmd_byte = 8'h02;
            default:           cmd_byte = 8'hFF;
        endcase

        if (item.cmd_type != RK4_CMD_RAW_BYTES)
            send_uart_byte(cmd_byte);

        foreach (item.payload[i])
            send_uart_byte(item.payload[i]);
    endtask

    virtual task send_uart_byte(input bit [7:0] data);
        // Start bit
        vif.uart_rx = 1'b0;
        repeat (baud_div) @(posedge vif.clk);

        // 8 data bits, LSB first
        for (int i = 0; i < 8; i++) begin
            vif.uart_rx = data[i];
            repeat (baud_div) @(posedge vif.clk);
        end

        // Stop bit
        vif.uart_rx = 1'b1;
        repeat (baud_div) @(posedge vif.clk);
    endtask

endclass
