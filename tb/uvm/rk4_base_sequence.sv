class rk4_base_sequence extends uvm_sequence #(rk4_seq_item);

    `uvm_object_utils(rk4_base_sequence)

    function new(string name = "rk4_base_sequence");
        super.new(name);
    endfunction

    virtual task body();
        rk4_seq_item prog_item, run_item;

        `uvm_info(get_type_name(), "body() — sequence starting", UVM_FULL)

        // ---------------------------------------------------------------
        // 1. Load a trivial f-function program
        //
        //    Instruction 0:  PASS R0 → R7  (copies v0 into acc), HALT
        //
        //    Encoding (16-bit LE):
        //      [15:13] src_a  = 000  (R0 = v0)
        //      [12:10] src_b  = 000  (don't care)
        //      [ 9: 7] alu_op = 111  (PASS)
        //      [ 6: 4] dest   = 111  (R7 = acc)
        //      [    3] halt   = 1
        //      [ 2: 0] rsvd   = 000
        //    → 16'h03F8   LE bytes: {0xF8, 0x03}
        //
        //    Instructions 1-15 are zero (never reached due to halt).
        //    With this program the k-slopes stay zero and y remains 0
        //    for every step — the test simply verifies the full pipeline
        //    runs to completion and the 0xDEADBEEF done marker appears.
        // ---------------------------------------------------------------
        prog_item = rk4_seq_item::type_id::create("prog_item");
        prog_item.cmd_type = RK4_CMD_LOAD_PROG;
        prog_item.payload  = new[32];

        prog_item.payload[0] = 8'hF8;
        prog_item.payload[1] = 8'h03;
        for (int i = 2; i < 32; i++)
            prog_item.payload[i] = 8'h00;

        `uvm_info(get_type_name(),
            $sformatf("LOAD_PROG item: instr0={0x%02h,0x%02h}  payload_len=%0d",
                prog_item.payload[0], prog_item.payload[1], prog_item.payload.size()), UVM_FULL)

        start_item(prog_item);
        `uvm_info(get_type_name(), "LOAD_PROG start_item granted", UVM_FULL)
        finish_item(prog_item);

        `uvm_info(get_type_name(), "LOAD_PROG sent", UVM_MEDIUM)

        // ---------------------------------------------------------------
        // 2. Run with v0 = 1.0 in Q16.16  (0x0001_0000)
        //    Little-endian byte order: {0x00, 0x00, 0x01, 0x00}
        // ---------------------------------------------------------------
        run_item = rk4_seq_item::type_id::create("run_item");
        run_item.cmd_type = RK4_CMD_RUN;
        run_item.payload  = new[4];

        run_item.payload[0] = 8'h00;
        run_item.payload[1] = 8'h00;
        run_item.payload[2] = 8'h01;
        run_item.payload[3] = 8'h00;

        `uvm_info(get_type_name(),
            $sformatf("RUN item: v0={0x%02h,0x%02h,0x%02h,0x%02h}  payload_len=%0d",
                run_item.payload[0], run_item.payload[1],
                run_item.payload[2], run_item.payload[3],
                run_item.payload.size()), UVM_FULL)

        start_item(run_item);
        `uvm_info(get_type_name(), "RUN start_item granted", UVM_FULL)
        finish_item(run_item);

        `uvm_info(get_type_name(), "RUN sent (v0 = 1.0 Q16.16)", UVM_MEDIUM)
        `uvm_info(get_type_name(), "body() — sequence complete", UVM_FULL)
    endtask

endclass
