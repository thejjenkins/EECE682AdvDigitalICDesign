`timescale 1ns / 1ps

module rk4_top (
    input  wire       clk_100MHz,
    input  wire       en,
    input  wire       rst,
    input  wire [1:0] sel,
    input  wire       uart_rx,
    output wire       uart_tx,
    output wire       clk_1Hz,
    // JTAG interface
    input  wire       tck,
    input  wire       tms,
    input  wire       trst_n,
    input  wire       tdi,
    output wire       tdo,
    output wire       tdo_oe,
    // Simple test of inverter
    input  wire       test_in,
    output wire       test_out
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

    // Simple test to verify that our chip is receiving power
    inverter power_test(
      .test_in(test_in),
      .test_out(test_out)
    );

    // Scan chain signals driven by the JTAG TAP.
    // Genus connects its inserted scan chain to these wires during DFT synthesis.
    wire scan_enable, scan_in, scan_out;
    assign scan_out = 1'b0;

    jtag_tap u_jtag_tap (
        .tck_i         (tck),
        .tms_i         (tms),
        .trst_ni       (trst_n),
        .tdi_i         (tdi),
        .tdo_o         (tdo),
        .tdo_oe_o      (tdo_oe),
        .scan_enable_o (scan_enable),
        .scan_in_o     (scan_in),
        .scan_out_i    (scan_out)
    );

    assign clk_1Hz = clk_in;

endmodule
