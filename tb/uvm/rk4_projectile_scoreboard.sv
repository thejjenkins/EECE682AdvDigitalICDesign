// Scoreboard with a Q16.16 fixed-point reference model that verifies
// the (t,y) pairs output by the DUT for different f-engine programs.

typedef enum int {
    F_CONST_VEL  = 0,   // f(v0)       = v0
    F_PROJECTILE = 1,   // f(t, v0)    = v0 - g*t
    F_EXP_APPROACH = 2  // f(v0, y)    = v0 - y
} f_func_t;

class rk4_projectile_scoreboard extends rk4_base_scoreboard;

    `uvm_component_utils(rk4_projectile_scoreboard)

    // Hardware parameters (set by the test via configure())
    int signed g_fixed;
    int signed inv6_fixed;
    int signed inv_n_fixed;
    int signed inv_g_fixed;
    int        num_div;

    // Per-run expected output
    int signed exp_t_q[$];
    int signed exp_y_q[$];
    f_func_t   cur_func;
    int signed cur_v0;
    int        run_count;
    int        pair_check_count;
    int        mismatch_count;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        run_count        = 0;
        pair_check_count = 0;
        mismatch_count   = 0;
    endfunction

    function void configure(int signed g, int signed inv6,
                            int signed inv_n, int signed inv_g, int n);
        g_fixed     = g;
        inv6_fixed  = inv6;
        inv_n_fixed = inv_n;
        inv_g_fixed = inv_g;
        num_div     = n;
    endfunction

    // ---------------------------------------------------------------
    //  Q16.16 helpers
    // ---------------------------------------------------------------
    static function int signed qmul(int signed a, int signed b);
        longint full = longint'(a) * longint'(b);
        return int'({full[47:16]});
    endfunction

    // ---------------------------------------------------------------
    //  Compute expected (t,y) pairs for a run
    // ---------------------------------------------------------------
    function void configure_run(f_func_t func, int signed v0);
        int signed dt, dt_half;
        int signed t_val, y_val;
        int signed k1, k2, k3, k4, k_sum, delta_y;
        int        step;

        cur_func = func;
        cur_v0   = v0;

        // Clear queues from any previous run
        exp_t_q.delete();
        exp_y_q.delete();

        // Reset byte accumulation for this run
        rx_bytes.delete();
        done_marker_received = 0;
        data_pair_count      = 0;

        // Replicate the FSM's INIT sequence: dt = qmul(qmul(v0<<1, INV_G), INV_N)
        dt      = qmul(qmul(v0 <<< 1, inv_g_fixed), inv_n_fixed);
        dt_half = dt >>> 1;

        t_val = 0;
        y_val = 0;

        `uvm_info(get_type_name(),
            $sformatf("configure_run: func=%s  v0=0x%08h  dt=0x%08h  dt_half=0x%08h  num_div=%0d",
                func.name(), v0, dt, dt_half, num_div), UVM_MEDIUM)

        for (step = 0; step < num_div; step++) begin
            // Evaluate f for k1..k4
            k1 = eval_f(func, v0, t_val,            y_val);
            k2 = eval_f(func, v0, t_val + dt_half,  y_val);
            k3 = eval_f(func, v0, t_val + dt_half,  y_val);
            k4 = eval_f(func, v0, t_val + dt,       y_val);

            // Hardware update sequence (exact order matters)
            k_sum   = (k2 <<< 1) + k1 + k3 + k3 + k4;
            delta_y = qmul(qmul(k_sum, dt), inv6_fixed);

            y_val = y_val + delta_y;
            t_val = t_val + dt;

            if (y_val[31] || (step + 1) == num_div) begin
                // Termination — no TX pair, just done marker
                `uvm_info(get_type_name(),
                    $sformatf("  step %0d: DONE (y=0x%08h  y_neg=%0b  last_step=%0b)",
                        step, y_val, y_val[31], (step+1)==num_div), UVM_HIGH)
                break;
            end

            exp_t_q.push_back(t_val);
            exp_y_q.push_back(y_val);
            `uvm_info(get_type_name(),
                $sformatf("  step %0d: t=0x%08h  y=0x%08h", step, t_val, y_val), UVM_HIGH)
        end

        run_count++;
        `uvm_info(get_type_name(),
            $sformatf("Expected %0d TX pairs for run #%0d", exp_t_q.size(), run_count),
            UVM_MEDIUM)
    endfunction

    function int signed eval_f(f_func_t func, int signed v0,
                               int signed t_arg, int signed y_arg);
        case (func)
            F_CONST_VEL:    return v0;
            F_PROJECTILE:   return v0 - qmul(g_fixed, t_arg);
            F_EXP_APPROACH: return v0 - y_arg;
            default:        return v0;
        endcase
    endfunction

    // ---------------------------------------------------------------
    //  Override write() to also check pairs against the reference
    // ---------------------------------------------------------------
    virtual function void write(rk4_seq_item item);
        super.write(item);
        check_accumulated_pairs();
    endfunction

    function void check_accumulated_pairs();
        int n_bytes;
        int n_data_bytes;
        int n_pairs_available;
        int signed got_t, got_y, exp_t, exp_y;
        int base;

        n_bytes = rx_bytes.size();
        if (done_marker_received)
            n_data_bytes = n_bytes - 4;
        else
            n_data_bytes = n_bytes;

        n_pairs_available = n_data_bytes / 8;

        while (pair_check_count < n_pairs_available &&
               pair_check_count < exp_t_q.size()) begin

            base = pair_check_count * 8;
            got_t = {rx_bytes[base+3], rx_bytes[base+2],
                     rx_bytes[base+1], rx_bytes[base+0]};
            got_y = {rx_bytes[base+7], rx_bytes[base+6],
                     rx_bytes[base+5], rx_bytes[base+4]};

            exp_t = exp_t_q[pair_check_count];
            exp_y = exp_y_q[pair_check_count];

            if (got_t !== exp_t || got_y !== exp_y) begin
                mismatch_count++;
                `uvm_error(get_type_name(),
                    $sformatf("MISMATCH pair %0d: got(t=0x%08h, y=0x%08h)  exp(t=0x%08h, y=0x%08h)",
                        pair_check_count, got_t, got_y, exp_t, exp_y))
            end else begin
                `uvm_info(get_type_name(),
                    $sformatf("MATCH pair %0d: t=0x%08h  y=0x%08h",
                        pair_check_count, got_t, got_y), UVM_HIGH)
            end
            pair_check_count++;
        end
    endfunction

    function void reset_for_next_run();
        rx_bytes.delete();
        done_marker_received = 0;
        data_pair_count      = 0;
        pair_check_count     = 0;
        exp_t_q.delete();
        exp_y_q.delete();
    endfunction

    // ---------------------------------------------------------------
    //  check_phase: overall pass/fail
    // ---------------------------------------------------------------
    virtual function void check_phase(uvm_phase phase);
        if (mismatch_count == 0 && run_count > 0) begin
            `uvm_info(get_type_name(),
                $sformatf("PASS — %0d runs, all (t,y) pairs matched", run_count), UVM_LOW)
        end else if (run_count == 0) begin
            `uvm_error(get_type_name(), "FAIL — no runs were executed")
        end else begin
            `uvm_error(get_type_name(),
                $sformatf("FAIL — %0d mismatches across %0d runs", mismatch_count, run_count))
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info(get_type_name(),
            $sformatf("Projectile scoreboard: %0d runs, %0d mismatches",
                run_count, mismatch_count), UVM_LOW)
    endfunction

endclass
