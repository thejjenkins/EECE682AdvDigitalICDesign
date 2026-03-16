class rk4_base_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(rk4_base_scoreboard)

    uvm_analysis_imp #(rk4_seq_item, rk4_base_scoreboard) analysis_export;

    bit [7:0] rx_bytes[$];
    bit       done_marker_received;
    int       data_pair_count;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        done_marker_received = 0;
        data_pair_count      = 0;
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        analysis_export = new("analysis_export", this);
    endfunction

    virtual function void write(rk4_seq_item item);
        foreach (item.payload[i])
            rx_bytes.push_back(item.payload[i]);

        `uvm_info(get_type_name(),
            $sformatf("RX byte 0x%02h  (total %0d bytes)", item.payload[0], rx_bytes.size()),
            UVM_HIGH)

        check_for_done_marker();
        count_data_pairs();
    endfunction

    virtual function void check_for_done_marker();
        int n = rx_bytes.size();
        if (n >= 4 &&
            rx_bytes[n-4] == 8'hDE &&
            rx_bytes[n-3] == 8'hAD &&
            rx_bytes[n-2] == 8'hBE &&
            rx_bytes[n-1] == 8'hEF) begin
            done_marker_received = 1;
            `uvm_info(get_type_name(), "Done marker 0xDEADBEEF received", UVM_LOW)
        end
    endfunction

    virtual function void count_data_pairs();
        int n = rx_bytes.size();
        if (!done_marker_received)
            data_pair_count = n / 8;
        else
            data_pair_count = (n - 4) / 8;
    endfunction

    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (done_marker_received) begin
            `uvm_info(get_type_name(),
                $sformatf("PASS — received %0d (t,y) pairs + done marker (%0d total bytes)",
                    data_pair_count, rx_bytes.size()), UVM_LOW)
        end else begin
            `uvm_error(get_type_name(),
                $sformatf("FAIL — done marker not received (got %0d bytes)", rx_bytes.size()))
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info(get_type_name(),
            $sformatf("Scoreboard summary: %0d bytes, %0d data pairs, done=%0b",
                rx_bytes.size(), data_pair_count, done_marker_received), UVM_LOW)
    endfunction

endclass
