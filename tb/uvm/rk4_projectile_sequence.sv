// Sequence for a single f-engine program load + run with a given v0.
// The test creates multiple instances of this sequence for different
// programs and v0 values.

class rk4_projectile_sequence extends uvm_sequence #(rk4_seq_item);

    `uvm_object_utils(rk4_projectile_sequence)

    bit [15:0] program_mem [16];
    bit        load_program;
    int signed v0_value;

    function new(string name = "rk4_projectile_sequence");
        super.new(name);
        load_program = 1;
        for (int i = 0; i < 16; i++) program_mem[i] = 16'h0000;
    endfunction

    // ---------------------------------------------------------------
    //  Helpers to build f-engine programs
    // ---------------------------------------------------------------

    // Encode a single f-engine instruction
    static function bit [15:0] encode_instr(
        bit [2:0] src_a, bit [2:0] src_b,
        bit [2:0] alu_op, bit [2:0] dest, bit halt
    );
        return {src_a, src_b, alu_op, dest, halt, 3'b000};
    endfunction

    static function void build_projectile_prog(ref bit [15:0] mem [16]);
        // f(t, v0) = v0 - g*t
        // R5 = G_FIXED (pre-loaded by FSM), R7 = time argument
        // Instr 0: MUL R7, R5, R7       → R7 = g * time
        // Instr 1: SUB R7, R0, R7 HALT  → R7 = v0 - g*time
        mem[0] = encode_instr(3'd5, 3'd7, 3'd2, 3'd7, 1'b0);  // 0xBD70
        mem[1] = encode_instr(3'd0, 3'd7, 3'd1, 3'd7, 1'b1);  // 0x1CF8
        for (int i = 2; i < 16; i++) mem[i] = 16'h0000;
    endfunction

    static function void build_const_vel_prog(ref bit [15:0] mem [16]);
        // f(v0) = v0
        // Instr 0: PASS R0 → R7, HALT
        mem[0] = encode_instr(3'd0, 3'd0, 3'd7, 3'd7, 1'b1);  // 0x03F8
        for (int i = 1; i < 16; i++) mem[i] = 16'h0000;
    endfunction

    static function void build_exp_approach_prog(ref bit [15:0] mem [16]);
        // f(v0, y) = v0 - y
        // Instr 0: SUB R7, R0, R6 HALT  → R7 = v0 - y
        mem[0] = encode_instr(3'd0, 3'd6, 3'd1, 3'd7, 1'b1);  // 0x18F8
        for (int i = 1; i < 16; i++) mem[i] = 16'h0000;
    endfunction

    static function void build_abs_half_prog(ref bit [15:0] mem [16]);
        // f(v0) = |v0| >>> 1   — 16-instruction, no halt (pc==15 terminates)
        // Exercises ABS, SHR, and the pc==15 expression coverage path.
        mem[0]  = encode_instr(3'd0, 3'd0, 3'd5, 3'd1, 1'b0);  // ABS R0 -> R1
        mem[1]  = encode_instr(3'd1, 3'd0, 3'd4, 3'd2, 1'b0);  // SHR R1 -> R2
        for (int i = 2; i < 15; i++)
            mem[i] = encode_instr(3'd2, 3'd0, 3'd7, 3'd4, 1'b0);  // PASS R2 -> R4 (padding)
        mem[15] = encode_instr(3'd2, 3'd0, 3'd7, 3'd7, 1'b0);  // PASS R2 -> R7 (no halt)
    endfunction

    static function void build_negate_prog(ref bit [15:0] mem [16]);
        // f(v0) = -v0
        // Instr 0: NEG R0 -> R7 HALT
        mem[0] = encode_instr(3'd0, 3'd0, 3'd6, 3'd7, 1'b1);
        for (int i = 1; i < 16; i++) mem[i] = 16'h0000;
    endfunction

    // ---------------------------------------------------------------
    //  body
    // ---------------------------------------------------------------
    virtual task body();
        rk4_seq_item prog_item, run_item;

        if (load_program) begin
            prog_item = rk4_seq_item::type_id::create("prog_item");
            prog_item.cmd_type = RK4_CMD_LOAD_PROG;
            prog_item.payload  = new[32];

            for (int i = 0; i < 16; i++) begin
                prog_item.payload[i*2]     = program_mem[i][7:0];
                prog_item.payload[i*2 + 1] = program_mem[i][15:8];
            end

            start_item(prog_item);
            finish_item(prog_item);
            `uvm_info(get_type_name(), "LOAD_PROG sent", UVM_MEDIUM)
        end

        run_item = rk4_seq_item::type_id::create("run_item");
        run_item.cmd_type = RK4_CMD_RUN;
        run_item.payload  = new[4];

        run_item.payload[0] = v0_value[7:0];
        run_item.payload[1] = v0_value[15:8];
        run_item.payload[2] = v0_value[23:16];
        run_item.payload[3] = v0_value[31:24];

        start_item(run_item);
        finish_item(run_item);
        `uvm_info(get_type_name(),
            $sformatf("RUN sent (v0 = 0x%08h)", v0_value), UVM_MEDIUM)
    endtask

endclass
