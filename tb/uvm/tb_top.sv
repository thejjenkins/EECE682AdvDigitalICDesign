`timescale 1ns / 1ps

module tb_top;

    import uvm_pkg::*;
    import rk4_tb_pkg::*;

    // ----------------------------------------------------------------
    //  Clock generation — 50 MHz (20 ns period)
    // ----------------------------------------------------------------
    localparam CLK_PERIOD = 20;

    logic clk;
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // ----------------------------------------------------------------
    //  Interface
    // ----------------------------------------------------------------
    rk4_if rk4_vif (.clk(clk));

    // ----------------------------------------------------------------
    //  DUT — rk4_projectile_top
    //
    //  NUM_DIV overridden to 5 so the base test finishes quickly.
    //  Restore to 100 (default) for full-length simulations.
    // ----------------------------------------------------------------
    rk4_projectile_top #(
        .CLK_FREQ  (50_000_000),
        .BAUD_RATE (115_200),
        .NUM_DIV   (5)
    ) dut (
        .clk     (clk),
        .rst_n   (rk4_vif.rst_n),
        .uart_rx (rk4_vif.uart_rx),
        .uart_tx (rk4_vif.uart_tx)
    );

    // ----------------------------------------------------------------
    //  UVM entry point
    // ----------------------------------------------------------------
    initial begin
        uvm_config_db#(virtual rk4_if)::set(null, "*", "rk4_vif", rk4_vif);
        run_test();
    end

    // ----------------------------------------------------------------
    //  Hard timeout safety net
    // ----------------------------------------------------------------
    initial begin
        #100ms;
        `uvm_fatal("TB_TOP", "Global simulation timeout (100 ms)")
    end

    // ----------------------------------------------------------------
    //  Optional waveform dump (uncomment for debug)
    // ----------------------------------------------------------------
    // initial begin
    //     $shm_open("waves.shm");
    //     $shm_probe(tb_top, "ACTF");
    // end

endmodule
