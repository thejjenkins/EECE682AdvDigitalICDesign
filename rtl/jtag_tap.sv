`timescale 1ns / 1ps

// IEEE 1149.1 JTAG TAP Controller with multiplexed debug bus
//
// 3-bit IR with IDCODE, BYPASS, and a two-register debug interface
// (DBG_ADDR selects a 32-bit group, DBG_DATA shifts it out).
// All debug inputs from the system clock domain are synchronized
// to TCK with 2-FF chains before use.

module jtag_tap #(
    parameter IrLength    = 3,
    parameter [31:0] IdcodeValue = 32'hEECE_00DE
) (
    // JTAG pins
    input  logic        tck_i,
    input  logic        tms_i,
    input  logic        trst_ni,
    input  logic        tdi_i,
    output logic        tdo_o,

    // Debug inputs (active in system clk domain)
    input  logic        dbg_busy_i,
    input  logic [5:0]  dbg_fsm_state_i,
    input  logic [6:0]  dbg_step_cnt_i,
    input  logic        dbg_uart_rx_i,

    input  logic [31:0] dbg_rf_t_i,
    input  logic [31:0] dbg_rf_y_i,
    input  logic [31:0] dbg_dt_i,

    input  logic [31:0] dbg_alu_result_i,
    input  logic [31:0] dbg_alu_a_i,
    input  logic [31:0] dbg_alu_b_i,

    input  logic        dbg_f_active_i,
    input  logic [1:0]  dbg_fe_estate_i,
    input  logic [3:0]  dbg_fe_pc_i,

    input  logic        dbg_tx_ready_i,
    input  logic [3:0]  dbg_tx_bytes_left_i,
    input  logic [1:0]  dbg_proto_pstate_i
);

    // =================================================================
    //  TAP FSM states (IEEE 1149.1)
    // =================================================================
    typedef enum logic [3:0] {
        TestLogicReset, RunTestIdle, SelectDrScan,
        CaptureDr, ShiftDr, Exit1Dr, PauseDr, Exit2Dr,
        UpdateDr, SelectIrScan, CaptureIr, ShiftIr,
        Exit1Ir, PauseIr, Exit2Ir, UpdateIr
    } tap_state_e;

    tap_state_e tap_state_q, tap_state_d;

    // =================================================================
    //  IR definitions
    // =================================================================
    typedef enum logic [IrLength-1:0] {
        BYPASS0  = 3'b000,
        IDCODE   = 3'b001,
        DBG_ADDR = 3'b010,
        DBG_DATA = 3'b011,
        BYPASS1  = 3'b111
    } ir_reg_e;

    logic [IrLength-1:0] ir_shift_d, ir_shift_q;
    ir_reg_e             ir_d, ir_q;

    // TAP control signals
    logic capture_dr, shift_dr, update_dr;
    logic capture_ir, shift_ir, update_ir;
    logic test_logic_reset;

    // =================================================================
    //  2-FF CDC synchronizers  (clk → tck)
    // =================================================================
    // Pack all debug inputs into a single vector for clean sync
    localparam DbgWidth = 1 + 6 + 7 + 1       // busy, fsm_state, step_cnt, uart_rx
                        + 32 + 32 + 32          // rf_t, rf_y, dt
                        + 32 + 32 + 32          // alu_result, alu_a, alu_b
                        + 1 + 2 + 4             // f_active, fe_estate, fe_pc
                        + 1 + 4 + 2;            // tx_ready, tx_bytes_left, proto_pstate

    logic [DbgWidth-1:0] dbg_async, dbg_meta, dbg_sync;

    assign dbg_async = {
        dbg_busy_i,
        dbg_fsm_state_i,
        dbg_step_cnt_i,
        dbg_uart_rx_i,
        dbg_rf_t_i,
        dbg_rf_y_i,
        dbg_dt_i,
        dbg_alu_result_i,
        dbg_alu_a_i,
        dbg_alu_b_i,
        dbg_f_active_i,
        dbg_fe_estate_i,
        dbg_fe_pc_i,
        dbg_tx_ready_i,
        dbg_tx_bytes_left_i,
        dbg_proto_pstate_i
    };

    always_ff @(posedge tck_i or negedge trst_ni) begin
        if (!trst_ni) begin
            dbg_meta <= '0;
            dbg_sync <= '0;
        end else begin
            dbg_meta <= dbg_async;
            dbg_sync <= dbg_meta;
        end
    end

    // Unpack synchronized signals
    logic        s_busy;
    logic [5:0]  s_fsm_state;
    logic [6:0]  s_step_cnt;
    logic        s_uart_rx;
    logic [31:0] s_rf_t, s_rf_y, s_dt;
    logic [31:0] s_alu_result, s_alu_a, s_alu_b;
    logic        s_f_active;
    logic [1:0]  s_fe_estate;
    logic [3:0]  s_fe_pc;
    logic        s_tx_ready;
    logic [3:0]  s_tx_bytes_left;
    logic [1:0]  s_proto_pstate;

    assign {
        s_busy,
        s_fsm_state,
        s_step_cnt,
        s_uart_rx,
        s_rf_t,
        s_rf_y,
        s_dt,
        s_alu_result,
        s_alu_a,
        s_alu_b,
        s_f_active,
        s_fe_estate,
        s_fe_pc,
        s_tx_ready,
        s_tx_bytes_left,
        s_proto_pstate
    } = dbg_sync;

    // =================================================================
    //  Debug MUX — select one 32-bit group
    // =================================================================
    logic [3:0]  dbg_addr_shift_d, dbg_addr_shift_q;
    logic [3:0]  dbg_addr_q;
    logic [31:0] dbg_mux_out;

    always_comb begin
        case (dbg_addr_q)
            4'h0: dbg_mux_out = {24'b0, s_uart_rx, s_step_cnt};
            4'h1: dbg_mux_out = {24'b0, s_f_active, s_busy, s_fsm_state};
            4'h2: dbg_mux_out = s_rf_t;
            4'h3: dbg_mux_out = s_rf_y;
            4'h4: dbg_mux_out = s_dt;
            4'h5: dbg_mux_out = s_alu_result;
            4'h6: dbg_mux_out = s_alu_a;
            4'h7: dbg_mux_out = s_alu_b;
            4'h8: dbg_mux_out = {20'b0, s_proto_pstate, s_tx_bytes_left,
                                  s_fe_pc, s_fe_estate};
            default: dbg_mux_out = 32'h0;
        endcase
    end

    // =================================================================
    //  IR shift / latch
    // =================================================================
    always_comb begin
        ir_shift_d = ir_shift_q;
        ir_d       = ir_q;

        if (capture_ir)
            ir_shift_d = IrLength'(3'b001);

        if (shift_ir)
            ir_shift_d = {tdi_i, ir_shift_q[IrLength-1:1]};

        if (update_ir)
            ir_d = ir_reg_e'(ir_shift_q);

        if (test_logic_reset) begin
            ir_shift_d = '0;
            ir_d       = IDCODE;
        end
    end

    always_ff @(posedge tck_i or negedge trst_ni) begin
        if (!trst_ni) begin
            ir_shift_q <= '0;
            ir_q       <= IDCODE;
        end else begin
            ir_shift_q <= ir_shift_d;
            ir_q       <= ir_d;
        end
    end

    // =================================================================
    //  DR select decode
    // =================================================================
    logic idcode_sel, bypass_sel, dbg_addr_sel, dbg_data_sel;

    always_comb begin
        idcode_sel   = 1'b0;
        bypass_sel   = 1'b0;
        dbg_addr_sel = 1'b0;
        dbg_data_sel = 1'b0;
        unique case (ir_q)
            IDCODE:   idcode_sel   = 1'b1;
            DBG_ADDR: dbg_addr_sel = 1'b1;
            DBG_DATA: dbg_data_sel = 1'b1;
            default:  bypass_sel   = 1'b1;
        endcase
    end

    // =================================================================
    //  IDCODE register (32-bit)
    // =================================================================
    logic [31:0] idcode_d, idcode_q;

    always_comb begin
        idcode_d = idcode_q;
        if (capture_dr && idcode_sel)
            idcode_d = IdcodeValue;
        if (shift_dr && idcode_sel)
            idcode_d = {tdi_i, idcode_q[31:1]};
        if (test_logic_reset)
            idcode_d = IdcodeValue;
    end

    // =================================================================
    //  BYPASS register (1-bit)
    // =================================================================
    logic bypass_d, bypass_q;

    always_comb begin
        bypass_d = bypass_q;
        if (capture_dr && bypass_sel)
            bypass_d = 1'b0;
        if (shift_dr && bypass_sel)
            bypass_d = tdi_i;
        if (test_logic_reset)
            bypass_d = 1'b0;
    end

    // =================================================================
    //  DBG_ADDR register (4-bit shift + 4-bit latch)
    // =================================================================
    always_comb begin
        dbg_addr_shift_d = dbg_addr_shift_q;
        if (capture_dr && dbg_addr_sel)
            dbg_addr_shift_d = dbg_addr_q;
        if (shift_dr && dbg_addr_sel)
            dbg_addr_shift_d = {tdi_i, dbg_addr_shift_q[3:1]};
    end

    // =================================================================
    //  DBG_DATA register (32-bit shift, capture from mux)
    // =================================================================
    logic [31:0] dbg_data_shift_d, dbg_data_shift_q;

    always_comb begin
        dbg_data_shift_d = dbg_data_shift_q;
        if (capture_dr && dbg_data_sel)
            dbg_data_shift_d = dbg_mux_out;
        if (shift_dr && dbg_data_sel)
            dbg_data_shift_d = {tdi_i, dbg_data_shift_q[31:1]};
    end

    // =================================================================
    //  DR state registers
    // =================================================================
    always_ff @(posedge tck_i or negedge trst_ni) begin
        if (!trst_ni) begin
            idcode_q         <= IdcodeValue;
            bypass_q         <= 1'b0;
            dbg_addr_shift_q <= 4'h0;
            dbg_addr_q       <= 4'h0;
            dbg_data_shift_q <= 32'h0;
        end else begin
            idcode_q         <= idcode_d;
            bypass_q         <= bypass_d;
            dbg_addr_shift_q <= dbg_addr_shift_d;
            dbg_data_shift_q <= dbg_data_shift_d;

            if (update_dr && dbg_addr_sel)
                dbg_addr_q <= dbg_addr_shift_q;
        end
    end

    // =================================================================
    //  TDO output mux
    // =================================================================
    logic tdo_mux;

    always_comb begin
        if (shift_ir) begin
            tdo_mux = ir_shift_q[0];
        end else begin
            unique case (ir_q)
                IDCODE:   tdo_mux = idcode_q[0];
                DBG_ADDR: tdo_mux = dbg_addr_shift_q[0];
                DBG_DATA: tdo_mux = dbg_data_shift_q[0];
                default:  tdo_mux = bypass_q;
            endcase
        end
    end

    always_ff @(negedge tck_i or negedge trst_ni) begin
        if (!trst_ni)
            tdo_o <= 1'b0;
        else
            tdo_o <= tdo_mux;
    end

    // =================================================================
    //  TAP FSM — next-state logic
    // =================================================================
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

    always_ff @(posedge tck_i or negedge trst_ni) begin
        if (!trst_ni)
            tap_state_q <= TestLogicReset;
        else
            tap_state_q <= tap_state_d;
    end

endmodule : jtag_tap
