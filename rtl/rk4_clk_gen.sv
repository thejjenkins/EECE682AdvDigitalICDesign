`timescale 1ns / 1ps

module rk4_clk_gen (
    input  wire       en,
    input  wire       rst,
    input  wire [1:0] sel,
    input  wire       mux_in,
    output wire       out
);
    wire osc_out1, osc_out2, osc_out3;
    reg  osc_out;

    rk4_ring_osc Oscillator1 (.enable(en), .osc_out(osc_out1));
    rk4_ring_osc Oscillator2 (.enable(en), .osc_out(osc_out2));
    rk4_ring_osc Oscillator3 (.enable(en), .osc_out(osc_out3));

    always @(*) begin
        case (sel)
            2'b00:   osc_out = osc_out1;
            2'b01:   osc_out = osc_out2;
            2'b10:   osc_out = osc_out3;
            2'b11:   osc_out = mux_in;
            default: osc_out = mux_in;
        endcase
    end

    rk4_clock_divider divider (
        .clk_in  (osc_out),
        .reset   (rst),
        .clk_out (out)
    );
endmodule
