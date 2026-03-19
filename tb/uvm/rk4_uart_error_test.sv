class rk4_uart_error_test extends rk4_base_test;

    `uvm_component_utils(rk4_uart_error_test)

    int baud_div;

    function new(string name = "rk4_uart_error_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(int)::get(this, "", "baud_div", baud_div))
            baud_div = 434;
    endfunction

    virtual task run_phase(uvm_phase phase);
        rk4_base_sequence seq;
        phase.raise_objection(this, "rk4_uart_error_test");

        apply_reset();

        // ---------------------------------------------------------------
        //  Error injection 1: false start glitch
        //  Drive rx low just long enough for the synchronizer to see it,
        //  then pull it high before the mid-bit sample at HALF_DIV.
        //  uart_rx will enter active mode, count down baud_cnt from
        //  HALF_DIV, then find rx_sync==1 at bit_cnt==0 and abort.
        // ---------------------------------------------------------------
        `uvm_info(get_type_name(), "Injecting false start glitch", UVM_MEDIUM)
        vif.uart_rx = 1'b0;
        repeat (300) @(posedge vif.clk);
        vif.uart_rx = 1'b1;
        repeat (baud_div * 2) @(posedge vif.clk);

        // ---------------------------------------------------------------
        //  Error injection 2: byte with bad stop bit
        //  Send a normal start bit + 8 data bits, but hold rx LOW
        //  during the stop bit period so rx_sync==0 at bit_cnt==9.
        // ---------------------------------------------------------------
        `uvm_info(get_type_name(), "Injecting byte with bad stop bit", UVM_MEDIUM)
        send_byte_bad_stop(8'hA5);
        repeat (baud_div * 2) @(posedge vif.clk);

        // ---------------------------------------------------------------
        //  Error injection 3: unknown command byte
        //  Send 0xFF while protocol is in ST_CMD — hits the default
        //  branch on line 84 of rk4_uart_protocol.sv.
        // ---------------------------------------------------------------
        `uvm_info(get_type_name(), "Injecting unknown command byte 0xFF", UVM_MEDIUM)
        send_uart_byte(8'hFF);
        repeat (baud_div * 2) @(posedge vif.clk);

        // ---------------------------------------------------------------
        //  Recovery: run the normal base sequence to prove the DUT
        //  still works after the UART errors.
        // ---------------------------------------------------------------
        `uvm_info(get_type_name(), "Running normal sequence to verify recovery", UVM_MEDIUM)
        vif.uart_rx = 1'b1;
        repeat (baud_div) @(posedge vif.clk);

        seq = rk4_base_sequence::type_id::create("seq");
        seq.start(env.agent.sqr);

        // ---------------------------------------------------------------
        //  Error injection 4: back-to-back RUN while FSM is busy
        //  The base sequence just finished transmitting LOAD_PROG + RUN
        //  bytes, so the FSM is now processing.  Bit-bang a second RUN
        //  command immediately — when the 4th v0 byte arrives the
        //  protocol parser checks if (!fsm_busy) and takes the implicit
        //  else path on line 118.
        // ---------------------------------------------------------------
        `uvm_info(get_type_name(), "Injecting back-to-back RUN while FSM busy", UVM_MEDIUM)
        send_uart_byte(8'h02);   // CMD_RUN
        send_uart_byte(8'h00);   // v0[7:0]
        send_uart_byte(8'h00);   // v0[15:8]
        send_uart_byte(8'h01);   // v0[23:16]
        send_uart_byte(8'h00);   // v0[31:24]

        fork
            begin
                wait (env.scb.done_marker_received);
                `uvm_info(get_type_name(),
                    $sformatf("Done marker received, bytes=%0d",
                        env.scb.rx_bytes.size()), UVM_MEDIUM)
            end
            begin
                #5ms;
                `uvm_error(get_type_name(), "Timeout waiting for done marker after error injection")
            end
        join_any
        disable fork;

        #1us;
        phase.drop_objection(this, "rk4_uart_error_test");
    endtask

    virtual task send_uart_byte(input bit [7:0] data);
        vif.uart_rx = 1'b0;
        repeat (baud_div) @(posedge vif.clk);
        for (int i = 0; i < 8; i++) begin
            vif.uart_rx = data[i];
            repeat (baud_div) @(posedge vif.clk);
        end
        vif.uart_rx = 1'b1;
        repeat (baud_div) @(posedge vif.clk);
    endtask

    virtual task send_byte_bad_stop(input bit [7:0] data);
        vif.uart_rx = 1'b0;
        repeat (baud_div) @(posedge vif.clk);
        for (int i = 0; i < 8; i++) begin
            vif.uart_rx = data[i];
            repeat (baud_div) @(posedge vif.clk);
        end
        vif.uart_rx = 1'b0;
        repeat (baud_div) @(posedge vif.clk);
        vif.uart_rx = 1'b1;
    endtask

endclass
