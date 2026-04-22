`timescale 1ns / 1ps

interface rk4_if (input logic clk);

    logic       rst_n;
    logic       uart_rx;
    logic       uart_tx;

    logic       test_in;
    logic       test_out;

    // JTAG
    logic       tck;
    logic       tms;
    logic       trst_n;
    logic       tdi;
    logic       tdo;

    initial begin
        uart_rx = 1'b1;
        rst_n   = 1'b1;
        test_in = 1'b0;
        tck     = 1'b0;
        tms     = 1'b0;
        trst_n  = 1'b1;
        tdi     = 1'b0;
    end

endinterface
