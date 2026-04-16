`timescale 1ns / 1ps
// 8 x 32-bit register file with 2 read ports, 1 write port, a dedicated
// v0 load port, and direct outputs for t (R1) and y (R6) used by TX logic.
//
// Register map
//   R0 = v0      R4 = k3
//   R1 = t       R5 = k4
//   R2 = k1      R6 = y
//   R3 = k2      R7 = acc (temporary)

module rk4_regfile (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [2:0]  rd_addr_a,
    output wire signed [31:0] rd_data_a,

    input  wire [2:0]  rd_addr_b,
    output wire signed [31:0] rd_data_b,

    input  wire        wr_en,
    input  wire [2:0]  wr_addr,
    input  wire signed [31:0] wr_data,

    input  wire        v0_load,
    input  wire signed [31:0] v0_data,

    // Direct outputs for TX snapshot (no read-port contention)
    output wire signed [31:0] t_out,
    output wire signed [31:0] y_out,

    // Debug: direct access to all registers for atomic snapshot
    output wire signed [31:0] dbg_reg0_out,
    output wire signed [31:0] dbg_reg1_out,
    output wire signed [31:0] dbg_reg2_out,
    output wire signed [31:0] dbg_reg3_out,
    output wire signed [31:0] dbg_reg4_out,
    output wire signed [31:0] dbg_reg5_out,
    output wire signed [31:0] dbg_reg6_out,
    output wire signed [31:0] dbg_reg7_out
);

reg signed [31:0] regs [0:7];

assign rd_data_a = regs[rd_addr_a];
assign rd_data_b = regs[rd_addr_b];
assign t_out     = regs[1];
assign y_out     = regs[6];

assign dbg_reg0_out = regs[0];
assign dbg_reg1_out = regs[1];
assign dbg_reg2_out = regs[2];
assign dbg_reg3_out = regs[3];
assign dbg_reg4_out = regs[4];
assign dbg_reg5_out = regs[5];
assign dbg_reg6_out = regs[6];
assign dbg_reg7_out = regs[7];

integer i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < 8; i = i + 1)
            regs[i] <= 32'sd0;
    end else begin
        if (v0_load)
            regs[0] <= v0_data;
        if (wr_en)
            regs[wr_addr] <= wr_data;
    end
end

endmodule
