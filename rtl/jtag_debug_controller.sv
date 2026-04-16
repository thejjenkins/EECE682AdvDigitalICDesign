`timescale 1ns / 1ps
// jtag_debug_controller.sv — TCK-domain debug DR manager
//
// Manages four debug data registers (STATUS, REGBANK, CONTROL, IMEM),
// drives CDC toggle signals toward CLK domain, and provides TDO mux
// output back to the TAP controller.

module jtag_debug_controller (
    input  wire        tck_i,
    input  wire        trst_ni,

    // TAP interface
    input  wire        capture_dr_i,
    input  wire        shift_dr_i,
    input  wire        update_dr_i,
    input  wire        tdi_i,

    // DR selection (from TAP IR decode)
    input  wire        status_sel_i,
    input  wire        regbank_sel_i,
    input  wire        control_sel_i,
    input  wire        imem_sel_i,

    // TDO output for debug DRs
    output wire        dbg_tdo_o,

    // CDC outputs (toward CLK domain via synchronizers in rk4_top)
    output reg         snap_req_tgl_o,
    input  wire        snap_ack_tgl_synced_i,
    output reg         halt_req_o,
    output reg         resume_req_tgl_o,
    output reg         single_step_tgl_o,
    input  wire        dbg_halted_synced_i,

    // Snapshot data (from CLK domain, stable under handshake)
    input  wire [47:0] snap_status_i,
    input  wire [255:0] snap_regbank_i,

    // IMEM access
    output wire [3:0]  imem_addr_o,
    input  wire [15:0] imem_rdata_synced_i
);

// =====================================================================
//  Shift registers
// =====================================================================
reg [47:0]  status_sr;
reg [255:0] regbank_sr;
reg [7:0]   control_sr;
reg [31:0]  imem_sr;

// Control latch (holds last Update-DR value for readback)
reg [7:0]   control_latch;

// IMEM address output is always bits [3:0] of the IMEM shift register
assign imem_addr_o = imem_sr[3:0];

// =====================================================================
//  TDO mux — bit[0] of the selected shift register
// =====================================================================
reg tdo_mux;
always @(*) begin
    tdo_mux = 1'b0;
    if (status_sel_i)       tdo_mux = status_sr[0];
    else if (regbank_sel_i) tdo_mux = regbank_sr[0];
    else if (control_sel_i) tdo_mux = control_sr[0];
    else if (imem_sel_i)    tdo_mux = imem_sr[0];
end
assign dbg_tdo_o = tdo_mux;

// =====================================================================
//  DBG_STATUS shift register (48-bit, read-only)
// =====================================================================
always @(posedge tck_i or negedge trst_ni) begin
    if (!trst_ni) begin
        status_sr <= 48'd0;
    end else begin
        if (capture_dr_i && status_sel_i)
            status_sr <= snap_status_i;
        else if (shift_dr_i && status_sel_i)
            status_sr <= {tdi_i, status_sr[47:1]};
    end
end

// =====================================================================
//  DBG_REGBANK shift register (256-bit, read-only)
// =====================================================================
always @(posedge tck_i or negedge trst_ni) begin
    if (!trst_ni) begin
        regbank_sr <= 256'd0;
    end else begin
        if (capture_dr_i && regbank_sel_i)
            regbank_sr <= snap_regbank_i;
        else if (shift_dr_i && regbank_sel_i)
            regbank_sr <= {tdi_i, regbank_sr[255:1]};
    end
end

// =====================================================================
//  DBG_CONTROL shift register (8-bit, R/W)
// =====================================================================
always @(posedge tck_i or negedge trst_ni) begin
    if (!trst_ni) begin
        control_sr    <= 8'd0;
        control_latch <= 8'd0;
    end else begin
        if (capture_dr_i && control_sel_i)
            control_sr <= control_latch;
        else if (shift_dr_i && control_sel_i)
            control_sr <= {tdi_i, control_sr[7:1]};

        if (update_dr_i && control_sel_i)
            control_latch <= control_sr;
    end
end

// =====================================================================
//  DBG_IMEM shift register (32-bit, R/W)
// =====================================================================
always @(posedge tck_i or negedge trst_ni) begin
    if (!trst_ni) begin
        imem_sr <= 32'd0;
    end else begin
        if (capture_dr_i && imem_sel_i)
            imem_sr <= {11'd0, 1'b0, imem_rdata_synced_i, imem_sr[3:0]};
        else if (shift_dr_i && imem_sel_i)
            imem_sr <= {tdi_i, imem_sr[31:1]};
    end
end

// =====================================================================
//  Control decode: Update-DR on CONTROL register drives CDC outputs
//
//  control_sr[0] = halt_req    (level)
//  control_sr[1] = resume_req  (toggle on rising edge)
//  control_sr[2] = single_step (toggle on rising edge)
//  control_sr[3] = snap_req    (toggle on rising edge)
// =====================================================================
always @(posedge tck_i or negedge trst_ni) begin
    if (!trst_ni) begin
        halt_req_o         <= 1'b0;
        resume_req_tgl_o   <= 1'b0;
        single_step_tgl_o  <= 1'b0;
        snap_req_tgl_o     <= 1'b0;
    end else if (update_dr_i && control_sel_i) begin
        halt_req_o <= control_sr[0];

        if (control_sr[1])
            resume_req_tgl_o <= ~resume_req_tgl_o;
        if (control_sr[2])
            single_step_tgl_o <= ~single_step_tgl_o;
        if (control_sr[3])
            snap_req_tgl_o <= ~snap_req_tgl_o;
    end
end

endmodule
