`timescale 1ns / 1ps

module tb_top;

    import uvm_pkg::*;
    import rk4_tb_pkg::*;

    // ----------------------------------------------------------------
    //  Simulation parameters
    //  rk4_projectile_top uses CLK_FREQ=10 MHz, BAUD_RATE=9600
    //  => internal BAUD_DIV = 10_000_000 / 9_600 = 1041
    //  The testbench clock matches CLK_FREQ directly (no clock divider).
    // ----------------------------------------------------------------
    localparam integer BAUD_DIV    = 1041;
    localparam real    CLK_PER     = 100.0;  // 100 ns -> 10 MHz

    // ----------------------------------------------------------------
    //  Clock generation (system clock)
    // ----------------------------------------------------------------
    logic clk;
    initial begin
        clk = 1'b0;
        forever #(CLK_PER / 2.0) clk = ~clk;
    end

    // ----------------------------------------------------------------
    //  Interface
    // ----------------------------------------------------------------
    rk4_if rk4_vif (.clk(clk));

    // ----------------------------------------------------------------
    //  DUT — rk4_projectile_top (digital core, no clock divider)
    // ----------------------------------------------------------------
    rk4_projectile_top dut (
        .clk        (clk),
        .rst_n      (rk4_vif.rst_n),
        .uart_rx    (rk4_vif.uart_rx),
        .uart_tx    (rk4_vif.uart_tx),
        .test_in    (rk4_vif.test_in),
        .test_out   (rk4_vif.test_out),
        .tck        (rk4_vif.tck),
        .tms        (rk4_vif.tms),
        .trst_n     (rk4_vif.trst_n),
        .tdi        (rk4_vif.tdi),
        .tdo        (rk4_vif.tdo)
    );

    // ----------------------------------------------------------------
    //  UVM entry point
    // ----------------------------------------------------------------
    initial begin
        uvm_config_db#(virtual rk4_if)::set(null, "*", "rk4_vif", rk4_vif);
        uvm_config_db#(int)::set(null, "*", "baud_div", BAUD_DIV);
        run_test();
    end

    // ----------------------------------------------------------------
    //  Hard timeout safety net
    // ----------------------------------------------------------------
    initial begin
        #60000ms;
        `uvm_fatal("TB_TOP", "Global simulation timeout (60 s)")
    end

    // ----------------------------------------------------------------
    //  Optional waveform dump (uncomment for debug)
    // ----------------------------------------------------------------
    // initial begin
    //     $shm_open("waves.shm");
    //     $shm_probe(tb_top, "ACTF");
    // end

endmodule
