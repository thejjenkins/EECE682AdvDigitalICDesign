`timescale 1ns / 1ps

module rk4_top (
    //input  wire       clk_100MHz,
    input  wire       clk,
    // input  wire       en,
    input  wire       rst,
    // input  wire [1:0] sel,
    input  wire       uart_rx,
    output wire       uart_tx,
    // output wire       clk_1Hz,
    // JTAG interface
    input  wire       tck,
    input  wire       tms,
    input  wire       trst_n,
    input  wire       tdi,
    output wire       tdo,
    output wire       tdo_oe,
    // Simple test of inverter
    input  wire       test_in,
    output wire       test_out
);

    // =================================================================
    //  Debug signal wires from rk4_projectile_top
    // =================================================================
    wire [5:0]          dbg_fsm_state;
    wire                dbg_fsm_busy;
    wire                dbg_halted_raw;
    wire                dbg_is_safe;
    wire [6:0]          dbg_step_cnt;
    wire                dbg_f_active;
    wire [3:0]          dbg_f_pc;
    wire [1:0]          dbg_f_estate;
    wire signed [31:0]  dbg_dt_reg;
    wire signed [31:0]  dbg_regs_out [0:7];
    wire [3:0]          dbg_imem_addr;
    wire [15:0]         dbg_imem_rdata;

    // Debug control signals into rk4_projectile_top
    wire                core_halt_req;
    wire                core_resume_req;
    wire                core_single_step;

    // =================================================================
    //  RK4 Projectile Core
    // =================================================================
    rk4_projectile_top rk4_core (
        .clk            (clk),
        .rst_n          (rst),
        .uart_rx        (uart_rx),
        .uart_tx        (uart_tx),
        .dbg_fsm_state  (dbg_fsm_state),
        .dbg_fsm_busy   (dbg_fsm_busy),
        .dbg_halted     (dbg_halted_raw),
        .dbg_is_safe    (dbg_is_safe),
        .dbg_step_cnt   (dbg_step_cnt),
        .dbg_f_active   (dbg_f_active),
        .dbg_f_pc       (dbg_f_pc),
        .dbg_f_estate   (dbg_f_estate),
        .dbg_dt_reg     (dbg_dt_reg),
        .dbg_halt_req   (core_halt_req),
        .dbg_resume_req (core_resume_req),
        .dbg_single_step(core_single_step),
        .dbg_regs_out   (dbg_regs_out),
        .dbg_imem_addr  (dbg_imem_addr),
        .dbg_imem_rdata (dbg_imem_rdata)
    );

    // =================================================================
    //  Inverter (power test — unchanged)
    // =================================================================
    inverter power_test(
        .test_in(test_in),
        .test_out(test_out)
    );

    // =================================================================
    //  JTAG TAP
    // =================================================================
    wire scan_enable, scan_in, scan_out;
    assign scan_out = 1'b0;

    wire dbg_status_sel, dbg_regbank_sel, dbg_control_sel, dbg_imem_sel;
    wire dbg_tdo;
    wire tap_capture_dr, tap_shift_dr, tap_update_dr;

    jtag_tap u_jtag_tap (
        .tck_i                  (tck),
        .tms_i                  (tms),
        .trst_ni                (trst_n),
        .tdi_i                  (tdi),
        .tdo_o                  (tdo),
        .tdo_oe_o               (tdo_oe),
        .scan_enable_o          (scan_enable),
        .scan_in_o              (scan_in),
        .scan_out_i             (scan_out),
        .dbg_status_select_o    (dbg_status_sel),
        .dbg_regbank_select_o   (dbg_regbank_sel),
        .dbg_control_select_o   (dbg_control_sel),
        .dbg_imem_select_o      (dbg_imem_sel),
        .dbg_tdo_i              (dbg_tdo),
        .capture_dr_o           (tap_capture_dr),
        .shift_dr_o             (tap_shift_dr),
        .update_dr_o            (tap_update_dr)
    );

    // =================================================================
    //  CDC Synchronizers
    // =================================================================

    // --- TCK → CLK (reset with rst) ---
    // snap_req_tgl
    wire snap_req_tgl_raw;
    reg [1:0] snap_req_tgl_pipe;
    wire snap_req_tgl_sync = snap_req_tgl_pipe[1];
    always @(posedge clk or negedge rst) begin
        if (!rst) snap_req_tgl_pipe <= 2'b0;
        else      snap_req_tgl_pipe <= {snap_req_tgl_pipe[0], snap_req_tgl_raw};
    end

    // halt_req
    wire halt_req_raw;
    reg [1:0] halt_req_pipe;
    wire halt_req_sync = halt_req_pipe[1];
    always @(posedge clk or negedge rst) begin
        if (!rst) halt_req_pipe <= 2'b0;
        else      halt_req_pipe <= {halt_req_pipe[0], halt_req_raw};
    end

    // resume_req_tgl
    wire resume_req_tgl_raw;
    reg [1:0] resume_req_tgl_pipe;
    wire resume_req_tgl_sync = resume_req_tgl_pipe[1];
    always @(posedge clk or negedge rst) begin
        if (!rst) resume_req_tgl_pipe <= 2'b0;
        else      resume_req_tgl_pipe <= {resume_req_tgl_pipe[0], resume_req_tgl_raw};
    end

    // single_step_tgl
    wire single_step_tgl_raw;
    reg [1:0] single_step_tgl_pipe;
    wire single_step_tgl_sync = single_step_tgl_pipe[1];
    always @(posedge clk or negedge rst) begin
        if (!rst) single_step_tgl_pipe <= 2'b0;
        else      single_step_tgl_pipe <= {single_step_tgl_pipe[0], single_step_tgl_raw};
    end

    // --- CLK → TCK (reset with trst_n) ---
    // snap_ack_tgl
    wire snap_ack_tgl_raw;
    reg [1:0] snap_ack_tgl_pipe;
    wire snap_ack_tgl_sync = snap_ack_tgl_pipe[1];
    always @(posedge tck or negedge trst_n) begin
        if (!trst_n) snap_ack_tgl_pipe <= 2'b0;
        else         snap_ack_tgl_pipe <= {snap_ack_tgl_pipe[0], snap_ack_tgl_raw};
    end

    // dbg_halted
    reg [1:0] dbg_halted_pipe;
    wire dbg_halted_sync = dbg_halted_pipe[1];
    always @(posedge tck or negedge trst_n) begin
        if (!trst_n) dbg_halted_pipe <= 2'b0;
        else         dbg_halted_pipe <= {dbg_halted_pipe[0], dbg_halted_raw};
    end

    // =================================================================
    //  Snapshot data buses (stable-bus rule: only read after handshake)
    // =================================================================
    wire [47:0]  snap_status;
    wire [255:0] snap_regbank;

    // =================================================================
    //  JTAG Debug Controller (TCK domain)
    // =================================================================
    jtag_debug_controller u_dbg_ctrl (
        .tck_i                  (tck),
        .trst_ni                (trst_n),
        .capture_dr_i           (tap_capture_dr),
        .shift_dr_i             (tap_shift_dr),
        .update_dr_i            (tap_update_dr),
        .tdi_i                  (tdi),
        .status_sel_i           (dbg_status_sel),
        .regbank_sel_i          (dbg_regbank_sel),
        .control_sel_i          (dbg_control_sel),
        .imem_sel_i             (dbg_imem_sel),
        .dbg_tdo_o              (dbg_tdo),
        .snap_req_tgl_o         (snap_req_tgl_raw),
        .snap_ack_tgl_synced_i  (snap_ack_tgl_sync),
        .halt_req_o             (halt_req_raw),
        .resume_req_tgl_o       (resume_req_tgl_raw),
        .single_step_tgl_o      (single_step_tgl_raw),
        .dbg_halted_synced_i    (dbg_halted_sync),
        .snap_status_i          (snap_status),
        .snap_regbank_i         (snap_regbank),
        .imem_addr_o            (dbg_imem_addr),
        .imem_rdata_synced_i    (dbg_imem_rdata)
    );

    // =================================================================
    //  Snapshot Controller (CLK domain)
    // =================================================================
    jtag_snapshot_ctrl u_snap_ctrl (
        .clk                        (clk),
        .rst_n                      (rst),
        .snap_req_tgl_synced        (snap_req_tgl_sync),
        .snap_ack_tgl               (snap_ack_tgl_raw),
        .halt_req_synced            (halt_req_sync),
        .resume_req_tgl_synced      (resume_req_tgl_sync),
        .single_step_tgl_synced     (single_step_tgl_sync),
        .fsm_state_i                (dbg_fsm_state),
        .fsm_busy_i                 (dbg_fsm_busy),
        .halted_i                   (dbg_halted_raw),
        .is_safe_i                  (dbg_is_safe),
        .step_cnt_i                 (dbg_step_cnt),
        .f_active_i                 (dbg_f_active),
        .f_pc_i                     (dbg_f_pc),
        .f_estate_i                 (dbg_f_estate),
        .dt_reg_i                   (dbg_dt_reg),
        .regs_i                     (dbg_regs_out),
        .halt_req_o                 (core_halt_req),
        .resume_req_o               (core_resume_req),
        .single_step_o              (core_single_step),
        .snap_status_o              (snap_status),
        .snap_regbank_o             (snap_regbank)
    );

endmodule
