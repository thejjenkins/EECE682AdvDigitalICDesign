`timescale 1ns / 1ps
// RK4 control FSM.
// Sequences the RK4 algorithm through the shared datapath and delegates
// f(t,y,v0) evaluation to the micro-coded f-engine.
//
// Register map (rk4_regfile):
//   R0=v0  R1=t  R2=k1  R3=k2  R4=k3  R5=k4  R6=y  R7=acc
//
// The MUX source select is 4 bits: {is_const, index[2:0]}
//   is_const=0 → register file R[index]
//   is_const=1 → constant from table:
//     0 = G_FIXED     3 = INV_G_FIXED   6 = dt_reg
//     1 = INV6_FIXED  4 = ZERO          7 = dt_half_reg
//     2 = INV_N_FIXED 5 = (reserved)

module rk4_control_fsm #(
    parameter integer NUM_DIV = 100
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        run_start,

    // f-engine handshake
    output reg         f_start,
    input  wire        f_done,
    input  wire        f_active,
    output reg  [2:0]  f_dest_k,

    // Datapath control (active when f_active == 0)
    output reg  [3:0]  mux_a_sel,
    output reg  [3:0]  mux_b_sel,
    output reg  [2:0]  alu_op,
    output reg  [2:0]  wr_addr,
    output reg         wr_en,

    // dt latch interface — parent stores these when ACC is written
    output reg         latch_dt,

    // y-negative check (parent reads regfile R6[31])
    input  wire        y_negative,

    // TX interface
    output reg         tx_send_pair,
    output reg         tx_send_done_marker,
    input  wire        tx_pair_sent,

    output reg  [6:0]  step_cnt,
    output reg         busy
);

// ALU op encodings
localparam OP_ADD  = 3'd0;
localparam OP_SUB  = 3'd1;
localparam OP_MUL  = 3'd2;
localparam OP_SHL  = 3'd3;
localparam OP_SHR  = 3'd4;
localparam OP_ABS  = 3'd5;
localparam OP_NEG  = 3'd6;
localparam OP_PASS = 3'd7;

// Register addresses
localparam R_V0  = 3'd0, R_T   = 3'd1, R_K1  = 3'd2, R_K2  = 3'd3,
           R_K3  = 3'd4, R_K4  = 3'd5, R_Y   = 3'd6, R_ACC = 3'd7;

// MUX selects: register
`define REG(r)  {1'b0, r}
// MUX selects: constant
localparam C_G      = 4'b1_000, C_INV6  = 4'b1_001, C_INV_N = 4'b1_010,
           C_INV_G  = 4'b1_011, C_ZERO  = 4'b1_100, C_DT    = 4'b1_110,
           C_DTHALF = 4'b1_111;

// States
localparam [5:0]
    S_IDLE       = 6'd0,
    S_INIT1      = 6'd1,   // acc = v0 <<< 1
    S_INIT2      = 6'd2,   // acc = qmul(acc, INV_G)
    S_INIT3      = 6'd3,   // acc = qmul(acc, INV_N)  → dt; latch dt
    S_INIT4      = 6'd4,   // clear t=0
    S_INIT5      = 6'd5,   // clear y=0
    S_PRELOAD_G  = 6'd6,   // R5 ← G_FIXED (for f-engine access)
    S_PRELOAD_T  = 6'd7,   // R7 ← t (K1 time argument)
    S_K1_START   = 6'd8,
    S_K1_WAIT    = 6'd9,
    S_K1_STORE   = 6'd10,  // R2(k1) ← R7(acc)
    S_K2_PREP    = 6'd11,  // acc = t + dt_half
    S_K2_START   = 6'd12,
    S_K2_WAIT    = 6'd13,
    S_K2_STORE   = 6'd14,  // R3(k2) ← R7(acc)
    S_K3_PREP    = 6'd15,  // acc = t + dt_half
    S_K3_START   = 6'd16,
    S_K3_WAIT    = 6'd17,
    S_K3_STORE   = 6'd18,  // R4(k3) ← R7(acc)
    S_K4_PREP    = 6'd19,  // acc = t + dt
    S_K4_START   = 6'd20,
    S_K4_WAIT    = 6'd21,
    S_K4_STORE   = 6'd22,  // R5(k4) ← R7(acc)
    S_UPD1       = 6'd23,  // acc = k2 <<< 1
    S_UPD2       = 6'd24,  // acc += k1
    S_UPD3       = 6'd25,  // acc += k3
    S_UPD4       = 6'd26,  // acc += k3   → k1+2k2+2k3
    S_UPD5       = 6'd27,  // acc += k4   → k_sum
    S_UPD6       = 6'd28,  // acc = qmul(acc, dt)
    S_UPD7       = 6'd29,  // acc = qmul(acc, inv6)
    S_UPD8       = 6'd30,  // y += acc
    S_UPD_T      = 6'd31,  // t += dt; step_cnt++
    S_CHECK      = 6'd32,
    S_TX_PREP    = 6'd33,
    S_TX_WAIT    = 6'd34,
    S_DONE_MARK  = 6'd35,
    S_DONE_WAIT  = 6'd36;

reg [5:0] state;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state            <= S_IDLE;
        mux_a_sel        <= 4'd0;
        mux_b_sel        <= 4'd0;
        alu_op           <= OP_PASS;
        wr_addr          <= 3'd0;
        wr_en            <= 1'b0;
        f_start          <= 1'b0;
        f_dest_k         <= R_K1;
        latch_dt         <= 1'b0;
        tx_send_pair     <= 1'b0;
        tx_send_done_marker <= 1'b0;
        step_cnt         <= 7'd0;
        busy             <= 1'b0;
    end else begin
        wr_en            <= 1'b0;
        f_start          <= 1'b0;
        latch_dt         <= 1'b0;
        tx_send_pair     <= 1'b0;
        tx_send_done_marker <= 1'b0;

        case (state)

        S_IDLE: begin
            busy <= 1'b0;
            if (run_start) begin
                busy  <= 1'b1;
                state <= S_INIT1;
            end
        end

        // acc = v0 <<< 1
        S_INIT1: begin
            mux_a_sel <= `REG(R_V0);
            alu_op    <= OP_SHL;
            wr_addr   <= R_ACC;
            wr_en     <= 1'b1;
            state     <= S_INIT2;
        end

        // acc = qmul(acc, INV_G)
        S_INIT2: begin
            mux_a_sel <= `REG(R_ACC);
            mux_b_sel <= C_INV_G;
            alu_op    <= OP_MUL;
            wr_addr   <= R_ACC;
            wr_en     <= 1'b1;
            state     <= S_INIT3;
        end

        // acc = qmul(acc, INV_N) → dt; latch dt (takes effect next cycle
        // when ALU still outputs the MUL result from this cycle's settings)
        S_INIT3: begin
            mux_a_sel <= `REG(R_ACC);
            mux_b_sel <= C_INV_N;
            alu_op    <= OP_MUL;
            wr_addr   <= R_ACC;
            wr_en     <= 1'b1;
            latch_dt  <= 1'b1;
            state     <= S_INIT4;
        end

        // Write 0 → t
        S_INIT4: begin
            mux_a_sel <= C_ZERO;
            alu_op    <= OP_PASS;
            wr_addr   <= R_T;
            wr_en     <= 1'b1;
            step_cnt  <= 7'd0;
            state     <= S_INIT5;
        end

        // Write 0 → y
        S_INIT5: begin
            mux_a_sel <= C_ZERO;
            alu_op    <= OP_PASS;
            wr_addr   <= R_Y;
            wr_en     <= 1'b1;
            state     <= S_PRELOAD_G;
        end

        // Pre-load G_FIXED into R5 so the f-engine program can access it
        S_PRELOAD_G: begin
            mux_a_sel <= C_G;
            alu_op    <= OP_PASS;
            wr_addr   <= R_K4;
            wr_en     <= 1'b1;
            state     <= S_PRELOAD_T;
        end

        // Copy current t into R7 (time argument for K1)
        S_PRELOAD_T: begin
            mux_a_sel <= `REG(R_T);
            alu_op    <= OP_PASS;
            wr_addr   <= R_ACC;
            wr_en     <= 1'b1;
            state     <= S_K1_START;
        end

        // --- K1: f(t, y, v0) → k1 ---
        S_K1_START: begin
            f_dest_k <= R_K1;
            f_start  <= 1'b1;
            state    <= S_K1_WAIT;
        end
        S_K1_WAIT: if (f_done) state <= S_K1_STORE;

        // Store f-engine result (R7) into k1 register (R2)
        S_K1_STORE: begin
            mux_a_sel <= `REG(R_ACC);
            alu_op    <= OP_PASS;
            wr_addr   <= R_K1;
            wr_en     <= 1'b1;
            state     <= S_K2_PREP;
        end

        // --- K2 prep: acc = t + dt_half ---
        S_K2_PREP: begin
            mux_a_sel <= `REG(R_T);
            mux_b_sel <= C_DTHALF;
            alu_op    <= OP_ADD;
            wr_addr   <= R_ACC;
            wr_en     <= 1'b1;
            state     <= S_K2_START;
        end
        S_K2_START: begin
            f_dest_k <= R_K2;
            f_start  <= 1'b1;
            state    <= S_K2_WAIT;
        end
        S_K2_WAIT: if (f_done) state <= S_K2_STORE;

        // Store f-engine result into k2 register (R3)
        S_K2_STORE: begin
            mux_a_sel <= `REG(R_ACC);
            alu_op    <= OP_PASS;
            wr_addr   <= R_K2;
            wr_en     <= 1'b1;
            state     <= S_K3_PREP;
        end

        // --- K3 prep: acc = t + dt_half ---
        S_K3_PREP: begin
            mux_a_sel <= `REG(R_T);
            mux_b_sel <= C_DTHALF;
            alu_op    <= OP_ADD;
            wr_addr   <= R_ACC;
            wr_en     <= 1'b1;
            state     <= S_K3_START;
        end
        S_K3_START: begin
            f_dest_k <= R_K3;
            f_start  <= 1'b1;
            state    <= S_K3_WAIT;
        end
        S_K3_WAIT: if (f_done) state <= S_K3_STORE;

        // Store f-engine result into k3 register (R4)
        S_K3_STORE: begin
            mux_a_sel <= `REG(R_ACC);
            alu_op    <= OP_PASS;
            wr_addr   <= R_K3;
            wr_en     <= 1'b1;
            state     <= S_K4_PREP;
        end

        // --- K4 prep: acc = t + dt ---
        S_K4_PREP: begin
            mux_a_sel <= `REG(R_T);
            mux_b_sel <= C_DT;
            alu_op    <= OP_ADD;
            wr_addr   <= R_ACC;
            wr_en     <= 1'b1;
            state     <= S_K4_START;
        end
        S_K4_START: begin
            f_dest_k <= R_K4;
            f_start  <= 1'b1;
            state    <= S_K4_WAIT;
        end
        S_K4_WAIT: if (f_done) state <= S_K4_STORE;

        // Store f-engine result into k4 register (R5)
        S_K4_STORE: begin
            mux_a_sel <= `REG(R_ACC);
            alu_op    <= OP_PASS;
            wr_addr   <= R_K4;
            wr_en     <= 1'b1;
            state     <= S_UPD1;
        end

        // --- UPDATE: y += dt/6 * (k1 + 2k2 + 2k3 + k4) ---
        // UPD1: acc = k2 <<< 1
        S_UPD1: begin
            mux_a_sel <= `REG(R_K2);
            alu_op    <= OP_SHL;
            wr_addr   <= R_ACC;
            wr_en     <= 1'b1;
            state     <= S_UPD2;
        end
        // UPD2: acc = acc + k1
        S_UPD2: begin
            mux_a_sel <= `REG(R_ACC);
            mux_b_sel <= `REG(R_K1);
            alu_op    <= OP_ADD;
            wr_addr   <= R_ACC;
            wr_en     <= 1'b1;
            state     <= S_UPD3;
        end
        // UPD3: acc = acc + k3
        S_UPD3: begin
            mux_a_sel <= `REG(R_ACC);
            mux_b_sel <= `REG(R_K3);
            alu_op    <= OP_ADD;
            wr_addr   <= R_ACC;
            wr_en     <= 1'b1;
            state     <= S_UPD4;
        end
        // UPD4: acc = acc + k3  (now k1 + 2k2 + 2k3)
        S_UPD4: begin
            mux_a_sel <= `REG(R_ACC);
            mux_b_sel <= `REG(R_K3);
            alu_op    <= OP_ADD;
            wr_addr   <= R_ACC;
            wr_en     <= 1'b1;
            state     <= S_UPD5;
        end
        // UPD5: acc = acc + k4  (k_sum complete)
        S_UPD5: begin
            mux_a_sel <= `REG(R_ACC);
            mux_b_sel <= `REG(R_K4);
            alu_op    <= OP_ADD;
            wr_addr   <= R_ACC;
            wr_en     <= 1'b1;
            state     <= S_UPD6;
        end
        // UPD6: acc = qmul(acc, dt)
        S_UPD6: begin
            mux_a_sel <= `REG(R_ACC);
            mux_b_sel <= C_DT;
            alu_op    <= OP_MUL;
            wr_addr   <= R_ACC;
            wr_en     <= 1'b1;
            state     <= S_UPD7;
        end
        // UPD7: acc = qmul(acc, INV6)
        S_UPD7: begin
            mux_a_sel <= `REG(R_ACC);
            mux_b_sel <= C_INV6;
            alu_op    <= OP_MUL;
            wr_addr   <= R_ACC;
            wr_en     <= 1'b1;
            state     <= S_UPD8;
        end
        // UPD8: y = y + acc
        S_UPD8: begin
            mux_a_sel <= `REG(R_Y);
            mux_b_sel <= `REG(R_ACC);
            alu_op    <= OP_ADD;
            wr_addr   <= R_Y;
            wr_en     <= 1'b1;
            state     <= S_UPD_T;
        end
        // t = t + dt; step_cnt++
        S_UPD_T: begin
            mux_a_sel <= `REG(R_T);
            mux_b_sel <= C_DT;
            alu_op    <= OP_ADD;
            wr_addr   <= R_T;
            wr_en     <= 1'b1;
            step_cnt  <= step_cnt + 7'd1;
            state     <= S_CHECK;
        end

        // --- CHECK ---
        S_CHECK: begin
            if (y_negative || step_cnt == NUM_DIV[6:0])
                state <= S_DONE_MARK;
            else
                state <= S_TX_PREP;
        end

        // --- TX: send (t, y) pair ---
        S_TX_PREP: begin
            tx_send_pair <= 1'b1;
            state        <= S_TX_WAIT;
        end
        S_TX_WAIT: begin
            if (tx_pair_sent) state <= S_PRELOAD_G;
        end

        // --- DONE: send 0xDEADBEEF marker ---
        S_DONE_MARK: begin
            tx_send_done_marker <= 1'b1;
            state               <= S_DONE_WAIT;
        end
        S_DONE_WAIT: begin
            if (tx_pair_sent) state <= S_IDLE;
        end

        default: state <= S_IDLE;

        endcase
    end
end

endmodule
