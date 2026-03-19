class rk4_alu_coverage_test extends rk4_projectile_test;

    `uvm_component_utils(rk4_alu_coverage_test)

    function new(string name = "rk4_alu_coverage_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this, "rk4_alu_coverage_test");

        apply_reset();

        // -----------------------------------------------------------
        //  Test 1: Abs-half  f(v0) = |v0| >>> 1
        //  Exercises ALU ops ABS (3'b101) and SHR (3'b100)
        // -----------------------------------------------------------
        run_f_test(F_ABS_HALF, "Abs-half", '{
            32'sd65536,    // v0 =  1.0
            -32'sd65536,   // v0 = -1.0 (exercises ABS negative path)
            32'sd655360    // v0 = 10.0
        });

        // -----------------------------------------------------------
        //  Test 2: Negate  f(v0) = -v0
        //  Exercises ALU op NEG (3'b110)
        // -----------------------------------------------------------
        run_f_test(F_NEGATE, "Negate", '{
            32'sd65536,    // v0 =  1.0
            -32'sd65536    // v0 = -1.0
        });

        #1us;
        phase.drop_objection(this, "rk4_alu_coverage_test");
    endtask

endclass
