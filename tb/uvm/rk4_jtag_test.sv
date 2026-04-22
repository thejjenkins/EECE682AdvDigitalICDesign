class rk4_jtag_test extends rk4_base_test;

    `uvm_component_utils(rk4_jtag_test)

    localparam [2:0] IR_BYPASS0  = 3'b000;
    localparam [2:0] IR_IDCODE   = 3'b001;
    localparam [2:0] IR_DBG_ADDR = 3'b010;
    localparam [2:0] IR_DBG_DATA = 3'b011;

    localparam [31:0] EXPECTED_IDCODE = 32'hEECE_00DE;

    localparam realtime TCK_PERIOD = 200ns;

    function new(string name = "rk4_jtag_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // =================================================================
    //  JTAG bit-bang primitives
    // =================================================================

    task jtag_tck_cycle(input logic tms_val, input logic tdi_val = 1'b0);
        vif.tms = tms_val;
        vif.tdi = tdi_val;
        #(TCK_PERIOD / 2);
        vif.tck = 1'b1;
        #(TCK_PERIOD / 2);
        vif.tck = 1'b0;
    endtask

    task jtag_reset();
        vif.tdi = 1'b0;
        repeat (6) jtag_tck_cycle(1'b1);
    endtask

    task jtag_goto_rti();
        jtag_tck_cycle(1'b0);  // TLR -> RTI
    endtask

    task jtag_shift_ir(input logic [2:0] ir_val);
        // RTI -> SelectDR (TMS=1)
        jtag_tck_cycle(1'b1);
        // SelectDR -> SelectIR (TMS=1)
        jtag_tck_cycle(1'b1);
        // SelectIR -> CaptureIR (TMS=0)
        jtag_tck_cycle(1'b0);
        // CaptureIR -> ShiftIR (TMS=0)
        jtag_tck_cycle(1'b0);

        // Shift 3 bits (LSB first), TMS=0 for first 2, TMS=1 on last
        for (int i = 0; i < 3; i++) begin
            logic last_bit;
            last_bit = (i == 2);
            jtag_tck_cycle(last_bit, ir_val[i]);
        end

        // Exit1IR -> UpdateIR (TMS=1)
        jtag_tck_cycle(1'b1);
        // UpdateIR -> RTI (TMS=0)
        jtag_tck_cycle(1'b0);
    endtask

    task jtag_shift_dr(input int nbits,
                       input logic [31:0] tdi_val,
                       output logic [31:0] tdo_val);
        tdo_val = 32'h0;

        // RTI -> SelectDR (TMS=1)
        jtag_tck_cycle(1'b1);
        // SelectDR -> CaptureDR (TMS=0)
        jtag_tck_cycle(1'b0);
        // CaptureDR -> ShiftDR (TMS=0)
        jtag_tck_cycle(1'b0);

        for (int i = 0; i < nbits; i++) begin
            logic last_bit;
            last_bit = (i == nbits - 1);
            vif.tms = last_bit;
            vif.tdi = tdi_val[i];
            #(TCK_PERIOD / 2);
            vif.tck = 1'b1;
            tdo_val[i] = vif.tdo;
            #(TCK_PERIOD / 2);
            vif.tck = 1'b0;
        end

        // Exit1DR -> UpdateDR (TMS=1)
        jtag_tck_cycle(1'b1);
        // UpdateDR -> RTI (TMS=0)
        jtag_tck_cycle(1'b0);
    endtask

    // Write a 4-bit address into DBG_ADDR, then read 32 bits from DBG_DATA
    task jtag_read_dbg_reg(input logic [3:0] addr,
                           output logic [31:0] data);
        logic [31:0] dummy;

        jtag_shift_ir(IR_DBG_ADDR);
        jtag_shift_dr(4, {28'h0, addr}, dummy);

        jtag_shift_ir(IR_DBG_DATA);
        jtag_shift_dr(32, 32'h0, data);
    endtask

    // =================================================================
    //  Main test body
    // =================================================================

    virtual task run_phase(uvm_phase phase);
        rk4_base_sequence seq;
        logic [31:0] tdo_data;

        phase.raise_objection(this, "rk4_jtag_test");

        apply_reset();

        // Allow a few clocks for TAP to settle after reset
        repeat (10) @(posedge vif.clk);

        // =============================================================
        //  TEST 1: IDCODE read
        // =============================================================
        `uvm_info(get_type_name(), "TEST 1: IDCODE read", UVM_MEDIUM)

        jtag_reset();
        jtag_goto_rti();

        jtag_shift_ir(IR_IDCODE);
        jtag_shift_dr(32, 32'h0, tdo_data);

        if (tdo_data === EXPECTED_IDCODE)
            `uvm_info(get_type_name(),
                $sformatf("IDCODE PASS: got 0x%08h", tdo_data), UVM_MEDIUM)
        else
            `uvm_error(get_type_name(),
                $sformatf("IDCODE FAIL: expected 0x%08h, got 0x%08h",
                    EXPECTED_IDCODE, tdo_data))

        // =============================================================
        //  TEST 2: BYPASS test
        //  In bypass mode the 1-bit register inserts a 1-cycle delay.
        //  Shift 8 bits in and verify they come back shifted by 1.
        // =============================================================
        `uvm_info(get_type_name(), "TEST 2: BYPASS test", UVM_MEDIUM)

        jtag_shift_ir(IR_BYPASS0);
        begin
            logic [7:0] pattern_in, pattern_out;
            logic [31:0] raw_out;
            pattern_in = 8'hA5;
            jtag_shift_dr(8, {24'h0, pattern_in}, raw_out);
            pattern_out = raw_out[7:0];
            // Bit 0 of TDO is the captured bypass reg (0), then bits 1-7
            // are the delayed version of input bits 0-6
            if (pattern_out[7:1] === pattern_in[6:0])
                `uvm_info(get_type_name(),
                    $sformatf("BYPASS PASS: in=0x%02h, out=0x%02h",
                        pattern_in, pattern_out), UVM_MEDIUM)
            else
                `uvm_error(get_type_name(),
                    $sformatf("BYPASS FAIL: in=0x%02h, out=0x%02h (expected delayed pattern)",
                        pattern_in, pattern_out))
        end

        // =============================================================
        //  TEST 3: Debug register reads after RK4 computation
        //  Load a program, run it, wait for completion, then read
        //  debug registers via JTAG and verify plausible values.
        // =============================================================
        `uvm_info(get_type_name(), "TEST 3: Debug register reads", UVM_MEDIUM)

        seq = rk4_base_sequence::type_id::create("seq");
        seq.start(env.agent.sqr);

        `uvm_info(get_type_name(), "Sequence sent — waiting for done marker", UVM_MEDIUM)

        fork
            begin
                wait (env.scb.done_marker_received);
                `uvm_info(get_type_name(),
                    $sformatf("Done marker received, bytes=%0d",
                        env.scb.rx_bytes.size()), UVM_MEDIUM)
            end
            begin
                #1500ms;
                `uvm_error(get_type_name(), "Timeout waiting for done marker")
            end
        join_any
        disable fork;

        // Let system settle
        repeat (100) @(posedge vif.clk);

        // Re-init JTAG TAP
        jtag_reset();
        jtag_goto_rti();

        // Read FSM status (addr 0x1): should show not-busy after completion
        begin
            logic [31:0] status_val;
            jtag_read_dbg_reg(4'h1, status_val);
            `uvm_info(get_type_name(),
                $sformatf("DBG_REG[0x1] (status) = 0x%08h  busy=%0b  f_active=%0b  fsm_state=%0d",
                    status_val, status_val[6], status_val[7], status_val[5:0]), UVM_MEDIUM)
            if (status_val[6] === 1'b0)
                `uvm_info(get_type_name(), "FSM not busy after completion — PASS", UVM_MEDIUM)
            else
                `uvm_error(get_type_name(), "FSM still busy after done marker — FAIL")
        end

        // Read rf_t (addr 0x2)
        begin
            logic [31:0] t_val;
            jtag_read_dbg_reg(4'h2, t_val);
            `uvm_info(get_type_name(),
                $sformatf("DBG_REG[0x2] (rf_t) = 0x%08h", t_val), UVM_MEDIUM)
        end

        // Read rf_y (addr 0x3)
        begin
            logic [31:0] y_val;
            jtag_read_dbg_reg(4'h3, y_val);
            `uvm_info(get_type_name(),
                $sformatf("DBG_REG[0x3] (rf_y) = 0x%08h", y_val), UVM_MEDIUM)
        end

        // Read dt (addr 0x4)
        begin
            logic [31:0] dt_val;
            jtag_read_dbg_reg(4'h4, dt_val);
            `uvm_info(get_type_name(),
                $sformatf("DBG_REG[0x4] (dt) = 0x%08h", dt_val), UVM_MEDIUM)
        end

        // Read an unused address (0xF) — should return zero
        begin
            logic [31:0] unused_val;
            jtag_read_dbg_reg(4'hF, unused_val);
            if (unused_val === 32'h0)
                `uvm_info(get_type_name(),
                    "DBG_REG[0xF] (unused) = 0x00000000 — PASS", UVM_MEDIUM)
            else
                `uvm_error(get_type_name(),
                    $sformatf("DBG_REG[0xF] expected 0, got 0x%08h", unused_val))
        end

        #1us;
        phase.drop_objection(this, "rk4_jtag_test");
    endtask

endclass
