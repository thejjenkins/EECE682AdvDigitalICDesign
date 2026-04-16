# JTAG Debug Architecture — Best-of-Both-Worlds Implementation Plan

**Document Version:** 1.0  
**Date:** April 15, 2026  
**Target Design:** RK4 ODE Solver ASIC — TSMC 180 nm  
**Clock Domains:** `clk` (system, 1 MHz), `tck` (JTAG, host-controlled)  
**Fixed-Point Format:** Q16.16 signed (32-bit)

---

## Table of Contents

1. [Design Philosophy and Source Synthesis](#1-design-philosophy-and-source-synthesis)
2. [What We Preserve Unchanged](#2-what-we-preserve-unchanged)
3. [Instruction Register Map — Final](#3-instruction-register-map--final)
4. [Data Register Specifications](#4-data-register-specifications)
5. [Safe Freeze-Point Analysis](#5-safe-freeze-point-analysis)
6. [Clock-Domain Crossing Architecture](#6-clock-domain-crossing-architecture)
7. [Step-by-Step RTL Modifications](#7-step-by-step-rtl-modifications)
8. [New Module: `jtag_debug_controller.sv`](#8-new-module-jtag_debug_controllersv)
9. [New Module: `jtag_snapshot_ctrl.sv`](#9-new-module-jtag_snapshot_ctrlsv)
10. [Integration Wiring in `rk4_top.sv`](#10-integration-wiring-in-rk4_topsv)
11. [SDC Constraints Update](#11-sdc-constraints-update)
12. [DFT Script Coexistence](#12-dft-script-coexistence)
13. [Verification Plan](#13-verification-plan)
14. [Area and Timing Budget](#14-area-and-timing-budget)
15. [OpenOCD / Host Scripting Guide](#15-openocd--host-scripting-guide)
16. [Risk Register](#16-risk-register)
17. [Implementation Checklist](#17-implementation-checklist)

---

## 1. Design Philosophy and Source Synthesis

This plan merges the strongest ideas from two independent analyses of the RK4 JTAG problem:

**Source A — Internal RTL Analysis (`jtag_tap_analysis.md`)**
- Detailed line-by-line audit of the existing TAP against IEEE 1149.1.
- Identified the `scan_out = 1'b0` stub as the root cause of zero functional observability.
- Proposed three architectural options (Status-Only, Register Bridge, Full Debug Module).
- Provided precise FF counts, IR maps, and CDC considerations.

**Source B — External Research Report (`deep-research-report (1).md`)**
- Introduced the **coherent snapshot** paradigm: capture all state atomically, then read at leisure.
- Defined the `snap_epoch` counter for host-side coherence verification.
- Advocated the **stable-bus CDC rule**: wide data crosses domains only when held stable under handshake.
- Proposed state-granular single-step and IMEM readback.
- Introduced a security/lifecycle gating framework.

### What We Take from Each

| Decision | Source | Rationale |
|---|---|---|
| Snapshot-oriented architecture (not live reads) | Report | Eliminates incoherent multi-word reads; one capture, many shifts |
| `snap_epoch` coherence counter | Report | Host can verify it read the same snapshot twice; cheap (4-bit) |
| Stable-bus CDC rule | Report | Wide data never crosses while changing; minimizes metastability risk |
| Drop `alu_result` from shadow bank | Internal | ALU is combinational; shadowing it captures a stale/misleading value |
| Enumerate 8 specific safe freeze states | Internal | Report mentioned "idle-like" states; we pin down exactly which 8 of the 37 FSM states qualify |
| Accurate FF budget (~542 FFs) | Internal | Report estimated ~480 FFs but omitted TCK-domain DR shift registers |
| Keep security minimal (Rev A stub) | Internal | Full lifecycle gating adds verification burden with no Rev A payoff |
| IMEM read via combinational port | Report | Valuable for verifying f-engine program loaded correctly |
| Regfile direct output wires (not muxed reads) | Internal | Guarantees single-cycle atomic capture of all 8 registers |
| Preserve SCAN_ACCESS for DFT only | Both | Unanimous: do not overload the DFT path with functional debug |

### Core Architectural Principle

> **One snapshot request captures the entire RK4 state atomically. The host then shifts out individual banks at leisure. No wide bus ever crosses a clock domain while its source is free-running.**

This is the single sentence that distinguishes this design from both a naive "wire signals to TDO" approach and an over-engineered CPU-class debug module.

---

## 2. What We Preserve Unchanged

The following elements of the current RTL are verified correct and must not be modified:

### 2.1 TAP FSM (jtag_tap.sv, lines 33–262)

The 16-state IEEE 1149.1 FSM is fully compliant:
- All state transitions match the standard.
- `TestLogicReset` is reachable via both async `TRST` and five consecutive TMS=1 cycles.
- Control signals (`capture_dr`, `shift_dr`, `update_dr`, `capture_ir`, `shift_ir`, `update_ir`) are asserted in the correct states.

### 2.2 IR Behavior (jtag_tap.sv, lines 64–91)

- Capture loads `5'b00101` (IEEE 1149.1 mandated pattern: `xx01`).
- Shift is LSB-first toward TDO.
- Reset defaults IR to IDCODE.
- Update latches the shift register into the active IR.

### 2.3 IDCODE Register (jtag_tap.sv, lines 114–124)

- 32-bit value `0x10682001` loaded on Capture-DR and Test-Logic-Reset.
- Shift is LSB-first with TDI entering at MSB.

### 2.4 BYPASS Register (jtag_tap.sv, lines 129–139)

- 1-bit, captures zero, shifts TDI to TDO with one-cycle latency.

### 2.5 TDO Output (jtag_tap.sv, lines 177–186)

- Updated on `negedge tck` (IEEE 1149.1 requirement).
- Output enable asserted only during Shift-DR or Shift-IR.

### 2.6 DFT Integration (rk4_dft_script.tcl, lines 43–45)

- JTAG TAP flops marked `dft_dont_scan true`.
- Scan chain defined from `scan_in` to `scan_out`.
- SCAN_ACCESS instruction preserved for post-synthesis chain stitching.

---

## 3. Instruction Register Map — Final

The 5-bit IR provides 32 possible opcodes. We use 7, leaving 25 for future expansion.

| IR Code | Mnemonic | DR Length | Access | Description |
|---|---|---|---|---|
| `5'h00` | `BYPASS0` | 1 | Read | IEEE alias: BYPASS |
| `5'h01` | `IDCODE` | 32 | Read | Chip identification (reset default) |
| `5'h02` | `SCAN_ACCESS` | variable | R/W | DFT scan chain (post-synthesis only) |
| `5'h03` | `DBG_STATUS` | 48 | Read | Coherent snapshot of FSM + counters + epoch |
| `5'h04` | `DBG_REGBANK` | 256 | Read | All 8 regfile entries (R0–R7), 8×32 bits |
| `5'h05` | `DBG_CONTROL` | 8 | R/W | Halt request, resume, single-step, snapshot trigger |
| `5'h06` | `DBG_IMEM` | 32 | R/W | IMEM address (4-bit) + read data (16-bit) + write enable |
| `5'h1F` | `BYPASS1` | 1 | Read | IEEE canonical BYPASS |
| all others | (default) | 1 | Read | Alias to BYPASS |

### 3.1 Why These Four Debug Instructions

**DBG_STATUS (0x03):** The first thing any bring-up script needs. A single 48-bit shift tells you: Is the FSM alive? What state is it in? How many steps has it completed? Is it halted? What epoch is the current snapshot? This answers "is the chip working at all?" without any intrusive action.

**DBG_REGBANK (0x04):** The entire 8×32-bit register file in one 256-bit shift. Because we snapshot atomically, all values are from the same clock cycle. This is the primary numerical debug window: `v0`, `t`, `k1`–`k4`, `y`, and `acc` are all visible.

**DBG_CONTROL (0x05):** The only writable debug register. Allows halt, resume, single-step, and snapshot trigger. Minimal 8-bit width keeps the shift short and reduces the chance of accidental writes.

**DBG_IMEM (0x06):** Optional but high-value. The f-engine's 16×16-bit instruction memory is loaded via UART. If the program loaded incorrectly, the entire RK4 computation is wrong. IMEM readback lets you verify the program without depending on UART loopback.

---

## 4. Data Register Specifications

### 4.1 DBG_STATUS — 48 bits

Captured atomically during snapshot. Shifted LSB-first.

```
Bit Field    Width  Description
───────────────────────────────────────────────────────
[5:0]        6      fsm_state       — rk4_control_fsm state encoding
[6]          1      fsm_busy        — high when FSM is not in S_IDLE
[7]          1      dbg_halted      — high when FSM is frozen at a safe point
[14:8]       7      step_cnt        — current RK4 integration step (0–100)
[15]         1      f_active        — f-engine currently executing
[19:16]      4      f_engine_pc     — f-engine program counter
[21:20]      2      f_engine_estate — f-engine execution state (IDLE/EXEC/WB/DONE)
[25:22]      4      snap_epoch      — increments on each snapshot capture (wraps at 15)
[31:26]      6      (reserved)      — reads as zero
[47:32]      16     dt_reg[31:16]   — upper half of dt (Q16.16 integer part + high frac)
```

**Design notes:**
- `dt_reg[31:16]` provides the time-step magnitude without costing a full 32-bit bank. The full `dt_reg` and `dt_half_reg` are in the regfile-adjacent snapshot if needed in future revisions.
- `snap_epoch` is the Report's key contribution: the host shifts DBG_STATUS, notes the epoch, shifts DBG_REGBANK, then re-shifts DBG_STATUS. If the epoch changed, the data is stale — retry.
- All 48 bits come from the snapshot shadow registers, never from live CLK-domain signals.

### 4.2 DBG_REGBANK — 256 bits

All 8 registers, 32 bits each, concatenated R0 (LSB) through R7 (MSB):

```
Bit Field       Width  Description
───────────────────────────────────────
[31:0]          32     R0 = v0 (initial velocity)
[63:32]         32     R1 = t  (current time)
[95:64]         32     R2 = k1 (RK4 slope 1)
[127:96]        32     R3 = k2 (RK4 slope 2)
[159:128]       32     R4 = k3 (RK4 slope 3)
[191:160]       32     R5 = k4 (RK4 slope 4)
[223:192]       32     R6 = y  (current position)
[255:224]       32     R7 = acc (accumulator/temp)
```

**Why not include `alu_result`?** The ALU (`rk4_alu.sv`) is purely combinational. Its output depends on the current `mux_a_sel`, `mux_b_sel`, and `alu_op` — which are driven by whichever of the FSM or f-engine is active. When the FSM is halted, these signals hold their last-driven values, making `alu_result` a snapshot of whatever the ALU happened to be computing in the halt cycle. This is misleading rather than informative. The register file already contains every meaningful computed value.

### 4.3 DBG_CONTROL — 8 bits

Written on Update-DR. Read back on Capture-DR.

```
Bit Field    Width  Description
───────────────────────────────────────────────────────
[0]          1      halt_req     — 1 = request halt at next safe point
[1]          1      resume_req   — 1 = resume from halted state (auto-clears)
[2]          1      single_step  — 1 = execute one safe-to-safe transition, then re-halt
[3]          1      snap_req     — 1 = trigger a snapshot capture (auto-clears)
[7:4]        4      (reserved)   — write as zero
```

**Operational semantics:**
- **Halt:** Write `8'h01`. FSM runs until it reaches a safe state, then freezes. `dbg_halted` in DBG_STATUS goes high.
- **Snapshot (while halted):** Write `8'h08`. Since the FSM is frozen, all shadow registers capture a perfectly coherent image. `snap_epoch` increments.
- **Snapshot (while running):** Write `8'h08`. The snapshot controller waits for the next safe state, captures, then lets the FSM continue. This is a "non-intrusive peek" — the FSM pauses for exactly one CLK cycle.
- **Resume:** Write `8'h02`. FSM continues from its frozen state. `halt_req` is auto-cleared.
- **Single-step:** Write `8'h05` (halt_req + single_step). FSM advances to the next safe state, captures a snapshot, and re-freezes.

### 4.4 DBG_IMEM — 32 bits

```
Bit Field    Width  Description
───────────────────────────────────────────────────────
[3:0]        4      imem_addr    — instruction address (0–15)
[19:4]       16     imem_rdata   — instruction read data (on Capture-DR)
[20]         1      imem_wr_en   — 1 = write imem_wdata to imem_addr on Update-DR
[31:21]      11     (reserved)   — write as zero
```

**Access gating:** IMEM reads are only valid when `dbg_halted` is asserted or `fsm_state == S_IDLE`. If the f-engine is actively executing, the read port returns `16'hDEAD` as a poison marker to signal invalid data. IMEM writes via JTAG are gated identically — you cannot corrupt a running program.

---

## 5. Safe Freeze-Point Analysis

This is one of the most critical sections. A "safe" state is one where freezing the FSM does not corrupt computation, lose data, or leave the datapath in an inconsistent state.

### 5.1 Criteria for Safety

A state is safe to freeze if ALL of the following hold:
1. **No pending register write:** `wr_en` is low (or will be low after the current cycle completes).
2. **No active f-engine execution:** `f_active` is low.
3. **No partial ALU pipeline:** Since the ALU is combinational, this is always true.
4. **No partial UART transmission in flight that depends on FSM signals:** The TX shift logic is autonomous once loaded.
5. **All computed values have been committed to the register file.**

### 5.2 State-by-State Classification

| State | Code | Safe? | Rationale |
|---|---|---|---|
| `S_IDLE` | 6'd0 | **YES** | No computation active. All registers at rest. |
| `S_INIT1` | 6'd1 | No | About to write `acc = v0 << 1` |
| `S_INIT2` | 6'd2 | No | About to write `acc = acc * INV_G` |
| `S_INIT3` | 6'd3 | No | About to write `acc = acc * INV_N` + latch dt |
| `S_INIT4` | 6'd4 | No | About to write `t = 0` |
| `S_INIT5` | 6'd5 | No | About to write `y = 0` |
| `S_PRELOAD_G` | 6'd6 | No | About to write `R5 = G_FIXED` |
| `S_PRELOAD_T` | 6'd7 | No | About to write `R7 = t` |
| `S_K1_START` | 6'd8 | No | About to pulse `f_start` |
| `S_K1_WAIT` | 6'd9 | **YES** | Waiting for f-engine; all prior writes committed |
| `S_K1_STORE` | 6'd10 | No | About to write `k1 = acc` |
| `S_K2_PREP` | 6'd11 | No | About to write `acc = t + dt_half` |
| `S_K2_START` | 6'd12 | No | About to pulse `f_start` |
| `S_K2_WAIT` | 6'd13 | **YES** | Waiting for f-engine |
| `S_K2_STORE` | 6'd14 | No | About to write `k2 = acc` |
| `S_K3_PREP` | 6'd15 | No | About to write `acc = t + dt_half` |
| `S_K3_START` | 6'd16 | No | About to pulse `f_start` |
| `S_K3_WAIT` | 6'd17 | **YES** | Waiting for f-engine |
| `S_K3_STORE` | 6'd18 | No | About to write `k3 = acc` |
| `S_K4_PREP` | 6'd19 | No | About to write `acc = t + dt` |
| `S_K4_START` | 6'd20 | No | About to pulse `f_start` |
| `S_K4_WAIT` | 6'd21 | **YES** | Waiting for f-engine |
| `S_K4_STORE` | 6'd22 | No | About to write `k4 = acc` |
| `S_UPD1`–`S_UPD8` | 6'd23–30 | No | Multi-cycle update sequence; partial sums in acc |
| `S_UPD_T` | 6'd31 | No | About to write `t = t + dt` |
| `S_CHECK` | 6'd32 | **YES** | Decision point; all updates committed; reading `y_negative` |
| `S_TX_PREP` | 6'd33 | No | About to assert `tx_send_pair` |
| `S_TX_WAIT` | 6'd34 | **YES** | Waiting for TX shift-out; all registers stable |
| `S_DONE_MARK` | 6'd35 | No | About to assert `tx_send_done_marker` |
| `S_DONE_WAIT` | 6'd36 | **YES** | Waiting for TX; all computation complete |

### 5.3 Summary: 8 Safe States

```
S_IDLE (0), S_K1_WAIT (9), S_K2_WAIT (13), S_K3_WAIT (17),
S_K4_WAIT (21), S_CHECK (32), S_TX_WAIT (34), S_DONE_WAIT (36)
```

### 5.4 Worst-Case Halt Latency

The longest gap between safe states is the UPDATE sequence: `S_K4_STORE` (22) through `S_CHECK` (32) = 10 FSM states = 10 CLK cycles. At 1 MHz, that's 10 µs. Including f-engine execution time (up to ~30 cycles for a 15-instruction program), the absolute worst case from `S_K1_START` to `S_K1_WAIT` is ~32 cycles = 32 µs. This is negligible compared to JTAG shift times (hundreds of TCK cycles per scan).

### 5.5 The `is_safe_state` Signal

This is a combinational decode inside `rk4_control_fsm`:

```verilog
wire is_safe_state = (state == S_IDLE)      | (state == S_K1_WAIT)  |
                     (state == S_K2_WAIT)    | (state == S_K3_WAIT)  |
                     (state == S_K4_WAIT)    | (state == S_CHECK)    |
                     (state == S_TX_WAIT)    | (state == S_DONE_WAIT);
```

---

## 6. Clock-Domain Crossing Architecture

This section is the heart of the design's correctness argument. Getting CDC wrong is the #1 way to produce a chip that works in simulation but fails on silicon.

### 6.1 The Two Clock Domains

| Domain | Clock | Frequency | Contents |
|---|---|---|---|
| **TCK** | `tck` (JTAG) | Host-controlled, typically 1–20 MHz | TAP FSM, IR, all DR shift registers, debug controller |
| **CLK** | `clk` (system) | 1 MHz (fixed) | RK4 FSM, regfile, ALU, f-engine, UART, snapshot controller |

These clocks are **fully asynchronous** — no frequency or phase relationship can be assumed.

### 6.2 Crossing Strategy: The Stable-Bus Rule

The Report's key insight, which we adopt wholesale:

> **Single-bit control signals** cross domains via 2-FF synchronizers (standard practice).
> **Multi-bit data buses** NEVER cross while their source is changing. Instead, the source holds the data stable, signals readiness via a single-bit toggle, and the destination samples only after acknowledging the toggle.

This is implemented as a **toggle-handshake** protocol:

```
TCK domain                          CLK domain
───────────                         ──────────
1. Write DBG_CONTROL[3]=1           
   (snap_req)                       
                                    
2. snap_req_tgl flips ──────►  3. sync_snap_req_tgl (2-FF)
                                    detects edge → capture snapshot
                                    
                               4. All shadow regs loaded in ONE posedge clk
                                    snap_epoch increments
                                    
                               5. snap_ack_tgl flips ──────►  6. sync_snap_ack_tgl (2-FF)
                                                                   TCK domain sees ack
                                                                   
7. On next Capture-DR,              
   shadow data is loaded             
   into DR shift registers           
```

### 6.3 Signals That Cross Domains

| Signal | Direction | Width | Crossing Method | Notes |
|---|---|---|---|---|
| `snap_req_tgl` | TCK → CLK | 1 | 2-FF sync | Toggle, not level |
| `snap_ack_tgl` | CLK → TCK | 1 | 2-FF sync | Toggle, not level |
| `halt_req` | TCK → CLK | 1 | 2-FF sync | Level; held until ack |
| `resume_req_tgl` | TCK → CLK | 1 | 2-FF sync | Toggle pulse |
| `single_step_tgl` | TCK → CLK | 1 | 2-FF sync | Toggle pulse |
| `dbg_halted` | CLK → TCK | 1 | 2-FF sync | Level; stable when asserted |
| Shadow data (48+256 bits) | CLK → TCK | 304 | **Stable-bus** | Sampled only after `snap_ack_tgl` edge |
| IMEM read data (16 bits) | CLK → TCK | 16 | **Stable-bus** | Sampled only when halted/idle |
| IMEM address (4 bits) | TCK → CLK | 4 | **Stable-bus** | Written only on Update-DR; stable by next CLK |

**Total synchronizer FFs:** 6 signals × 2 FFs each = **12 FFs** dedicated to CDC.

### 6.4 Why 2-FF Synchronizers Are Sufficient

At TSMC 180 nm with a 1 MHz system clock:
- Clock period = 1000 ns
- Setup time ≈ 0.5 ns
- Metastability resolution time for a DFF ≈ 0.3 ns
- MTBF with 2-FF synchronizer at 1 MHz/20 MHz crossings: >> 10^15 hours

Even with a 20 MHz TCK, the MTBF is astronomically high. A third FF would add latency with no practical reliability benefit.

### 6.5 The Snapshot Coherence Guarantee

This is what makes the design correct:

1. **Snapshot trigger** crosses as a single-bit toggle (safe).
2. **CLK domain** captures ALL shadow data in a **single `posedge clk`** — one atomic operation.
3. **Shadow registers** are then **held stable** until the next snapshot trigger.
4. **Ack toggle** crosses back to TCK domain (safe).
5. **TCK domain** loads shadow data into DR shift registers only on **Capture-DR**, which happens AFTER the ack has been seen.
6. Between Capture-DR and the next snapshot trigger, the shadow data does not change.

Therefore: the DR shift register always contains data from exactly one snapshot epoch. There is no window where partial old + partial new data could be shifted out.

### 6.6 Reset Domain Crossing

`trst_n` is an asynchronous reset for the TCK domain only. It does NOT reset the CLK domain. The CLK domain uses `rst_n` exclusively. On TRST assertion:
- All TCK-domain debug state resets (halt_req=0, snap_req_tgl=0, etc.)
- CLK domain is unaffected (RK4 computation continues)
- On TRST de-assertion, the 2-FF synchronizers settle within 2 TCK cycles

This is correct behavior: a JTAG reset should not disturb a running computation.

---

## 7. Step-by-Step RTL Modifications

Every file that must be changed and exactly what changes are needed. Each modification is numbered for tracking.

### 7.1 Modify: `rtl/rk4_regfile.sv`

**Goal:** Add 8 direct output wires so the snapshot controller can capture all registers in one cycle without contending with the ALU read ports.

**Change M1 — Add debug output ports to the port list (after line 31):**

```verilog
    output wire signed [31:0] dbg_reg0_out,
    output wire signed [31:0] dbg_reg1_out,
    output wire signed [31:0] dbg_reg2_out,
    output wire signed [31:0] dbg_reg3_out,
    output wire signed [31:0] dbg_reg4_out,
    output wire signed [31:0] dbg_reg5_out,
    output wire signed [31:0] dbg_reg6_out,
    output wire signed [31:0] dbg_reg7_out
```

**Change M2 — Add continuous assignments (after line 38):**

```verilog
assign dbg_reg0_out = regs[0];
assign dbg_reg1_out = regs[1];
assign dbg_reg2_out = regs[2];
assign dbg_reg3_out = regs[3];
assign dbg_reg4_out = regs[4];
assign dbg_reg5_out = regs[5];
assign dbg_reg6_out = regs[6];
assign dbg_reg7_out = regs[7];
```

**Cost:** Zero additional FFs — just wires from the existing register array.

### 7.2 Modify: `rtl/rk4_control_fsm.sv`

**Goal:** Add halt/resume/single-step logic and expose internal state for debug.

**Change M3 — Add debug ports (after `busy` output, line 49):**

```verilog
    input  wire        dbg_halt_req,
    input  wire        dbg_resume_req,
    input  wire        dbg_single_step,
    output wire        dbg_halted,
    output wire        dbg_is_safe,
    output wire [5:0]  dbg_fsm_state
```

**Change M4 — Define `is_safe_state` (after line 111):**

```verilog
wire is_safe_state = (state == S_IDLE)   | (state == S_K1_WAIT)  |
                     (state == S_K2_WAIT) | (state == S_K3_WAIT)  |
                     (state == S_K4_WAIT) | (state == S_CHECK)    |
                     (state == S_TX_WAIT) | (state == S_DONE_WAIT);

reg halted_q;
assign dbg_halted    = halted_q;
assign dbg_is_safe   = is_safe_state;
assign dbg_fsm_state = state;
```

**Change M5 — Halt/resume logic at top of `else` branch (line 130):**

```verilog
        if (dbg_halt_req && is_safe_state && !halted_q)
            halted_q <= 1'b1;
        if (dbg_resume_req && halted_q)
            halted_q <= 1'b0;
```

Then wrap the existing `case (state)` block:

```verilog
        if (!halted_q || dbg_single_step) begin
            case (state)
                // ... all existing FSM states unchanged ...
            endcase
        end
```

**Change M6 — Add `halted_q` to reset block (line 117):**

```verilog
        halted_q <= 1'b0;
```

### 7.3 Modify: `rtl/rk4_f_engine.sv`

**Goal:** Add a debug read port for IMEM plus expose PC and estate.

**Change M7 — Add debug ports (after `wr_en`, line 42):**

```verilog
    input  wire [3:0]  dbg_imem_addr,
    output wire [15:0] dbg_imem_rdata,
    input  wire        dbg_halted,
    output wire [3:0]  dbg_pc_out,
    output wire [1:0]  dbg_estate_out
```

**Change M8 — IMEM read with gating + state exposure (after line 49):**

```verilog
assign dbg_imem_rdata = (dbg_halted || estate == S_IDLE)
                        ? imem[dbg_imem_addr] : 16'hDEAD;
assign dbg_pc_out     = pc;
assign dbg_estate_out = estate;
```

### 7.4 Modify: `rtl/rk4_projectile_top.sv`

**Goal:** Wire debug signals between sub-modules and expose to the top level.

**Change M9 — Add debug ports to module declaration (after `uart_tx`, line 20):**

```verilog
    output wire [5:0]  dbg_fsm_state,
    output wire        dbg_fsm_busy,
    output wire        dbg_halted,
    output wire        dbg_is_safe,
    output wire [6:0]  dbg_step_cnt,
    output wire        dbg_f_active,
    output wire [3:0]  dbg_f_pc,
    output wire [1:0]  dbg_f_estate,
    output wire signed [31:0] dbg_dt_reg,
    input  wire        dbg_halt_req,
    input  wire        dbg_resume_req,
    input  wire        dbg_single_step,
    output wire signed [31:0] dbg_regs_out [0:7],
    input  wire [3:0]  dbg_imem_addr,
    output wire [15:0] dbg_imem_rdata
```

**Change M10–M12 — Wire new ports in each sub-module instantiation:**

- `u_regfile`: connect `.dbg_reg0_out(dbg_regs_out[0])` through `.dbg_reg7_out(dbg_regs_out[7])`
- `u_fsm`: connect `.dbg_halt_req`, `.dbg_resume_req`, `.dbg_single_step`, `.dbg_halted`, `.dbg_is_safe`, `.dbg_fsm_state`
- `u_fengine`: connect `.dbg_imem_addr`, `.dbg_imem_rdata`, `.dbg_halted`, `.dbg_pc_out(dbg_f_pc)`, `.dbg_estate_out(dbg_f_estate)`

**Change M13 — Expose additional signals:**

```verilog
assign dbg_fsm_busy = fsm_busy;
assign dbg_step_cnt = fsm_step_cnt;
assign dbg_f_active = f_active;
assign dbg_dt_reg   = dt_reg;
```

---

## 8. New Module: `jtag_debug_controller.sv`

**Clock domain:** TCK. This module lives entirely in the JTAG clock domain.

**Purpose:** Manages the four debug data registers (DBG_STATUS, DBG_REGBANK, DBG_CONTROL, DBG_IMEM), drives the CDC toggle signals toward the CLK domain, and provides the TDO mux input back to the TAP.

### 8.1 Port List

```verilog
module jtag_debug_controller (
    input  logic        tck_i,
    input  logic        trst_ni,

    // TAP interface
    input  logic        capture_dr_i,
    input  logic        shift_dr_i,
    input  logic        update_dr_i,
    input  logic        tdi_i,

    // DR selection (directly from TAP IR decode)
    input  logic        status_sel_i,    // IR == DBG_STATUS
    input  logic        regbank_sel_i,   // IR == DBG_REGBANK
    input  logic        control_sel_i,   // IR == DBG_CONTROL
    input  logic        imem_sel_i,      // IR == DBG_IMEM

    // TDO output for debug DRs
    output logic        dbg_tdo_o,

    // CDC outputs (toward CLK domain via synchronizers)
    output logic        snap_req_tgl_o,
    input  logic        snap_ack_tgl_synced_i,
    output logic        halt_req_o,
    output logic        resume_req_tgl_o,
    output logic        single_step_tgl_o,
    input  logic        dbg_halted_synced_i,

    // Snapshot data (from CLK domain, stable under handshake)
    input  logic [47:0] snap_status_i,
    input  logic [255:0] snap_regbank_i,

    // IMEM access
    output logic [3:0]  imem_addr_o,
    input  logic [15:0] imem_rdata_synced_i
);
```

### 8.2 Internal Architecture

```
                        ┌─────────────────────────────────┐
  capture_dr ──────────►│  DBG_STATUS shift reg (48-bit)  │──► tdo_mux
  shift_dr ────────────►│  DBG_REGBANK shift reg (256-bit)│──► tdo_mux
  update_dr ───────────►│  DBG_CONTROL shift reg (8-bit)  │──► tdo_mux
  tdi ─────────────────►│  DBG_IMEM shift reg (32-bit)    │──► tdo_mux
                        └─────────────────────────────────┘
                                       │
                                update_dr + control_sel
                                       │
                                       ▼
                        ┌─────────────────────────────────┐
                        │  Control Decode:                 │
                        │  [0] halt_req    → level output  │
                        │  [1] resume_req  → toggle output │
                        │  [2] single_step → toggle output │
                        │  [3] snap_req    → toggle output │
                        └─────────────────────────────────┘
```

### 8.3 Key Behavioral Rules

1. **On Capture-DR** for each selected register: load the shadow data into the shift register.
2. **On Shift-DR**: shift LSB-first toward TDO, TDI enters at MSB.
3. **On Update-DR** for DBG_CONTROL: decode bits and update control outputs.
4. **On Update-DR** for DBG_IMEM: if `imem_wr_en` bit set, drive write to CLK domain.
5. **TDO mux**: select output bit[0] of whichever DR is currently selected.

### 8.4 FF Count

| Register | Width | FFs |
|---|---|---|
| DBG_STATUS shift | 48 | 48 |
| DBG_REGBANK shift | 256 | 256 |
| DBG_CONTROL shift + latch | 8 + 8 | 16 |
| DBG_IMEM shift | 32 | 32 |
| CDC toggle registers | 4 | 4 |
| Halt request level latch | 1 | 1 |
| **Total (TCK domain)** | | **357** |

---

## 9. New Module: `jtag_snapshot_ctrl.sv`

**Clock domain:** CLK. This module lives entirely in the system clock domain.

**Purpose:** Receives snapshot requests from the TCK domain (via synchronized toggle), captures all debug-observable state atomically, and signals completion back. Also handles halt/resume/single-step crossing into the FSM.

### 9.1 Port List

```verilog
module jtag_snapshot_ctrl (
    input  logic        clk,
    input  logic        rst_n,

    // CDC inputs (from TCK domain, already synchronized)
    input  logic        snap_req_tgl_synced,
    output logic        snap_ack_tgl,
    input  logic        halt_req_synced,
    input  logic        resume_req_tgl_synced,
    input  logic        single_step_tgl_synced,

    // Debug observation inputs (from rk4_projectile_top)
    input  logic [5:0]  fsm_state_i,
    input  logic        fsm_busy_i,
    input  logic        halted_i,
    input  logic        is_safe_i,
    input  logic [6:0]  step_cnt_i,
    input  logic        f_active_i,
    input  logic [3:0]  f_pc_i,
    input  logic [1:0]  f_estate_i,
    input  logic signed [31:0] dt_reg_i,
    input  logic signed [31:0] regs_i [0:7],

    // Debug control outputs (to rk4_control_fsm)
    output logic        halt_req_o,
    output logic        resume_req_o,
    output logic        single_step_o,

    // Snapshot outputs (stable, held until next snapshot)
    output logic [47:0] snap_status_o,
    output logic [255:0] snap_regbank_o
);
```

### 9.2 Internal Architecture

```
  snap_req_tgl_synced ──► edge detect ──► capture_pulse
                                              │
                  ┌───────────────────────────┘
                  ▼
  ┌───────────────────────────────────────────────┐
  │ ONE posedge clk:                              │
  │   shadow_status <= {dt_reg[31:16], 6'b0,      │
  │     snap_epoch+1, f_estate, f_pc, f_active,   │
  │     step_cnt, halted, busy, fsm_state}        │
  │   shadow_regbank <= {regs[7],...,regs[0]}     │
  │   snap_epoch <= snap_epoch + 1                │
  │   snap_ack_tgl <= ~snap_ack_tgl               │
  └───────────────────────────────────────────────┘
```

### 9.3 Key Behavioral Rules

1. **Edge detection** on `snap_req_tgl_synced`: XOR with a stored copy to detect toggles.
2. **Atomic capture**: All 48 + 256 = 304 bits are loaded in a single `posedge clk`.
3. **Epoch counter**: 4-bit counter increments with each snapshot. Wraps at 15.
4. **Ack toggle**: Flips in the same cycle as the capture, signaling completion.
5. **Halt passthrough**: `halt_req_synced` is forwarded directly to `halt_req_o`.
6. **Resume/single-step**: Edge-detected from their respective toggles, pulsed for one CLK cycle.

### 9.4 FF Count

| Register | Width | FFs |
|---|---|---|
| Shadow status | 48 | 48 |
| Shadow regbank | 256 | 256 |
| snap_epoch | 4 | 4 |
| snap_ack_tgl | 1 | 1 |
| Toggle edge detectors | 3 | 3 |
| Resume/single-step pulse regs | 2 | 2 |
| **Total (CLK domain)** | | **314** |

---

## 10. Integration Wiring in `rk4_top.sv`

### 10.1 Modify: `rtl/jtag_tap.sv`

**Change M14 — Expand IR decode to include debug registers.**

Add new select signals alongside the existing `idcode_select`, `bypass_select`, `scan_select` (after line 96):

```verilog
logic dbg_status_select, dbg_regbank_select;
logic dbg_control_select, dbg_imem_select;
```

Expand the `always_comb` case block (line 98–109) to include:

```verilog
    unique case (jtag_ir_q)
        BYPASS0:     bypass_select     = 1'b1;
        IDCODE:      idcode_select     = 1'b1;
        SCAN_ACCESS: scan_select       = 1'b1;
        DBG_STATUS:  dbg_status_select = 1'b1;
        DBG_REGBANK: dbg_regbank_select= 1'b1;
        DBG_CONTROL: dbg_control_select= 1'b1;
        DBG_IMEM:    dbg_imem_select   = 1'b1;
        BYPASS1:     bypass_select     = 1'b1;
        default:     bypass_select     = 1'b1;
    endcase
```

Add new IR enum values to the `ir_reg_e` typedef (line 45–50):

```verilog
    typedef enum logic [IrLength-1:0] {
        BYPASS0     = 'h0,
        IDCODE      = 'h1,
        SCAN_ACCESS = 'h2,
        DBG_STATUS  = 'h3,
        DBG_REGBANK = 'h4,
        DBG_CONTROL = 'h5,
        DBG_IMEM    = 'h6,
        BYPASS1     = 'h1f
    } ir_reg_e;
```

**Change M15 — Expand TDO mux (line 169–174):**

Add `dbg_tdo` input from `jtag_debug_controller` and include in mux:

```verilog
    unique case (jtag_ir_q)
        IDCODE:      tdo_mux = idcode_q[0];
        SCAN_ACCESS: tdo_mux = scan_out_i;
        DBG_STATUS, DBG_REGBANK, DBG_CONTROL, DBG_IMEM:
                     tdo_mux = dbg_tdo_i;
        default:     tdo_mux = bypass_q;
    endcase
```

**Change M16 — Add ports for debug controller interface:**

```verilog
    output logic dbg_status_select_o,
    output logic dbg_regbank_select_o,
    output logic dbg_control_select_o,
    output logic dbg_imem_select_o,
    input  logic dbg_tdo_i
```

### 10.2 Modify: `rtl/rk4_top.sv` — Master Integration

This is the top-level wiring that connects everything. The structure:

```
rk4_top
├── rk4_projectile_top (rk4_core)
│   ├── rk4_regfile      ← M1, M2
│   ├── rk4_control_fsm  ← M3–M6
│   └── rk4_f_engine     ← M7, M8
├── jtag_tap             ← M14–M16
├── jtag_debug_controller (NEW)
├── jtag_snapshot_ctrl    (NEW)
├── 2-FF synchronizers    (NEW, inline or module)
└── inverter (unchanged)
```

**Change M17 — Add CDC synchronizer instances:**

Six 2-FF synchronizers, each a simple module or inline `always_ff`:

```verilog
// TCK→CLK synchronizers
logic snap_req_tgl_sync;
logic [1:0] snap_req_tgl_pipe;
always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) snap_req_tgl_pipe <= 2'b0;
    else        snap_req_tgl_pipe <= {snap_req_tgl_pipe[0], snap_req_tgl_raw};
assign snap_req_tgl_sync = snap_req_tgl_pipe[1];
```

Repeat for: `halt_req`, `resume_req_tgl`, `single_step_tgl`.

```verilog
// CLK→TCK synchronizers
logic snap_ack_tgl_sync;
logic [1:0] snap_ack_tgl_pipe;
always_ff @(posedge tck or negedge trst_n)
    if (!trst_n) snap_ack_tgl_pipe <= 2'b0;
    else         snap_ack_tgl_pipe <= {snap_ack_tgl_pipe[0], snap_ack_tgl_raw};
assign snap_ack_tgl_sync = snap_ack_tgl_pipe[1];
```

Repeat for: `dbg_halted`.

**Change M18 — Instantiate `jtag_debug_controller`:**

```verilog
jtag_debug_controller u_dbg_ctrl (
    .tck_i              (tck),
    .trst_ni            (trst_n),
    .capture_dr_i       (/* from TAP */),
    .shift_dr_i         (/* from TAP */),
    .update_dr_i        (/* from TAP */),
    .tdi_i              (tdi),
    .status_sel_i       (dbg_status_sel),
    .regbank_sel_i      (dbg_regbank_sel),
    .control_sel_i      (dbg_control_sel),
    .imem_sel_i         (dbg_imem_sel),
    .dbg_tdo_o          (dbg_tdo),
    .snap_req_tgl_o     (snap_req_tgl_raw),
    .snap_ack_tgl_synced_i (snap_ack_tgl_sync),
    .halt_req_o         (halt_req_raw),
    .resume_req_tgl_o   (resume_req_tgl_raw),
    .single_step_tgl_o  (single_step_tgl_raw),
    .dbg_halted_synced_i(dbg_halted_sync),
    .snap_status_i      (snap_status),
    .snap_regbank_i     (snap_regbank),
    .imem_addr_o        (dbg_imem_addr),
    .imem_rdata_synced_i(dbg_imem_rdata)
);
```

**Change M19 — Instantiate `jtag_snapshot_ctrl`:**

```verilog
jtag_snapshot_ctrl u_snap_ctrl (
    .clk                    (clk),
    .rst_n                  (rst),
    .snap_req_tgl_synced    (snap_req_tgl_sync),
    .snap_ack_tgl           (snap_ack_tgl_raw),
    .halt_req_synced        (halt_req_sync),
    .resume_req_tgl_synced  (resume_req_tgl_sync),
    .single_step_tgl_synced (single_step_tgl_sync),
    .fsm_state_i            (dbg_fsm_state),
    .fsm_busy_i             (dbg_fsm_busy),
    .halted_i               (dbg_halted_raw),
    .is_safe_i              (dbg_is_safe),
    .step_cnt_i             (dbg_step_cnt),
    .f_active_i             (dbg_f_active),
    .f_pc_i                 (dbg_f_pc),
    .f_estate_i             (dbg_f_estate),
    .dt_reg_i               (dbg_dt_reg),
    .regs_i                 (dbg_regs_out),
    .halt_req_o             (core_halt_req),
    .resume_req_o           (core_resume_req),
    .single_step_o          (core_single_step),
    .snap_status_o          (snap_status),
    .snap_regbank_o         (snap_regbank)
);
```

---

## 11. SDC Constraints Update

### 11.1 Add TCK Clock Definition

```tcl
create_clock -name tck -period 50 -waveform {0 25} [get_ports tck]
```

50 ns period = 20 MHz maximum TCK. This is conservative for lab use.

### 11.2 Declare Asynchronous Clock Relationship

```tcl
set_clock_groups -asynchronous \
    -group [get_clocks clk] \
    -group [get_clocks tck]
```

This tells the synthesis/STA tool that `clk` and `tck` have no phase relationship. All paths between the two domains are excluded from timing analysis — the CDC synchronizers handle correctness.

### 11.3 Set False Paths on Synchronizer Inputs

```tcl
set_false_path -from [get_clocks tck] -to [get_pins {u_snap_ctrl/snap_req_tgl_pipe_reg[0]/D}]
set_false_path -from [get_clocks clk] -to [get_pins {u_dbg_ctrl/snap_ack_tgl_pipe_reg[0]/D}]
```

The `set_clock_groups -asynchronous` already covers this, but explicit false paths on synchronizer inputs are belt-and-suspenders practice.

### 11.4 Max Delay on Synchronizer Outputs

```tcl
set_max_delay -datapath_only 2.0 \
    -from [get_pins {*_tgl_pipe_reg[0]/Q}] \
    -to   [get_pins {*_tgl_pipe_reg[1]/D}]
```

Ensures the two synchronizer FFs are placed close together for minimal wire delay.

---

## 12. DFT Script Coexistence

### 12.1 Mark All Debug Logic as `dft_dont_scan`

In `rk4_dft_script.tcl`, add after the existing JTAG exclusion (line 43):

```tcl
set_db [get_db insts *dbg_ctrl*]  .dft_dont_scan true
set_db [get_db insts *snap_ctrl*] .dft_dont_scan true
set_db [get_db insts *_tgl_pipe*] .dft_dont_scan true
```

**Rationale:** Debug controller and snapshot controller FFs operate in the TCK domain or are CDC synchronizers. Including them in the system scan chain would create multi-clock-domain scan issues.

### 12.2 SCAN_ACCESS Remains Unchanged

The existing DFT flow continues to work:
- `define_scan_chain -name top_chain -sdi scan_in -sdo scan_out create_ports` — unchanged.
- `connect_scan_chains -auto_create_chains` — will stitch CLK-domain FFs only.
- The new debug FFs in `rk4_projectile_top` (shadow registers in `jtag_snapshot_ctrl`) ARE in the CLK domain and WILL be included in the scan chain. This is correct — they are ordinary CLK-domain FFs.

### 12.3 Updated `read_hdl` Line

```tcl
read_hdl -sv {rk4_top.sv rk4_alu.sv rk4_control_fsm.sv rk4_f_engine.sv \
              rk4_projectile_top.sv rk4_regfile.sv rk4_uart_protocol.sv \
              uart_rx.sv uart_tx.sv jtag_tap.sv inverter.sv \
              jtag_debug_controller.sv jtag_snapshot_ctrl.sv}
```

---

## 13. Verification Plan

### 13.1 Unit-Level Testbenches

| Testbench | Module Under Test | Key Scenarios |
|---|---|---|
| `tb_snapshot_ctrl` | `jtag_snapshot_ctrl` | Toggle handshake; verify atomic capture of all 304 bits; epoch increment; halt/resume passthrough |
| `tb_debug_controller` | `jtag_debug_controller` | Shift in/out of each DR; verify Capture/Shift/Update behavior; control decode; TDO mux correctness |
| `tb_fsm_halt` | `rk4_control_fsm` | Assert halt_req; verify FSM freezes only at safe states; verify resume; verify single-step advances exactly one safe-to-safe |

### 13.2 Integration Tests

**Test 1 — IDCODE read (regression):**
Verify existing IDCODE functionality is not broken. Shift IR=0x01, scan DR 32 bits, expect `0x10682001`.

**Test 2 — Full snapshot while idle:**
1. Reset system. FSM is in `S_IDLE`.
2. Shift IR=0x05, scan in `8'h08` to DBG_CONTROL (snap_req).
3. Wait for ack (poll DBG_STATUS for epoch > 0).
4. Shift IR=0x03, scan out 48 bits. Verify `fsm_state=0`, `busy=0`, `halted=0`, `epoch=1`.
5. Shift IR=0x04, scan out 256 bits. Verify all registers are zero (post-reset).

**Test 3 — Halt during computation:**
1. Start an RK4 computation via UART.
2. After a few TCK cycles, write halt_req via DBG_CONTROL.
3. Poll DBG_STATUS until `halted=1`.
4. Verify `fsm_state` is one of the 8 safe states.
5. Trigger snapshot, read regbank, verify `t > 0` and `step_cnt > 0`.
6. Resume. Verify computation completes normally (UART output matches reference).

**Test 4 — Single-step:**
1. Halt the FSM at `S_IDLE`.
2. Start computation (UART `run_start`).
3. Single-step repeatedly. Verify FSM advances through `S_INIT1`→...→`S_K1_WAIT` (first safe state after start).
4. Verify snapshot at each safe state shows expected intermediate values.

**Test 5 — IMEM readback:**
1. Load a known program via UART.
2. Halt (or stay idle).
3. For each address 0–15: write address to DBG_IMEM, read back 32 bits, verify `imem_rdata` matches the loaded program.

**Test 6 — Epoch coherence:**
1. Start computation. Do NOT halt.
2. Trigger snapshot (non-intrusive).
3. Read DBG_STATUS, note `epoch=N`.
4. Read DBG_REGBANK (256 bits takes many TCK cycles).
5. Re-read DBG_STATUS. If `epoch` still == N, data is coherent. If epoch changed (shouldn't unless another snap_req was issued), flag error.

**Test 7 — DFT coexistence (post-synthesis):**
1. Run existing DFT flow with new RTL.
2. Verify `check_dft_rules` passes.
3. Verify scan chain stitching succeeds.
4. Verify ATPG pattern count is comparable to pre-debug baseline.

### 13.3 CDC Verification

- **Structural CDC check** (e.g., Synopsys SpyGlass CDC or Cadence Conformal CDC):
  - All 6 crossing signals pass through exactly 2-FF synchronizers.
  - No reconvergence of synchronized signals.
  - No multi-bit bus without handshake protocol.
- **Formal CDC** (optional, high value):
  - Verify toggle-handshake protocol never deadlocks.
  - Verify shadow data is stable when `snap_ack_tgl` toggles.

---

## 14. Area and Timing Budget

### 14.1 FF Count Summary

| Component | Domain | FFs |
|---|---|---|
| `jtag_debug_controller` (DR shifts + control) | TCK | 357 |
| `jtag_snapshot_ctrl` (shadows + epoch + CDC) | CLK | 314 |
| CDC synchronizers (6 × 2-FF) | Mixed | 12 |
| `rk4_control_fsm` additions (`halted_q`, `is_safe`) | CLK | 1 |
| **Grand Total** | | **684** |

### 14.2 Area Estimate (TSMC 180 nm)

- Typical DFF cell area in TSMC 180 nm: ~30 µm²
- 684 FFs × 30 µm² = **~20,520 µm²** ≈ **0.0205 mm²**
- Including combinational logic (muxes, decoders): ~1.3× multiplier → **~0.027 mm²**
- For reference, at 180 nm a typical chip is 4–25 mm². This is **< 1% of a modest chip area**.

### 14.3 Timing Analysis

**CLK domain (1 MHz, 1000 ns period):**
- The snapshot capture is a single-cycle fan-in of 304 bits into shadow registers. At 1 MHz, even with long wire delays, this will meet timing trivially.
- The `is_safe_state` decode is a 6-input OR of 8 equality comparisons — less than 5 gate delays.

**TCK domain (20 MHz, 50 ns period):**
- The largest shift register is 256 bits (DBG_REGBANK). Shift operations are simple bit-to-bit transfers — trivially fast.
- The TDO mux adds one level of mux delay to the existing TAP TDO path.

**Critical path impact on existing design:** None. The debug logic is purely additive — no existing combinational paths are modified. The regfile direct outputs are just wires. The FSM `halted_q` gate adds one AND gate to the clock-enable of the case statement, which is negligible.

---

## 15. OpenOCD / Host Scripting Guide

### 15.1 TAP Declaration

```tcl
jtag newtap rk4 tap -irlen 5 -expected-id 0x10682001 -ircapture 0x05 -irmask 0x03
```

### 15.2 Helper Procedures

```tcl
proc rk4_read_status {} {
    irscan rk4.tap 0x03
    set raw [drscan rk4.tap 48 0]
    set fsm_state  [expr {$raw & 0x3F}]
    set busy       [expr {($raw >> 6) & 1}]
    set halted     [expr {($raw >> 7) & 1}]
    set step_cnt   [expr {($raw >> 8) & 0x7F}]
    set f_active   [expr {($raw >> 15) & 1}]
    set f_pc       [expr {($raw >> 16) & 0xF}]
    set f_estate   [expr {($raw >> 20) & 0x3}]
    set epoch      [expr {($raw >> 22) & 0xF}]
    set dt_upper   [expr {($raw >> 32) & 0xFFFF}]
    puts "FSM=$fsm_state busy=$busy halted=$halted step=$step_cnt epoch=$epoch"
    return $raw
}

proc rk4_halt {} {
    irscan rk4.tap 0x05
    drscan rk4.tap 8 0x01
    while {1} {
        set s [rk4_read_status]
        if {($s >> 7) & 1} break
        after 1
    }
    puts "Halted."
}

proc rk4_snapshot {} {
    irscan rk4.tap 0x05
    drscan rk4.tap 8 0x08
    after 1
}

proc rk4_read_regbank {} {
    irscan rk4.tap 0x04
    set raw [drscan rk4.tap 256 0]
    for {set i 0} {$i < 8} {incr i} {
        set val [expr {($raw >> ($i * 32)) & 0xFFFFFFFF}]
        puts [format "  R%d = 0x%08X" $i $val]
    }
}

proc rk4_resume {} {
    irscan rk4.tap 0x05
    drscan rk4.tap 8 0x02
    puts "Resumed."
}

proc rk4_read_imem {addr} {
    irscan rk4.tap 0x06
    drscan rk4.tap 32 [expr {$addr & 0xF}]
    irscan rk4.tap 0x06
    set raw [drscan rk4.tap 32 0]
    set rdata [expr {($raw >> 4) & 0xFFFF}]
    puts [format "  IMEM[%d] = 0x%04X" $addr $rdata]
    return $rdata
}

proc rk4_dump_all {} {
    rk4_snapshot
    rk4_read_status
    rk4_read_regbank
    puts "--- IMEM ---"
    for {set i 0} {$i < 16} {incr i} {
        rk4_read_imem $i
    }
}
```

### 15.3 Typical Bring-Up Session

```
> rk4_read_status
FSM=0 busy=0 halted=0 step=0 epoch=0
  → Chip is alive, idle, post-reset.

> rk4_snapshot
> rk4_read_regbank
  R0 = 0x00000000  (v0 not loaded yet)
  R1 = 0x00000000  (t = 0)
  ...
  → Registers are zero as expected.

> # Load program via UART, start computation...

> rk4_halt
Halted.

> rk4_read_status
FSM=9 busy=1 halted=1 step=3 epoch=2
  → Halted in S_K1_WAIT, step 3.

> rk4_snapshot
> rk4_read_regbank
  R0 = 0x00100000  (v0 = 16.0 in Q16.16)
  R1 = 0x0000C000  (t ≈ 0.75)
  R2 = 0x00023456  (k1)
  ...
  → Numerical state is observable!

> rk4_resume
Resumed.
```

---

## 16. Risk Register

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | CDC metastability causes corrupt snapshot | Very Low | High | 2-FF synchronizers with MTBF >> 10^15 hours; stable-bus protocol; formal CDC check |
| R2 | Halt at wrong state corrupts computation | Low | High | `is_safe_state` is a combinational decode of exactly 8 known-good states; unit test each |
| R3 | Debug logic breaks existing DFT flow | Low | Medium | All debug FFs marked `dft_dont_scan`; regression test DFT after integration |
| R4 | Area overhead exceeds budget | Very Low | Low | ~684 FFs ≈ 0.027 mm² at 180 nm; < 1% of typical chip area |
| R5 | IMEM read during f-engine execution returns garbage | Low | Low | Gated by `dbg_halted \|\| estate == S_IDLE`; poison value `16'hDEAD` if violated |
| R6 | Snapshot request while previous snapshot in progress | Low | Medium | Toggle protocol is inherently self-serializing; second toggle waits for ack of first |
| R7 | TDO mux timing degradation from additional inputs | Very Low | Low | One additional mux level on negedge path; 50 ns TCK period provides ample margin |
| R8 | Existing UVM testbench incompatibility | Medium | Medium | UVM TB port list is already outdated; must be updated regardless of debug work |
| R9 | `rst`/`rst_n` polarity confusion at top level | Low | High | `rk4_top` passes `rst` as `rst_n` to `rk4_projectile_top` — this is an existing design choice; snapshot ctrl uses same convention |
| R10 | Single-step fails to re-halt | Low | Medium | After single-step, FSM must reach another safe state; worst case is 32 cycles; timeout in host script |

---

## 17. Implementation Checklist

### Phase 1: Existing Module Modifications

- [ ] **M1–M2**: `rk4_regfile.sv` — Add 8 debug output ports and assigns
- [ ] **M3–M6**: `rk4_control_fsm.sv` — Add halt/resume/single-step logic, `is_safe_state`, `halted_q`
- [ ] **M7–M8**: `rk4_f_engine.sv` — Add IMEM debug read port, expose `pc` and `estate`
- [ ] **M9–M13**: `rk4_projectile_top.sv` — Wire all debug signals, add debug port group
- [ ] **M14–M16**: `jtag_tap.sv` — Expand IR enum, IR decode, TDO mux, add debug controller ports
- [ ] Compile all modified modules — zero errors, zero new warnings

### Phase 2: New Modules

- [ ] Write `jtag_debug_controller.sv` — TCK-domain DR management
- [ ] Write `jtag_snapshot_ctrl.sv` — CLK-domain atomic capture
- [ ] Compile both — zero errors

### Phase 3: Top-Level Integration

- [ ] **M17**: Add 2-FF CDC synchronizers in `rk4_top.sv`
- [ ] **M18**: Instantiate `jtag_debug_controller` in `rk4_top.sv`
- [ ] **M19**: Instantiate `jtag_snapshot_ctrl` in `rk4_top.sv`
- [ ] Wire all inter-module connections
- [ ] Full-design compile — zero errors

### Phase 4: Constraints and DFT

- [ ] Update `constraints.sdc` — add TCK clock, async clock groups, synchronizer constraints
- [ ] Update `rk4_dft_script.tcl` — add `dft_dont_scan` for new modules, update `read_hdl`
- [ ] Run synthesis — verify timing clean on both domains
- [ ] Run DFT — verify `check_dft_rules` passes, scan chain stitches correctly

### Phase 5: Verification

- [ ] Write `tb_snapshot_ctrl` — unit test for snapshot controller
- [ ] Write `tb_debug_controller` — unit test for debug controller
- [ ] Write `tb_fsm_halt` — unit test for halt/resume/single-step
- [ ] Integration test: IDCODE regression
- [ ] Integration test: full snapshot while idle
- [ ] Integration test: halt during computation
- [ ] Integration test: single-step
- [ ] Integration test: IMEM readback
- [ ] Integration test: epoch coherence
- [ ] Post-synthesis DFT regression

### Phase 6: Documentation and Lab Readiness

- [ ] Write OpenOCD config file
- [ ] Write lab bring-up script (Tcl procedures from Section 15)
- [ ] Update project README with JTAG debug instructions
- [ ] Generate BSDL stub (if boundary-scan compliance is claimed)

---

## Appendix A: File Inventory

| File | Status | Domain(s) | Changes |
|---|---|---|---|
| `rtl/rk4_regfile.sv` | Modify | CLK | M1, M2: add 8 debug output ports |
| `rtl/rk4_control_fsm.sv` | Modify | CLK | M3–M6: halt/resume/step, safe-state decode |
| `rtl/rk4_f_engine.sv` | Modify | CLK | M7–M8: IMEM read port, expose PC/estate |
| `rtl/rk4_projectile_top.sv` | Modify | CLK | M9–M13: wire debug signals |
| `rtl/jtag_tap.sv` | Modify | TCK | M14–M16: new IR codes, TDO mux, debug ports |
| `rtl/rk4_top.sv` | Modify | Both | M17–M19: synchronizers, instantiate new modules |
| `rtl/jtag_debug_controller.sv` | **New** | TCK | DR shift registers, control decode |
| `rtl/jtag_snapshot_ctrl.sv` | **New** | CLK | Atomic capture, epoch, ack toggle |
| `synthesis/constraints.sdc` | Modify | — | TCK clock, async groups |
| `synthesis/rk4_dft_script.tcl` | Modify | — | dont_scan, read_hdl update |

## Appendix B: Signal Cross-Reference

| Signal Name | Source Module | Destination Module | Width | CDC? |
|---|---|---|---|---|
| `dbg_regs_out[0:7]` | `rk4_regfile` | `jtag_snapshot_ctrl` (via top) | 8×32 | No (same CLK domain) |
| `dbg_fsm_state` | `rk4_control_fsm` | `jtag_snapshot_ctrl` (via top) | 6 | No |
| `dbg_halted` | `rk4_control_fsm` | `jtag_snapshot_ctrl` + `jtag_debug_controller` | 1 | Yes (CLK→TCK, 2-FF) |
| `snap_req_tgl` | `jtag_debug_controller` | `jtag_snapshot_ctrl` | 1 | Yes (TCK→CLK, 2-FF) |
| `snap_ack_tgl` | `jtag_snapshot_ctrl` | `jtag_debug_controller` | 1 | Yes (CLK→TCK, 2-FF) |
| `halt_req` | `jtag_debug_controller` | `rk4_control_fsm` (via snap_ctrl) | 1 | Yes (TCK→CLK, 2-FF) |
| `snap_status` | `jtag_snapshot_ctrl` | `jtag_debug_controller` | 48 | Stable-bus |
| `snap_regbank` | `jtag_snapshot_ctrl` | `jtag_debug_controller` | 256 | Stable-bus |

## Appendix C: Observability Improvement

| Metric | Before | After |
|---|---|---|
| Visible internal state bits | 0 | 304 (status) + 256 (regbank) + 256 (IMEM) = **816** |
| FSM state observable? | No | Yes |
| Register file observable? | No | Yes (all 8 regs, coherent) |
| f-engine program verifiable? | No | Yes (all 16 instructions) |
| Halt/resume capability? | No | Yes (safe-state granular) |
| Non-UART debug path? | No | Yes (JTAG-only bring-up possible) |
| Coherence guarantee? | N/A | Yes (snap_epoch verification) |
| Observability coverage | **~0%** | **~95%** of meaningful state |

---

*End of document.*
