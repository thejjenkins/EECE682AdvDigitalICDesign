`timescale 1ns / 1ps
// Micro-coded f-function engine.
// Stores a 16-instruction program (16 bits each) loaded via UART.
// When f_start is pulsed, the engine steps the PC through the program
// and drives MUX / ALU / dest signals until it hits a HALT flag or
// reaches the end of the program.
//
// Instruction format (16 bits):
//   [15:13] src_a   — MUX_A operand select (register file or constant)
//   [12:10] src_b   — MUX_B operand select
//   [ 9:7 ] alu_op  — ALU operation
//   [ 6:4 ] dest    — destination register
//   [ 3]    halt    — end-of-program marker
//   [ 2:0 ] (reserved)
//
// Operand encoding (3 bits shared for src_a / src_b):
//   0-7 map to register file R0..R7 when the MSB of the 4-bit
//   mux_sel output is 0.  Constants are selected when src == 3'b1xx
//   via an extended scheme in the top-level wiring (see rk4_projectile_top).
//   To keep this module simple, src_a/src_b are output directly and
//   the parent module maps them to register addresses or constant selects.

module rk4_f_engine (
    input  wire        clk,
    input  wire        rst_n,

    // Program load interface (from UART protocol parser)
    input  wire        prog_wr,
    input  wire [3:0]  prog_addr,
    input  wire [15:0] prog_data,

    // Control handshake
    input  wire        f_start,
    output reg         f_active,
    output reg         f_done,

    // Decoded outputs driving shared datapath
    output reg  [2:0]  src_a,
    output reg  [2:0]  src_b,
    output reg  [2:0]  alu_op,
    output reg  [2:0]  dest,
    output reg         wr_en
);

// Instruction memory: 16 x 16-bit
reg [15:0] imem [0:15];
reg [3:0]  pc;

wire [15:0] cur_instr = imem[pc];

// Decode fields
wire [2:0] dec_src_a  = cur_instr[15:13];
wire [2:0] dec_src_b  = cur_instr[12:10];
wire [2:0] dec_alu_op = cur_instr[9:7];
wire [2:0] dec_dest   = cur_instr[6:4];
wire       dec_halt   = cur_instr[3];

// Program write
integer i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < 16; i = i + 1)
            imem[i] <= 16'd0;
    end else if (prog_wr) begin
        imem[prog_addr] <= prog_data;
    end
end

// Execution FSM
localparam S_IDLE    = 2'd0;
localparam S_EXEC    = 2'd1;
localparam S_WB      = 2'd2;

reg [1:0] estate;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pc       <= 4'd0;
        estate   <= S_IDLE;
        f_active <= 1'b0;
        f_done   <= 1'b0;
        src_a    <= 3'd0;
        src_b    <= 3'd0;
        alu_op   <= 3'd0;
        dest     <= 3'd0;
        wr_en    <= 1'b0;
    end else begin
        f_done <= 1'b0;
        wr_en  <= 1'b0;

        case (estate)
            S_IDLE: begin
                if (f_start) begin
                    pc       <= 4'd0;
                    f_active <= 1'b1;
                    estate   <= S_EXEC;
                end
            end

            // Drive decode outputs for one cycle so ALU computes
            S_EXEC: begin
                src_a  <= dec_src_a;
                src_b  <= dec_src_b;
                alu_op <= dec_alu_op;
                dest   <= dec_dest;
                estate <= S_WB;
            end

            // Write-back: assert wr_en so ALU result is stored, then advance PC
            S_WB: begin
                wr_en <= 1'b1;
                if (dec_halt || pc == 4'd15) begin
                    f_active <= 1'b0;
                    f_done   <= 1'b1;
                    estate   <= S_IDLE;
                end else begin
                    pc     <= pc + 4'd1;
                    estate <= S_EXEC;
                end
            end

            default: estate <= S_IDLE;
        endcase
    end
end

endmodule
