class rk4_projectile_test extends rk4_base_test;

    `uvm_component_utils(rk4_projectile_test)

    rk4_projectile_scoreboard proj_scb;

    // Hardware constants (must match tb_top / DUT defaults)
    localparam int signed G_FIXED     = 32'sd642252;
    localparam int signed INV6_FIXED  = 32'sd10922;
    localparam int signed INV_N_FIXED = 32'sd655;
    localparam int signed INV_G_FIXED = 32'sd6694;
    localparam int        NUM_DIV     = 100;

    function new(string name = "rk4_projectile_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        // Override the scoreboard type before super.build_phase creates the env
        set_type_override_by_type(
            rk4_base_scoreboard::get_type(),
            rk4_projectile_scoreboard::get_type()
        );
        super.build_phase(phase);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // Get a handle to the projectile scoreboard
        if (!$cast(proj_scb, env.scb))
            `uvm_fatal(get_type_name(), "Failed to cast scoreboard to rk4_projectile_scoreboard")
        proj_scb.configure(G_FIXED, INV6_FIXED, INV_N_FIXED, INV_G_FIXED, NUM_DIV);
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this, "rk4_projectile_test");

        apply_reset();

        check_inverter();

        // -----------------------------------------------------------
        //  Test 1: Projectile motion  f(t, v0) = v0 - g*t
        // -----------------------------------------------------------
        run_f_test(F_PROJECTILE, "Projectile motion", '{
            32'sd65536,    // v0 = 1.0   → y_max ≈ 0.05
            32'sd655360,   // v0 = 10.0  → y_max ≈ 5.1      (bits ~18)
            32'sd6553600,  // v0 = 100.0 → y_max ≈ 510       (bits ~24)
            32'sd32768000, // v0 = 500.0 → y_max ≈ 12755     (bits ~29)
            32'sd52428800  // v0 = 800.0 → y_max ≈ 32653     (bits ~30)
        });

        // -----------------------------------------------------------
        //  Test 2: Constant velocity  f(v0) = v0
        // -----------------------------------------------------------
        run_f_test(F_CONST_VEL, "Constant velocity", '{
            32'sd65536,    // v0 = 1.0
            32'sd32768,    // v0 = 0.5
            32'sh0000AAAA, // v0 ≈ 0.667 — toggles odd fractional bits
            32'sh00055555, // v0 ≈ 5.333 — toggles even bits
            32'sh0000FFFF, // v0 ≈ 0.99998 — all fractional bits set
            32'sh7FFF0000, // v0 = 32767.0 — toggles v0_data bits [16..30]
            -32'sd65536    // v0 = -1.0 (0xFFFF0000) — toggles v0_data bit [31]
        });

        // -----------------------------------------------------------
        //  Test 3: Exponential approach  f(v0, y) = v0 - y
        // -----------------------------------------------------------
        run_f_test(F_EXP_APPROACH, "Exponential approach", '{
            32'sd65536,    // v0 = 1.0
            32'sd131072,   // v0 = 2.0
            32'sd262144    // v0 = 4.0
        });

        #1us;
        phase.drop_objection(this, "rk4_projectile_test");
    endtask

    // ---------------------------------------------------------------
    //  Run one f-function with multiple v0 values
    // ---------------------------------------------------------------
    virtual task run_f_test(f_func_t func, string label, int signed v0_list[$]);
        rk4_projectile_sequence seq;
        bit [15:0] prog [16];
        bit first_v0;

        `uvm_info(get_type_name(),
            $sformatf("=== %s: %0d v0 values ===", label, v0_list.size()), UVM_LOW)

        // Build the program for this function
        case (func)
            F_PROJECTILE:   rk4_projectile_sequence::build_projectile_prog(prog);
            F_CONST_VEL:    rk4_projectile_sequence::build_const_vel_prog(prog);
            F_EXP_APPROACH: rk4_projectile_sequence::build_exp_approach_prog(prog);
            F_ABS_HALF:     rk4_projectile_sequence::build_abs_half_prog(prog);
            F_NEGATE:       rk4_projectile_sequence::build_negate_prog(prog);
        endcase

        first_v0 = 1;
        foreach (v0_list[i]) begin
            `uvm_info(get_type_name(),
                $sformatf("  Running %s with v0 = 0x%08h (%0d)",
                    label, v0_list[i], v0_list[i]), UVM_MEDIUM)

            // Tell scoreboard what to expect
            proj_scb.configure_run(func, v0_list[i]);

            // Create and start sequence
            seq = rk4_projectile_sequence::type_id::create("seq");
            seq.load_program = first_v0;   // only load program on first v0
            for (int j = 0; j < 16; j++) seq.program_mem[j] = prog[j];
            seq.v0_value = v0_list[i];
            seq.start(env.agent.sqr);

            // Wait for done marker
            wait_for_done_or_timeout(v0_list[i]);

            first_v0 = 0;
        end
    endtask

    virtual task wait_for_done_or_timeout(int signed v0);
        fork
            begin
                wait (proj_scb.done_marker_received);
                `uvm_info(get_type_name(),
                    $sformatf("  Done marker received for v0=0x%08h (bytes=%0d)",
                        v0, proj_scb.rx_bytes.size()), UVM_MEDIUM)
            end
            begin
                #1500ms;
                `uvm_error(get_type_name(),
                    $sformatf("  TIMEOUT for v0=0x%08h (bytes=%0d)",
                        v0, proj_scb.rx_bytes.size()))
            end
        join_any
        disable fork;

        // Let any remaining bytes drain
        #10us;

        // Final pair check
        proj_scb.check_accumulated_pairs();
        proj_scb.reset_for_next_run();
    endtask

endclass
