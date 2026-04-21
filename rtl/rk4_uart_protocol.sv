`timescale 1ns / 1ps
// UART command protocol parser.
// Receives bytes from uart_rx and routes them:
//
//   Command 0x01 — Load f-program:
//     Followed by 32 bytes (16 instructions x 2 bytes each, little-endian).
//     Each pair is written to rk4_f_engine instruction memory.
//
//   Command 0x02 — Run:
//     Followed by 4 bytes (v0 in Q16.16, little-endian).
//     Loads v0 into register file and pulses run_start.

module rk4_uart_protocol (
    input  wire        clk,
    input  wire        rst_n,

    // From uart_rx
    input  wire        rx_valid,
    input  wire [7:0]  rx_data,

    // To rk4_f_engine (program load)
    output reg         prog_wr,
    output reg  [3:0]  prog_addr,
    output reg  [15:0] prog_data,

    // To rk4_regfile (v0 load)
    output reg         v0_load,
    output reg  signed [31:0] v0_data,

    // To rk4_control_fsm
    output reg         run_start,

    // Busy flag from FSM (reject run while busy)
    input  wire        fsm_busy,

    output wire [1:0]  pstate_o
);

localparam [7:0] CMD_LOAD_PROG = 8'h01;
localparam [7:0] CMD_RUN       = 8'h02;

localparam [1:0]
    ST_CMD      = 2'd0,
    ST_PROG_LO  = 2'd1,
    ST_PROG_HI  = 2'd2,
    ST_V0_BYTE  = 2'd3;

reg [1:0]  pstate;

assign pstate_o = pstate;

reg [2:0]  byte_cnt;    // counts bytes within a command payload
reg [3:0]  instr_idx;   // which instruction we're loading
reg [7:0]  lo_byte;     // temp for little-endian instruction assembly
reg [31:0] v0_shift;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pstate    <= ST_CMD;
        byte_cnt  <= 3'd0;
        instr_idx <= 4'd0;
        lo_byte   <= 8'd0;
        v0_shift  <= 32'd0;
        prog_wr   <= 1'b0;
        prog_addr <= 4'd0;
        prog_data <= 16'd0;
        v0_load   <= 1'b0;
        v0_data   <= 32'sd0;
        run_start <= 1'b0;
    end else begin
        prog_wr   <= 1'b0;
        v0_load   <= 1'b0;
        run_start <= 1'b0;

        if (rx_valid) begin
            case (pstate)

            ST_CMD: begin
                case (rx_data)
                    CMD_LOAD_PROG: begin
                        pstate    <= ST_PROG_LO;
                        instr_idx <= 4'd0;
                    end
                    CMD_RUN: begin
                        pstate   <= ST_V0_BYTE;
                        byte_cnt <= 3'd0;
                        v0_shift <= 32'd0;
                    end
                    default: ; // ignore unknown commands
                endcase
            end

            // Instruction low byte
            ST_PROG_LO: begin
                lo_byte <= rx_data;
                pstate  <= ST_PROG_HI;
            end

            // Instruction high byte → write to f-engine
            ST_PROG_HI: begin
                prog_wr   <= 1'b1;
                prog_addr <= instr_idx;
                prog_data <= {rx_data, lo_byte};

                if (instr_idx == 4'd15) begin
                    pstate <= ST_CMD;
                end else begin
                    instr_idx <= instr_idx + 4'd1;
                    pstate    <= ST_PROG_LO;
                end
            end

            // v0 bytes (little-endian, 4 bytes)
            ST_V0_BYTE: begin
                case (byte_cnt[1:0])
                    2'd0: v0_shift[ 7: 0] <= rx_data;
                    2'd1: v0_shift[15: 8] <= rx_data;
                    2'd2: v0_shift[23:16] <= rx_data;
                    2'd3: begin
                        v0_shift[31:24] <= rx_data;
                        v0_data   <= {rx_data, v0_shift[23:0]};
                        v0_load   <= 1'b1;
                        if (!fsm_busy)
                            run_start <= 1'b1;
                        pstate <= ST_CMD;
                    end
                endcase
                byte_cnt <= byte_cnt + 3'd1;
            end

            default: pstate <= ST_CMD;

            endcase
        end
    end
end

endmodule
