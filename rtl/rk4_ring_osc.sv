`timescale 1ns / 1ps

module rk4_ring_osc (
    input  wire enable,
    output wire osc_out
);
    wire w0, w1, w2, w3, w4;

    nand #1 (w0, enable, w4);

    not  #1 (w1, w0);
    not  #1 (w2, w1);
    not  #1 (w3, w2);
    not  #1 (w4, w3);

    assign osc_out = w0;
endmodule
