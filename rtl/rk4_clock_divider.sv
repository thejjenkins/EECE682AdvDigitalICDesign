`timescale 1ns / 1ps

module rk4_clock_divider (
    input  wire clk_in,
    input  wire reset,
    output reg  clk_out
);
    reg [5:0] counter;
    parameter div_count = 6'd49;

    always @(posedge clk_in or negedge reset) begin
        if (!reset) begin
            counter <= 6'd0;
            clk_out <= 1'b0;
        end else if (counter >= div_count) begin
            counter <= 6'd0;
            clk_out <= ~clk_out;
        end else begin
            counter <= counter + 1;
        end
    end
endmodule
