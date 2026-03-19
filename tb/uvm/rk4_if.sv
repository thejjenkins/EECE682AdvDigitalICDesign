`timescale 1ns / 1ps

interface rk4_if (input logic clk);

    logic       rst_n;
    logic       uart_rx;
    logic       uart_tx;

    initial begin
        uart_rx = 1'b1;
        rst_n   = 1'b1;
    end

endinterface
