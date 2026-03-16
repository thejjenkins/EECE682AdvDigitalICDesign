`timescale 1ns / 1ps

module uart_rx #(
    parameter integer BAUD_DIV = 434
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg        rx_valid,
    output reg  [7:0] rx_data
);

reg rx_s1, rx_sync;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin 
        rx_s1 <= 1'b1; 
        rx_sync <= 1'b1; 
    end else begin 
        rx_s1 <= rx;   
        rx_sync <= rx_s1; 
    end
end

localparam integer HALF_DIV = BAUD_DIV / 2;

reg [$clog2(BAUD_DIV+1)-1:0] baud_cnt;
reg [3:0]  bit_cnt;
reg [7:0]  shift_reg;
reg        active;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        baud_cnt  <= '0;
        bit_cnt   <= 4'd0;
        shift_reg <= 8'd0;
        active    <= 1'b0;
        rx_valid  <= 1'b0;
        rx_data   <= 8'd0;
    end else begin
        rx_valid <= 1'b0;

        if (!active) begin
            if (!rx_sync) begin
                active   <= 1'b1;
                baud_cnt <= HALF_DIV[$clog2(BAUD_DIV+1)-1:0];
                bit_cnt  <= 4'd0;
            end
        end else begin
            if (baud_cnt == '0) begin
                baud_cnt <= BAUD_DIV[$clog2(BAUD_DIV+1)-1:0] - 1;
                case (bit_cnt)
                    4'd0: begin
                        if (rx_sync) active <= 1'b0;
                        else         bit_cnt <= 4'd1;
                    end
                    4'd1,4'd2,4'd3,4'd4,
                    4'd5,4'd6,4'd7,4'd8: begin
                        shift_reg <= {rx_sync, shift_reg[7:1]};
                        bit_cnt   <= bit_cnt + 4'd1;
                    end
                    4'd9: begin
                        if (rx_sync) begin
                            rx_data  <= shift_reg;
                            rx_valid <= 1'b1;
                        end
                        active  <= 1'b0;
                        bit_cnt <= 4'd0;
                    end
                    default: active <= 1'b0;
                endcase
            end else begin
                baud_cnt <= baud_cnt - 1;
            end
        end
    end
end

endmodule
