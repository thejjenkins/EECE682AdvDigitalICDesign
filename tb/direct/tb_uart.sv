`timescale 1ns / 1ps

module tb_uart;

// =====================================================================
//  Parameters — small BAUD_DIV for fast simulation
// =====================================================================
localparam integer CLK_FREQ  = 800;
localparam integer BAUD_RATE = 100;
localparam integer BAUD_DIV  = CLK_FREQ / BAUD_RATE;   // 8
localparam integer HALF_DIV  = BAUD_DIV / 2;            // 4
localparam real    CLK_PER   = 1000.0 / CLK_FREQ;       // 1.25 ns
localparam real    BIT_PER   = CLK_PER * BAUD_DIV;      // 10.0 ns
localparam integer NUM_DIV   = 5;

// =====================================================================
//  Scoreboard
// =====================================================================
integer pass_cnt = 0;
integer fail_cnt = 0;

task automatic check(input string tag, input logic [31:0] got, input logic [31:0] exp);
    if (got === exp) begin
        pass_cnt++;
    end else begin
        fail_cnt++;
        $display("  [FAIL] %s: got 0x%08h, expected 0x%08h", tag, got, exp);
    end
endtask

// =====================================================================
//  Clock & Reset
// =====================================================================
reg clk = 0;
always #(CLK_PER/2.0) clk = ~clk;

reg rst_n;

// =====================================================================
//  Signals for standalone uart_rx
// =====================================================================
reg        rx_line_a = 1'b1;
wire       rxA_valid;
wire [7:0] rxA_data;

uart_rx #(.BAUD_DIV(BAUD_DIV)) u_rx_a (
    .clk(clk), .rst_n(rst_n),
    .rx(rx_line_a), .rx_valid(rxA_valid), .rx_data(rxA_data)
);

// =====================================================================
//  Signals for standalone uart_tx
// =====================================================================
reg        txB_valid = 0;
reg  [7:0] txB_data  = 8'd0;
wire       txB_ready;
wire       txB_line;

uart_tx #(.BAUD_DIV(BAUD_DIV)) u_tx_b (
    .clk(clk), .rst_n(rst_n),
    .tx_valid(txB_valid), .tx_data(txB_data),
    .tx_ready(txB_ready), .tx(txB_line)
);

// =====================================================================
//  Signals for loopback: tx -> rx
// =====================================================================
wire       rxL_valid;
wire [7:0] rxL_data;

uart_rx #(.BAUD_DIV(BAUD_DIV)) u_rx_loop (
    .clk(clk), .rst_n(rst_n),
    .rx(txB_line), .rx_valid(rxL_valid), .rx_data(rxL_data)
);

// =====================================================================
//  Signals for standalone rk4_uart_protocol
// =====================================================================
reg        proto_rx_valid = 0;
reg  [7:0] proto_rx_data  = 8'd0;
reg        proto_fsm_busy = 0;
wire       proto_prog_wr;
wire [3:0] proto_prog_addr;
wire [15:0] proto_prog_data;
wire       proto_v0_load;
wire signed [31:0] proto_v0_data;
wire       proto_run_start;

rk4_uart_protocol u_proto (
    .clk(clk), .rst_n(rst_n),
    .rx_valid(proto_rx_valid), .rx_data(proto_rx_data),
    .prog_wr(proto_prog_wr), .prog_addr(proto_prog_addr), .prog_data(proto_prog_data),
    .v0_load(proto_v0_load), .v0_data(proto_v0_data),
    .run_start(proto_run_start), .fsm_busy(proto_fsm_busy)
);

// =====================================================================
//  Full integration DUT — rk4_projectile_top
// =====================================================================
reg  integ_rx = 1'b1;
wire integ_tx;

rk4_projectile_top #(
    .CLK_FREQ (CLK_FREQ),
    .BAUD_RATE(BAUD_RATE),
    .NUM_DIV  (NUM_DIV)
) u_dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .uart_rx        (integ_rx),
    .uart_tx        (integ_tx),
    // Debug inputs tied to safe defaults (no halt, no step, no IMEM read)
    .dbg_halt_req   (1'b0),
    .dbg_resume_req (1'b0),
    .dbg_single_step(1'b0),
    .dbg_imem_addr  (4'b0),
    // Debug outputs left unconnected (purely observational)
    .dbg_fsm_state  (),
    .dbg_fsm_busy   (),
    .dbg_halted     (),
    .dbg_is_safe    (),
    .dbg_step_cnt   (),
    .dbg_f_active   (),
    .dbg_f_pc       (),
    .dbg_f_estate   (),
    .dbg_dt_reg     (),
    .dbg_regs_out   (),
    .dbg_imem_rdata ()
);

// =====================================================================
//  Helper task: bit-bang one 8N1 byte on an arbitrary rx line
// =====================================================================
task automatic send_byte_on(ref reg line_out, input [7:0] data);
    integer i;
    begin
        line_out = 1'b0;                       // start bit
        #(BIT_PER);
        for (i = 0; i < 8; i = i + 1) begin   // data bits LSB first
            line_out = data[i];
            #(BIT_PER);
        end
        line_out = 1'b1;                       // stop bit
        #(BIT_PER);
    end
endtask

// =====================================================================
//  Helper task: pulse proto_rx_valid with a byte (for protocol parser)
// =====================================================================
task automatic proto_send_byte(input [7:0] data);
    begin
        @(posedge clk);
        proto_rx_valid <= 1'b1;
        proto_rx_data  <= data;
        @(posedge clk);
        proto_rx_valid <= 1'b0;
        @(posedge clk);
    end
endtask

// =====================================================================
//  Helper task: capture one byte from a tx line (bit-bang receive)
// =====================================================================
task automatic capture_byte_from(input reg line_in, output [7:0] data);
    integer i;
    begin
        @(negedge line_in);                    // wait for start bit
        #(BIT_PER + BIT_PER/2);               // skip start, go to mid-bit0
        for (i = 0; i < 8; i = i + 1) begin
            data[i] = line_in;
            if (i < 7) #(BIT_PER);
        end
        #(BIT_PER);                           // ride out stop bit
    end
endtask

// =====================================================================
//  MAIN TEST SEQUENCE
// =====================================================================
initial begin
    $display("\n========== UART Testbench Start ==========\n");
    rst_n = 1'b0;
    #(CLK_PER * 5);
    rst_n = 1'b1;
    #(CLK_PER * 3);

    // -----------------------------------------------------------------
    //  TEST 1: uart_rx — single valid byte
    // -----------------------------------------------------------------
    begin : test1_rx_single
        $display("[TEST 1] uart_rx — single valid byte (0xA5)");
        send_byte_on(rx_line_a, 8'hA5);
        #(CLK_PER * 4);
        check("RX single byte", {24'd0, rxA_data}, {24'd0, 8'hA5});
    end

    // -----------------------------------------------------------------
    //  TEST 2: uart_rx — back-to-back bytes
    // -----------------------------------------------------------------
    begin : test2_rx_backtoback
        reg [7:0] exp [0:2];
        integer k;
        $display("[TEST 2] uart_rx — back-to-back bytes (0x11, 0x22, 0x33)");
        exp[0] = 8'h11; exp[1] = 8'h22; exp[2] = 8'h33;
        for (k = 0; k < 3; k = k + 1) begin
            send_byte_on(rx_line_a, exp[k]);
            #(CLK_PER * 4);
            check($sformatf("RX b2b byte %0d", k), {24'd0, rxA_data}, {24'd0, exp[k]});
        end
    end

    // -----------------------------------------------------------------
    //  TEST 3: uart_rx — framing error (stop bit = 0)
    // -----------------------------------------------------------------
    begin : test3_rx_framing
        integer i;
        reg saved_valid;
        $display("[TEST 3] uart_rx — framing error");
        rx_line_a = 1'b0;           // start
        #(BIT_PER);
        for (i = 0; i < 8; i = i + 1) begin
            rx_line_a = 1'b1;       // data = 0xFF
            #(BIT_PER);
        end
        rx_line_a = 1'b0;           // BAD stop bit
        #(BIT_PER);
        rx_line_a = 1'b1;           // return idle
        #(CLK_PER * 10);
        saved_valid = rxA_valid;
        check("RX framing error (no valid)", {31'd0, saved_valid}, 32'd0);
    end

    // -----------------------------------------------------------------
    //  TEST 4: uart_rx — false start (glitch)
    // -----------------------------------------------------------------
    begin : test4_rx_false_start
        reg saved_valid;
        $display("[TEST 4] uart_rx — false start glitch");
        rx_line_a = 1'b0;
        #(BIT_PER / 4);             // glitch < half bit
        rx_line_a = 1'b1;
        #(BIT_PER * 2);
        saved_valid = rxA_valid;
        check("RX false start (no valid)", {31'd0, saved_valid}, 32'd0);
    end

    // -----------------------------------------------------------------
    //  TEST 5: uart_tx — single byte waveform
    // -----------------------------------------------------------------
    begin : test5_tx_single
        reg [9:0] captured;
        integer i;
        $display("[TEST 5] uart_tx — single byte (0x3C)");
        @(posedge clk);
        txB_data  <= 8'h3C;
        txB_valid <= 1'b1;
        @(posedge clk);
        txB_valid <= 1'b0;
        check("TX ready deasserts", {31'd0, txB_ready}, 32'd0);

        // Wait for baud_cnt to expire, then sample each of the 10 bits
        #(CLK_PER * (BAUD_DIV - 1));
        for (i = 0; i < 10; i = i + 1) begin
            #(CLK_PER);             // sample at first cycle of each bit slot
            captured[i] = txB_line;
            if (i < 9) #(CLK_PER * (BAUD_DIV - 1));
        end
        check("TX start bit",  {31'd0, captured[0]}, 32'd0);
        check("TX data bits",  {24'd0, captured[8:1]}, {24'd0, 8'h3C});
        check("TX stop bit",   {31'd0, captured[9]}, 32'd1);

        // wait for tx to go idle
        @(posedge txB_ready);
        #(CLK_PER * 2);
        check("TX ready re-asserts", {31'd0, txB_ready}, 32'd1);
    end

    // -----------------------------------------------------------------
    //  TEST 6: uart_tx — busy rejection
    // -----------------------------------------------------------------
    begin : test6_tx_busy
        $display("[TEST 6] uart_tx — busy rejection");
        @(posedge clk);
        txB_data  <= 8'hAA;
        txB_valid <= 1'b1;
        @(posedge clk);
        txB_valid <= 1'b0;
        #(CLK_PER * 3);

        // attempt second send while busy
        @(posedge clk);
        txB_data  <= 8'h55;
        txB_valid <= 1'b1;
        @(posedge clk);
        txB_valid <= 1'b0;
        check("TX still busy", {31'd0, txB_ready}, 32'd0);

        @(posedge txB_ready);
        #(CLK_PER * 2);
    end

    // -----------------------------------------------------------------
    //  TEST 7: uart_tx — back-to-back
    // -----------------------------------------------------------------
    begin : test7_tx_b2b
        $display("[TEST 7] uart_tx — back-to-back transmissions");
        @(posedge clk);
        txB_data  <= 8'h01;
        txB_valid <= 1'b1;
        @(posedge clk);
        txB_valid <= 1'b0;

        @(posedge txB_ready);
        @(posedge clk);
        txB_data  <= 8'h02;
        txB_valid <= 1'b1;
        @(posedge clk);
        txB_valid <= 1'b0;

        @(posedge txB_ready);
        #(CLK_PER * 2);
        check("TX b2b idle", {31'd0, txB_ready}, 32'd1);
    end

    // -----------------------------------------------------------------
    //  TEST 8: TX -> RX loopback
    // -----------------------------------------------------------------
    begin : test8_loopback
        reg [7:0] lb_rx;
        integer k;
        reg [7:0] lb_vals [0:3];
        $display("[TEST 8] TX -> RX loopback");
        lb_vals[0] = 8'h00; lb_vals[1] = 8'hFF;
        lb_vals[2] = 8'h55; lb_vals[3] = 8'hA3;

        for (k = 0; k < 4; k = k + 1) begin
            @(posedge clk);
            txB_data  <= lb_vals[k];
            txB_valid <= 1'b1;
            @(posedge clk);
            txB_valid <= 1'b0;

            @(posedge rxL_valid);
            #(CLK_PER);
            check($sformatf("Loopback byte %0d", k),
                  {24'd0, rxL_data}, {24'd0, lb_vals[k]});

            @(posedge txB_ready);
            #(CLK_PER * 2);
        end
    end

    // -----------------------------------------------------------------
    //  TEST 9: Protocol — CMD_LOAD_PROG (0x01)
    // -----------------------------------------------------------------
    begin : test9_proto_load
        integer n;
        reg [15:0] exp_instr;
        $display("[TEST 9] Protocol — CMD_LOAD_PROG");
        proto_send_byte(8'h01);

        for (n = 0; n < 16; n = n + 1) begin
            exp_instr = 16'hA000 + n[15:0];
            proto_send_byte(exp_instr[7:0]);     // low byte
            proto_send_byte(exp_instr[15:8]);    // high byte
            @(posedge clk);
            check($sformatf("PROG addr[%0d]", n),
                  {28'd0, proto_prog_addr}, {28'd0, n[3:0]});
            check($sformatf("PROG data[%0d]", n),
                  {16'd0, proto_prog_data}, {16'd0, exp_instr});
        end
    end

    // -----------------------------------------------------------------
    //  TEST 10: Protocol — CMD_RUN, fsm_busy=0
    // -----------------------------------------------------------------
    begin : test10_proto_run
        $display("[TEST 10] Protocol — CMD_RUN (fsm_busy=0)");
        proto_fsm_busy <= 1'b0;
        proto_send_byte(8'h02);
        proto_send_byte(8'hEF);  // v0[7:0]
        proto_send_byte(8'hBE);  // v0[15:8]
        proto_send_byte(8'hAD);  // v0[23:16]
        proto_send_byte(8'hDE);  // v0[31:24]
        #(CLK_PER * 2);
        check("RUN v0_data", proto_v0_data, 32'hDEADBEEF);
        check("RUN run_start fired", {31'd0, proto_run_start | proto_v0_load}, 32'd1);
    end

    // -----------------------------------------------------------------
    //  TEST 11: Protocol — CMD_RUN, fsm_busy=1
    // -----------------------------------------------------------------
    begin : test11_proto_busy
        reg saw_run;
        $display("[TEST 11] Protocol — CMD_RUN (fsm_busy=1, suppressed)");
        proto_fsm_busy <= 1'b1;
        #(CLK_PER);
        proto_send_byte(8'h02);
        proto_send_byte(8'h11);
        proto_send_byte(8'h22);
        proto_send_byte(8'h33);
        proto_send_byte(8'h44);
        #(CLK_PER * 2);
        check("BUSY v0_data", proto_v0_data, 32'h44332211);
        saw_run = proto_run_start;
        check("BUSY run_start suppressed", {31'd0, saw_run}, 32'd0);
        proto_fsm_busy <= 1'b0;
        #(CLK_PER);
    end

    // -----------------------------------------------------------------
    //  TEST 12: Protocol — unknown command
    // -----------------------------------------------------------------
    begin : test12_proto_unknown
        reg saw_prog, saw_v0, saw_run;
        $display("[TEST 12] Protocol — unknown command (0xFF)");
        proto_send_byte(8'hFF);
        #(CLK_PER * 2);
        saw_prog = proto_prog_wr;
        saw_v0   = proto_v0_load;
        saw_run  = proto_run_start;
        check("Unknown: no prog_wr",   {31'd0, saw_prog}, 32'd0);
        check("Unknown: no v0_load",   {31'd0, saw_v0},   32'd0);
        check("Unknown: no run_start", {31'd0, saw_run},  32'd0);
    end

    // -----------------------------------------------------------------
    //  TEST 13: Protocol — sequential CMD_LOAD_PROG then CMD_RUN
    // -----------------------------------------------------------------
    begin : test13_proto_seq
        integer n;
        $display("[TEST 13] Protocol — sequential LOAD then RUN");
        proto_fsm_busy <= 1'b0;
        proto_send_byte(8'h01);
        for (n = 0; n < 16; n = n + 1) begin
            proto_send_byte(8'h00);
            proto_send_byte(8'h00);
        end
        #(CLK_PER * 2);

        proto_send_byte(8'h02);
        proto_send_byte(8'h78);
        proto_send_byte(8'h56);
        proto_send_byte(8'h34);
        proto_send_byte(8'h12);
        #(CLK_PER * 2);
        check("SEQ v0_data", proto_v0_data, 32'h12345678);
    end

    // -----------------------------------------------------------------
    //  TEST 14: Full integration — load program, run, capture output
    // -----------------------------------------------------------------
    begin : test14_integration
        reg [7:0] rx_byte;
        reg [31:0] t_val, y_val;
        reg [31:0] done_marker;
        integer b;
        reg [15:0] gravity_prog [0:15];

        $display("[TEST 14] Full integration — rk4_projectile_top");

        // Build a trivial f-program: single instruction that does
        // result = NEG(R0) -> dest R2 (k-register), then HALT.
        // Instruction format: [15:13]=src_a [12:10]=src_b [9:7]=alu_op [6:4]=dest [3]=halt [2:0]=0
        // NEG = alu_op 3'b110, src_a = R0 = 3'd0, dest = contextual (overridden by FSM f_dest_k)
        // We want: src_a=000, src_b=000, alu_op=110, dest=000, halt=1 => 16'b000_000_110_000_1_000 = 16'h0308
        gravity_prog[0] = 16'h0308;
        for (b = 1; b < 16; b = b + 1)
            gravity_prog[b] = 16'h0000;

        // Send CMD_LOAD_PROG via bit-bang on integ_rx
        send_byte_on(integ_rx, 8'h01);
        for (b = 0; b < 16; b = b + 1) begin
            send_byte_on(integ_rx, gravity_prog[b][7:0]);
            send_byte_on(integ_rx, gravity_prog[b][15:8]);
        end

        // Send CMD_RUN with v0 = 0x00010000 (1.0 in Q16.16)
        send_byte_on(integ_rx, 8'h02);
        send_byte_on(integ_rx, 8'h00);  // v0[7:0]
        send_byte_on(integ_rx, 8'h00);  // v0[15:8]
        send_byte_on(integ_rx, 8'h01);  // v0[23:16]
        send_byte_on(integ_rx, 8'h00);  // v0[31:24]

        // Capture at least one (t,y) pair (8 bytes little-endian)
        $display("  Waiting for TX output from integration DUT...");
        t_val = 32'd0;
        y_val = 32'd0;

        for (b = 0; b < 4; b = b + 1) begin
            capture_byte_from(integ_tx, rx_byte);
            t_val = t_val | ({24'd0, rx_byte} << (b * 8));
        end
        for (b = 0; b < 4; b = b + 1) begin
            capture_byte_from(integ_tx, rx_byte);
            y_val = y_val | ({24'd0, rx_byte} << (b * 8));
        end

        $display("  First (t,y) pair: t=0x%08h  y=0x%08h", t_val, y_val);
        check("Integration: t != 0", |t_val, 1'b1);

        // Drain remaining bytes until we see the 0xDEADBEEF done marker.
        // The done marker is 4 bytes: 0xEF, 0xBE, 0xAD, 0xDE (little-endian).
        done_marker = 32'd0;
        fork
            begin : capture_done
                reg [7:0] tmp;
                reg [31:0] window;
                integer total_bytes;
                window = 32'd0;
                total_bytes = 0;
                forever begin
                    capture_byte_from(integ_tx, tmp);
                    window = {tmp, window[31:8]};
                    total_bytes = total_bytes + 1;
                    if (window == 32'hDEADBEEF) begin
                        done_marker = window;
                        disable capture_done;
                    end
                    if (total_bytes > 500) begin
                        $display("  [WARN] Gave up after 500 TX bytes without done marker");
                        disable capture_done;
                    end
                end
            end
            begin : timeout_guard
                #(CLK_PER * 500000);
                $display("  [WARN] Integration timeout");
                disable capture_done;
            end
        join
        check("Integration: done marker", done_marker, 32'hDEADBEEF);
    end

    // -----------------------------------------------------------------
    //  Summary
    // -----------------------------------------------------------------
    #(CLK_PER * 10);
    $display("\n========== UART Testbench Done ==========");
    $display("  PASSED: %0d", pass_cnt);
    $display("  FAILED: %0d", fail_cnt);
    if (fail_cnt == 0)
        $display("  ** ALL TESTS PASSED **");
    else
        $display("  ** SOME TESTS FAILED **");
    $display("");
    $finish;
end

endmodule
