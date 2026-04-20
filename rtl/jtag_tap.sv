`timescale 1ns / 1ps

// IEEE 1149.1 JTAG TAP Controller for the RK4 ODE Solver
//
// Provides chip identification (IDCODE) and BYPASS through standard JTAG
// pins.  Scan chain access uses dedicated top-level ports created by Genus
// DFT.  Adapted from the PULP platform dmi_jtag_tap.sv reference.

module jtag_tap #(
    parameter int unsigned IrLength    = 5,
    parameter logic [31:0] IdcodeValue = 32'h10682001
    // [31:28] version      = 0x1
    // [27:12] part number  = 0x0682  (EECE-682)
    // [11:1]  manufacturer = 0x000
    // [0]     mandatory 1
) (
    input  logic tck_i,
    input  logic tms_i,
    input  logic trst_ni,
    input  logic tdi_i,
    output logic tdo_o
);

    // -----------------------------------------------------------------
    //  TAP FSM states (IEEE 1149.1)
    // -----------------------------------------------------------------
    typedef enum logic [3:0] {
        TestLogicReset, RunTestIdle, SelectDrScan,
        CaptureDr, ShiftDr, Exit1Dr, PauseDr, Exit2Dr,
        UpdateDr, SelectIrScan, CaptureIr, ShiftIr,
        Exit1Ir, PauseIr, Exit2Ir, UpdateIr
    } tap_state_e;

    tap_state_e tap_state_q, tap_state_d;

    // -----------------------------------------------------------------
    //  Instruction register definitions
    // -----------------------------------------------------------------
    typedef enum logic [IrLength-1:0] {
        BYPASS0     = 'h0,
        IDCODE      = 'h1,
        dbg_ALU_RESULT = 'h2,
        dbg_FSM_CONTROL_STATE = 'h3,
        dbg_F_ENGINE_PC = 'h4,
        dbg_CUR_INSTR = 'h5,
        dbg_REG_WR_EN = 'h6,
        dbg_REG_V0_DATA = 'h7,
        dbg_RUN_START = 'h8,
        dbg_FSM_BUSY = 'h9,
        dbg_UART_FSM = 'ha,
        BYPASS1     = 'h1f
    } ir_reg_e;

    // IR shift / latch registers
    logic [IrLength-1:0] jtag_ir_shift_d, jtag_ir_shift_q;
    ir_reg_e             jtag_ir_d, jtag_ir_q;

    // TAP control signals (directly from FSM)
    logic capture_dr, shift_dr, update_dr;
    logic capture_ir, shift_ir, update_ir;
    logic test_logic_reset;

    // -----------------------------------------------------------------
    //  IR logic
    // -----------------------------------------------------------------
    always_comb begin
        jtag_ir_shift_d = jtag_ir_shift_q;
        jtag_ir_d       = jtag_ir_q;

        if (shift_ir)
            jtag_ir_shift_d = {tdi_i, jtag_ir_shift_q[IrLength-1:1]};

        if (capture_ir)
            jtag_ir_shift_d = IrLength'(4'b0101);

        if (update_ir)
            jtag_ir_d = ir_reg_e'(jtag_ir_shift_q);

        if (test_logic_reset) begin
            jtag_ir_shift_d = '0;
            jtag_ir_d       = IDCODE;
        end
    end

    always_ff @(posedge tck_i, negedge trst_ni) begin
        if (!trst_ni) begin
            jtag_ir_shift_q <= '0;
            jtag_ir_q       <= IDCODE;
        end else begin
            jtag_ir_shift_q <= jtag_ir_shift_d;
            jtag_ir_q       <= jtag_ir_d;
        end
    end

    // -----------------------------------------------------------------
    //  Data register selection
    // -----------------------------------------------------------------
    logic idcode_select, bypass_select;

    always_comb begin
        idcode_select = 1'b0;
        bypass_select = 1'b0;
        unique case (jtag_ir_q)
            IDCODE:  idcode_select = 1'b1;
            default: bypass_select = 1'b1;
        endcase
    end

    // -----------------------------------------------------------------
    //  IDCODE register (32-bit, shift-only DR)
    // -----------------------------------------------------------------
    logic [31:0] idcode_d, idcode_q;

    always_comb begin
        idcode_d = idcode_q;
        if (capture_dr && idcode_select)
            idcode_d = IdcodeValue;
        if (shift_dr && idcode_select)
            idcode_d = {tdi_i, idcode_q[31:1]};
        if (test_logic_reset)
            idcode_d = IdcodeValue;
    end

    // -----------------------------------------------------------------
    //  Bypass register (1-bit)
    // -----------------------------------------------------------------
    logic bypass_d, bypass_q;

    always_comb begin
        bypass_d = bypass_q;
        if (capture_dr && bypass_select)
            bypass_d = 1'b0;
        if (shift_dr && bypass_select)
            bypass_d = tdi_i;
        if (test_logic_reset)
            bypass_d = 1'b0;
    end

    // -----------------------------------------------------------------
    //  DR state registers
    // -----------------------------------------------------------------
    always_ff @(posedge tck_i or negedge trst_ni) begin
        if (!trst_ni) begin
            idcode_q <= IdcodeValue;
            bypass_q <= 1'b0;
        end else begin
            idcode_q <= idcode_d;
            bypass_q <= bypass_d;
        end
    end

    // -----------------------------------------------------------------
    //  TDO output mux
    // -----------------------------------------------------------------
    logic tdo_mux;

    always_comb begin
        if (shift_ir) begin
            tdo_mux = jtag_ir_shift_q[0];
        end else begin
            unique case (jtag_ir_q)
                IDCODE:  tdo_mux = idcode_q[0];
                default: tdo_mux = bypass_q;
            endcase
        end
    end

    // TDO changes on the negative edge of TCK (IEEE 1149.1 requirement)
    always_ff @(negedge tck_i or negedge trst_ni) begin
        if (!trst_ni) begin
            tdo_o    <= 1'b0;
            // tdo_oe_o <= 1'b0;
        end else begin
            tdo_o    <= tdo_mux;
            // tdo_oe_o <= (shift_ir | shift_dr);
        end
    end

    // -----------------------------------------------------------------
    //  TAP FSM — next-state logic
    // -----------------------------------------------------------------
    always_comb begin
        tap_state_d      = tap_state_q;
        test_logic_reset = 1'b0;
        capture_dr       = 1'b0;
        shift_dr         = 1'b0;
        update_dr        = 1'b0;
        capture_ir       = 1'b0;
        shift_ir         = 1'b0;
        update_ir        = 1'b0;

        unique case (tap_state_q)
            TestLogicReset: begin
                tap_state_d      = tms_i ? TestLogicReset : RunTestIdle;
                test_logic_reset = 1'b1;
            end
            RunTestIdle:
                tap_state_d = tms_i ? SelectDrScan : RunTestIdle;

            // ------ DR path ------
            SelectDrScan:
                tap_state_d = tms_i ? SelectIrScan : CaptureDr;
            CaptureDr: begin
                capture_dr  = 1'b1;
                tap_state_d = tms_i ? Exit1Dr : ShiftDr;
            end
            ShiftDr: begin
                shift_dr    = 1'b1;
                tap_state_d = tms_i ? Exit1Dr : ShiftDr;
            end
            Exit1Dr:
                tap_state_d = tms_i ? UpdateDr : PauseDr;
            PauseDr:
                tap_state_d = tms_i ? Exit2Dr : PauseDr;
            Exit2Dr:
                tap_state_d = tms_i ? UpdateDr : ShiftDr;
            UpdateDr: begin
                update_dr   = 1'b1;
                tap_state_d = tms_i ? SelectDrScan : RunTestIdle;
            end

            // ------ IR path ------
            SelectIrScan:
                tap_state_d = tms_i ? TestLogicReset : CaptureIr;
            CaptureIr: begin
                capture_ir  = 1'b1;
                tap_state_d = tms_i ? Exit1Ir : ShiftIr;
            end
            ShiftIr: begin
                shift_ir    = 1'b1;
                tap_state_d = tms_i ? Exit1Ir : ShiftIr;
            end
            Exit1Ir:
                tap_state_d = tms_i ? UpdateIr : PauseIr;
            PauseIr:
                tap_state_d = tms_i ? Exit2Ir : PauseIr;
            Exit2Ir:
                tap_state_d = tms_i ? UpdateIr : ShiftIr;
            UpdateIr: begin
                update_ir   = 1'b1;
                tap_state_d = tms_i ? SelectDrScan : RunTestIdle;
            end
            default: ;
        endcase
    end

    // TAP state register
    always_ff @(posedge tck_i or negedge trst_ni) begin
        if (!trst_ni)
            tap_state_q <= TestLogicReset;
        else
            tap_state_q <= tap_state_d;
    end

endmodule : jtag_tap
