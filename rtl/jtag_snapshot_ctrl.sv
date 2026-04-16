`timescale 1ns / 1ps
// jtag_snapshot_ctrl.sv — CLK-domain snapshot controller
//
// Receives snapshot requests from TCK domain (via synchronized toggle),
// captures all debug-observable state atomically in a single posedge clk,
// and signals completion back via ack toggle.
// Also forwards halt/resume/single-step across the CDC boundary.

module jtag_snapshot_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    // CDC inputs (from TCK domain, already synchronized by 2-FF in rk4_top)
    input  wire        snap_req_tgl_synced,
    output reg         snap_ack_tgl,
    input  wire        halt_req_synced,
    input  wire        resume_req_tgl_synced,
    input  wire        single_step_tgl_synced,

    // Debug observation inputs (from rk4_projectile_top)
    input  wire [5:0]  fsm_state_i,
    input  wire        fsm_busy_i,
    input  wire        halted_i,
    input  wire        is_safe_i,
    input  wire [6:0]  step_cnt_i,
    input  wire        f_active_i,
    input  wire [3:0]  f_pc_i,
    input  wire [1:0]  f_estate_i,
    input  wire signed [31:0] dt_reg_i,
    input  wire signed [31:0] regs_i [0:7],

    // Debug control outputs (to rk4_control_fsm via rk4_projectile_top)
    output wire        halt_req_o,
    output reg         resume_req_o,
    output reg         single_step_o,

    // Snapshot outputs (stable, held until next snapshot)
    output reg  [47:0]  snap_status_o,
    output reg  [255:0] snap_regbank_o
);

// Toggle edge detectors — stored copies
reg snap_req_prev;
reg resume_prev;
reg single_step_prev;

wire capture_pulse    = snap_req_tgl_synced ^ snap_req_prev;
wire resume_pulse     = resume_req_tgl_synced ^ resume_prev;
wire single_step_pulse = single_step_tgl_synced ^ single_step_prev;

// Halt is level-forwarded (not toggle-based)
assign halt_req_o = halt_req_synced;

// 4-bit snapshot epoch counter
reg [3:0] snap_epoch;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        snap_status_o    <= 48'd0;
        snap_regbank_o   <= 256'd0;
        snap_epoch       <= 4'd0;
        snap_ack_tgl     <= 1'b0;
        snap_req_prev    <= 1'b0;
        resume_prev      <= 1'b0;
        single_step_prev <= 1'b0;
        resume_req_o     <= 1'b0;
        single_step_o    <= 1'b0;
    end else begin
        // Default: pulse outputs are single-cycle
        resume_req_o  <= 1'b0;
        single_step_o <= 1'b0;

        // Store previous toggle values for edge detection
        snap_req_prev    <= snap_req_tgl_synced;
        resume_prev      <= resume_req_tgl_synced;
        single_step_prev <= single_step_tgl_synced;

        // Atomic snapshot capture
        if (capture_pulse) begin
            // Status register: [47:32]=dt_reg upper half, [31:26]=reserved,
            // [25:22]=epoch+1, [21:20]=f_estate, [19:16]=f_pc,
            // [15]=f_active, [14:8]=step_cnt, [7]=halted, [6]=busy, [5:0]=fsm_state
            snap_status_o <= {
                dt_reg_i[31:16],           // [47:32]
                6'd0,                      // [31:26] reserved
                snap_epoch + 4'd1,         // [25:22] new epoch
                f_estate_i,                // [21:20]
                f_pc_i,                    // [19:16]
                f_active_i,                // [15]
                step_cnt_i,                // [14:8]
                halted_i,                  // [7]
                fsm_busy_i,               // [6]
                fsm_state_i                // [5:0]
            };

            // Regbank: R0 at LSB, R7 at MSB
            snap_regbank_o <= {
                regs_i[7], regs_i[6], regs_i[5], regs_i[4],
                regs_i[3], regs_i[2], regs_i[1], regs_i[0]
            };

            snap_epoch   <= snap_epoch + 4'd1;
            snap_ack_tgl <= ~snap_ack_tgl;
        end

        // Resume / single-step edge-detect to pulse
        if (resume_pulse)
            resume_req_o <= 1'b1;
        if (single_step_pulse)
            single_step_o <= 1'b1;
    end
end

endmodule
