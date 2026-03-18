`timescale 1ns / 1ps
// rk4_projectile_top.sv — Redesigned with programmable f-function
//
// UART RX → Protocol Parser → { Register File, ALU, f-Engine, Control FSM } → UART TX
//
// Target:  TSMC 180 nm       Format: Q16.16 signed fixed-point

module rk4_projectile_top #(
    parameter integer CLK_FREQ  = 50_000_000,
    parameter integer BAUD_RATE = 115_200,
    parameter integer NUM_DIV   = 100,
    parameter signed [31:0] G_FIXED     = 32'sd642252,
    parameter signed [31:0] INV6_FIXED  = 32'sd10922,
    parameter signed [31:0] INV_N_FIXED = 32'sd655,
    parameter signed [31:0] INV_G_FIXED = 32'sd6694
) (
    input  wire clk,
    input  wire rst_n,
    input  wire uart_rx,
    output wire uart_tx
);

localparam integer BAUD_DIV = CLK_FREQ / BAUD_RATE;

// =====================================================================
//  UART RX
// =====================================================================
wire       rx_valid;
wire [7:0] rx_data;

uart_rx #(.BAUD_DIV(BAUD_DIV)) u_rx (
    .clk(clk), .rst_n(rst_n),
    .rx(uart_rx), .rx_valid(rx_valid), .rx_data(rx_data)
);

// =====================================================================
//  UART TX
// =====================================================================
wire       tx_ready;
reg        tx_valid;
reg  [7:0] tx_byte;

uart_tx #(.BAUD_DIV(BAUD_DIV)) u_tx (
    .clk(clk), .rst_n(rst_n),
    .tx_valid(tx_valid), .tx_data(tx_byte),
    .tx_ready(tx_ready), .tx(uart_tx)
);

// =====================================================================
//  Protocol Parser
// =====================================================================
wire        prog_wr;
wire [3:0]  prog_addr;
wire [15:0] prog_data;
wire        v0_load;
wire signed [31:0] v0_data;
wire        run_start;
wire        fsm_busy;

rk4_uart_protocol u_proto (
    .clk(clk), .rst_n(rst_n),
    .rx_valid(rx_valid), .rx_data(rx_data),
    .prog_wr(prog_wr), .prog_addr(prog_addr), .prog_data(prog_data),
    .v0_load(v0_load), .v0_data(v0_data),
    .run_start(run_start), .fsm_busy(fsm_busy)
);

// =====================================================================
//  Register File
// =====================================================================
wire [2:0]         rf_rd_addr_a, rf_rd_addr_b;
wire signed [31:0] rf_rd_data_a, rf_rd_data_b;
wire               rf_wr_en;
wire [2:0]         rf_wr_addr;
wire signed [31:0] rf_wr_data;
wire signed [31:0] rf_t_out, rf_y_out;

rk4_regfile u_regfile (
    .clk(clk), .rst_n(rst_n),
    .rd_addr_a(rf_rd_addr_a), .rd_data_a(rf_rd_data_a),
    .rd_addr_b(rf_rd_addr_b), .rd_data_b(rf_rd_data_b),
    .wr_en(rf_wr_en), .wr_addr(rf_wr_addr), .wr_data(rf_wr_data),
    .v0_load(v0_load), .v0_data(v0_data),
    .t_out(rf_t_out), .y_out(rf_y_out)
);

// =====================================================================
//  ALU
// =====================================================================
wire signed [31:0] alu_a, alu_b, alu_result;
wire [2:0]         alu_op;

rk4_alu u_alu (
    .op_a(alu_a), .op_b(alu_b), .alu_op(alu_op), .result(alu_result)
);

// =====================================================================
//  f-Engine
// =====================================================================
wire        f_start, f_active, f_done;
wire [2:0]  fe_src_a, fe_src_b, fe_alu_op, fe_dest;
wire        fe_wr_en;

rk4_f_engine u_fengine (
    .clk(clk), .rst_n(rst_n),
    .prog_wr(prog_wr), .prog_addr(prog_addr), .prog_data(prog_data),
    .f_start(f_start), .f_active(f_active), .f_done(f_done),
    .src_a(fe_src_a), .src_b(fe_src_b), .alu_op(fe_alu_op),
    .dest(fe_dest), .wr_en(fe_wr_en)
);

// =====================================================================
//  Control FSM
// =====================================================================
wire [3:0]  fsm_mux_a, fsm_mux_b;
wire [2:0]  fsm_alu_op, fsm_wr_addr;
wire        fsm_wr_en, fsm_latch_dt;
wire [2:0]  fsm_f_dest_k;
wire        fsm_tx_pair, fsm_tx_done_marker;
wire [6:0]  fsm_step_cnt;
reg         tx_pair_sent;

rk4_control_fsm #(.NUM_DIV(NUM_DIV)) u_fsm (
    .clk(clk), .rst_n(rst_n),
    .run_start(run_start),
    .f_start(f_start), .f_done(f_done), .f_active(f_active),
    .f_dest_k(fsm_f_dest_k),
    .mux_a_sel(fsm_mux_a), .mux_b_sel(fsm_mux_b),
    .alu_op(fsm_alu_op), .wr_addr(fsm_wr_addr), .wr_en(fsm_wr_en),
    .latch_dt(fsm_latch_dt),
    .y_negative(rf_y_out[31]),
    .tx_send_pair(fsm_tx_pair), .tx_send_done_marker(fsm_tx_done_marker),
    .tx_pair_sent(tx_pair_sent),
    .step_cnt(fsm_step_cnt),
    .busy(fsm_busy)
);

// =====================================================================
//  dt / dt_half Latch
// =====================================================================
reg signed [31:0] dt_reg, dt_half_reg;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dt_reg      <= 32'sd0;
        dt_half_reg <= 32'sd0;
    end else if (fsm_latch_dt) begin
        dt_reg      <= alu_result;
        dt_half_reg <= alu_result >>> 1;
    end
end

// =====================================================================
//  Control MUX: f-engine vs FSM → datapath
// =====================================================================
wire [3:0] sel_a = f_active ? {1'b0, fe_src_a} : fsm_mux_a;
wire [3:0] sel_b = f_active ? {1'b0, fe_src_b} : fsm_mux_b;

assign alu_op     = f_active ? fe_alu_op  : fsm_alu_op;
assign rf_wr_addr = f_active ? fe_dest    : fsm_wr_addr;
assign rf_wr_en   = f_active ? fe_wr_en   : fsm_wr_en;
assign rf_wr_data = alu_result;

// =====================================================================
//  Source MUXes (register or constant)
// =====================================================================
assign rf_rd_addr_a = sel_a[2:0];
assign rf_rd_addr_b = sel_b[2:0];

reg signed [31:0] const_a, const_b;

always @(*) begin
    case (sel_a[2:0])
        3'd0: const_a = G_FIXED;
        3'd1: const_a = INV6_FIXED;
        3'd2: const_a = INV_N_FIXED;
        3'd3: const_a = INV_G_FIXED;
        3'd4: const_a = 32'sd0;
        3'd5: const_a = 32'sd0;
        3'd6: const_a = dt_reg;
        3'd7: const_a = dt_half_reg;
    endcase
end

always @(*) begin
    case (sel_b[2:0])
        3'd0: const_b = G_FIXED;
        3'd1: const_b = INV6_FIXED;
        3'd2: const_b = INV_N_FIXED;
        3'd3: const_b = INV_G_FIXED;
        3'd4: const_b = 32'sd0;
        3'd5: const_b = 32'sd0;
        3'd6: const_b = dt_reg;
        3'd7: const_b = dt_half_reg;
    endcase
end

assign alu_a = sel_a[3] ? const_a : rf_rd_data_a;
assign alu_b = sel_b[3] ? const_b : rf_rd_data_b;

// =====================================================================
//  TX Shift-Out Logic
// =====================================================================
reg [63:0] tx_shift;
reg [3:0]  tx_bytes_left;
reg [1:0]  tx_mode;
reg        tx_pending;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_shift      <= 64'd0;
        tx_bytes_left <= 4'd0;
        tx_valid      <= 1'b0;
        tx_byte       <= 8'd0;
        tx_pair_sent  <= 1'b0;
        tx_mode       <= 2'd0;
        tx_pending    <= 1'b0;
    end else begin
        tx_valid     <= 1'b0;
        tx_pair_sent <= 1'b0;

        if (tx_pending && !tx_ready)
            tx_pending <= 1'b0;

        case (tx_mode)
        2'd0: begin
            tx_pending <= 1'b0;
            if (fsm_tx_pair) begin
                tx_shift <= {rf_y_out[31:24], rf_y_out[23:16],
                             rf_y_out[15:8],  rf_y_out[7:0],
                             rf_t_out[31:24], rf_t_out[23:16],
                             rf_t_out[15:8],  rf_t_out[7:0]};
                tx_bytes_left <= 4'd8;
                tx_mode       <= 2'd1;
            end else if (fsm_tx_done_marker) begin
                tx_shift      <= {32'd0, 8'hDE, 8'hAD, 8'hBE, 8'hEF};
                tx_bytes_left <= 4'd4;
                tx_mode       <= 2'd2;
            end
        end

        2'd1, 2'd2: begin
            if (tx_bytes_left == 4'd0) begin
                tx_pair_sent <= 1'b1;
                tx_mode      <= 2'd0;
            end else if (tx_ready && !tx_pending) begin
                tx_byte       <= tx_shift[7:0];
                tx_valid      <= 1'b1;
                tx_shift      <= {8'd0, tx_shift[63:8]};
                tx_bytes_left <= tx_bytes_left - 4'd1;
                tx_pending    <= 1'b1;
            end
        end

        default: tx_mode <= 2'd0;
        endcase
    end
end

endmodule
