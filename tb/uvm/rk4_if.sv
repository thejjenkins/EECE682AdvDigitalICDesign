`timescale 1ns / 1ps

interface rk4_if (input logic clk);

    logic       rst_n;
    logic       uart_rx;
    logic       uart_tx;
    logic       en;
    logic [1:0] sel;

    initial begin
        uart_rx = 1'b1;
        rst_n   = 1'b1;
        en      = 1'b1;
        sel     = 2'b11;
    end

endinterface
