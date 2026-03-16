`timescale 1ns / 1ps

module rk4_top (
    input  wire       clk_100MHz,
    input  wire       en,
    input  wire       rst,
    input  wire [1:0] sel,
    input  wire       uart_rx,
    output wire       uart_tx,
    output wire       clk_1Hz
);

    wire clk_in;

    rk4_clk_gen clock_unit (
        .en     (en),
        .rst    (rst),
        .sel    (sel),
        .mux_in (clk_100MHz),
        .out    (clk_in)
    );

    rk4_projectile_top rk4_core (
        .clk     (clk_in),
        .rst_n   (rst),
        .uart_rx (uart_rx),
        .uart_tx (uart_tx)
    );

    assign clk_1Hz = clk_in;

endmodule
