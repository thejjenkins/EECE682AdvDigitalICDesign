`timescale 1ns / 1ps

module tb_top;

    import uvm_pkg::*;
    import rk4_tb_pkg::*;

    // ----------------------------------------------------------------
    //  Simulation parameters
    //  The clock divider (div_count=49) divides by 100.
    //  Internal BAUD_DIV = CLK_FREQ / BAUD_RATE = 1_000_000 / 9_600 = 104.
    //  The driver sees the external clock, so baud_div = 104 * 100 = 10400.
    // ----------------------------------------------------------------
    localparam integer BAUD_DIV_INT = 104;
    localparam integer CLK_DIV     = 100;
    localparam integer BAUD_DIV    = BAUD_DIV_INT * CLK_DIV;
    localparam real    CLK_PER     = 0.01;   // 10 ps external clock

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
    //  DUT — rk4_top (full chip with clock generation)
    // ----------------------------------------------------------------
    rk4_top dut (
        .clk_100MHz (clk),
        .en         (rk4_vif.en),
        .rst        (rk4_vif.rst_n),
        .sel        (rk4_vif.sel),
        .uart_rx    (rk4_vif.uart_rx),
        .uart_tx    (rk4_vif.uart_tx),
        .clk_1Hz    ()
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
        #50ms;
        `uvm_fatal("TB_TOP", "Global simulation timeout (50 ms)")
    end

    // ----------------------------------------------------------------
    //  Optional waveform dump (uncomment for debug)
    // ----------------------------------------------------------------
    // initial begin
    //     $shm_open("waves.shm");
    //     $shm_probe(tb_top, "ACTF");
    // end

endmodule
