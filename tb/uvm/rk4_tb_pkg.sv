package rk4_tb_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "rk4_seq_item.sv"
    `include "rk4_base_sequencer.sv"
    `include "rk4_base_driver.sv"
    `include "rk4_base_monitor.sv"
    `include "rk4_base_agent.sv"
    `include "rk4_base_scoreboard.sv"
    `include "rk4_base_env.sv"
    `include "rk4_base_sequence.sv"
    `include "rk4_base_test.sv"

    // Projectile motion test components
    `include "rk4_projectile_scoreboard.sv"
    `include "rk4_projectile_sequence.sv"
    `include "rk4_projectile_test.sv"

    // ALU coverage test (SHR, ABS, NEG)
    `include "rk4_alu_coverage_test.sv"

    // UART error injection test
    `include "rk4_uart_error_test.sv"

    // Clock generation coverage test
    `include "rk4_clk_gen_test.sv"

endpackage
