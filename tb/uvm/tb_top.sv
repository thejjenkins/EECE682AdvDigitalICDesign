`timescale 1ns / 1ps

module tb_top;

    import uvm_pkg::*;
    import rk4_tb_pkg::*;

    // ----------------------------------------------------------------
    //  Simulation parameters — small values for fast simulation,
    //  matching the proven direct testbench configuration.
    // ----------------------------------------------------------------
    localparam integer CLK_FREQ  = 1000;
    localparam integer BAUD_RATE = 100;
    localparam integer BAUD_DIV  = CLK_FREQ / BAUD_RATE;  // 10
    localparam integer NUM_DIV   = 100;
    localparam real    CLK_PER   = 1000.0 / CLK_FREQ;     // 1.25 ns

    // ----------------------------------------------------------------
    //  Clock generation
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
    //  DUT — rk4_projectile_top
    // ----------------------------------------------------------------
    rk4_projectile_top #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE),
        .NUM_DIV   (NUM_DIV)
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
        uvm_config_db#(int)::set(null, "*", "baud_div", BAUD_DIV);
        run_test();
    end

    // ----------------------------------------------------------------
    //  Hard timeout safety net
    // ----------------------------------------------------------------
    initial begin
        #10ms;
        `uvm_fatal("TB_TOP", "Global simulation timeout (10 ms)")
    end

    // ----------------------------------------------------------------
    //  Optional waveform dump (uncomment for debug)
    // ----------------------------------------------------------------
    // initial begin
    //     $shm_open("waves.shm");
    //     $shm_probe(tb_top, "ACTF");
    // end

endmodule
