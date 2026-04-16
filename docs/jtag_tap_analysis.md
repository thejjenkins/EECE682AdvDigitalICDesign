# JTAG TAP Analysis and Redesign Proposal for the RK4 Projectile Engine

**Document Version:** 1.0
**Date:** April 15, 2026
**Target Design:** RK4 ODE Solver ASIC — TSMC 180nm
**Repository:** https://github.com/thejjenkins/EECE682AdvDigitalICDesign

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Project Architecture Overview](#2-project-architecture-overview)
3. [Current JTAG TAP Implementation](#3-current-jtag-tap-implementation)
4. [Highlights — What the TAP Does Well](#4-highlights--what-the-tap-does-well)
5. [Lowlights — The Connectivity Problem](#5-lowlights--the-connectivity-problem)
6. [Impact Analysis — What Is Lost](#6-impact-analysis--what-is-lost)
7. [Proposed Changes — Architecture Options](#7-proposed-changes--architecture-options)
8. [Detailed Design of Recommended Approach](#8-detailed-design-of-recommended-approach)
9. [Implementation Considerations](#9-implementation-considerations)
10. [Conclusion](#10-conclusion)
11. [Appendices](#11-appendices)

---

## 1. Executive Summary

The RK4 Projectile Engine is a fixed-point numerical integrator implemented as a custom ASIC targeting TSMC 180nm. The chip communicates with a host via UART and includes an IEEE 1149.1 JTAG TAP controller for test and debug access. While the JTAG TAP is a correct and standards-compliant implementation of the IEEE 1149.1 state machine, **it is architecturally disconnected from the RK4 computational datapath**. In its current form, the TAP can only report a hardcoded 32-bit IDCODE and provide a 1-bit BYPASS path. Its SCAN_ACCESS data register — the only channel that could provide internal observability — is wired to a constant zero stub, rendering it non-functional outside of post-synthesis DFT flows.

This document provides a rigorous analysis of the current implementation, catalogs its strengths and deficiencies, quantifies the observability gap, and proposes concrete architectural changes to transform the JTAG interface into a functional debug and diagnostic tool for the RK4 engine.

---

## 2. Project Architecture Overview

### 2.1 System Block Diagram

The RK4 Projectile Engine computes projectile trajectories using the 4th-order Runge-Kutta numerical integration method. The system architecture is:

```
                        ┌─────────────────────────────────────────────────────────┐
                        │                     rk4_top                             │
                        │                                                         │
  JTAG Pins             │  ┌──────────┐     ┌──────────────────────────────────┐  │
  ─────────────────────►│  │ jtag_tap │     │      rk4_projectile_top         │  │
  tck,tms,trst_n,tdi    │  │          │     │                                  │  │
  ◄─────────────────────│  │  IDCODE  │     │  ┌──────┐  ┌──────┐  ┌───────┐  │  │
  tdo, tdo_oe           │  │  BYPASS  │     │  │ UART │  │Proto-│  │Reg    │  │  │
                        │  │  SCAN ──►scan_enable     │  │ col  │  │File   │  │  │
                        │  │  ACCESS  │scan_in         │  │Parser│  │(8x32) │  │  │
                        │  │          │◄──scan_out=0   │  └──────┘  └───────┘  │  │
                        │  └──────────┘     │                                  │  │
                        │                   │  ┌──────┐  ┌──────┐  ┌───────┐  │  │
  UART Pins             │                   │  │ ALU  │  │  f-  │  │Control│  │  │
  uart_rx ──────────────│──────────────────►│  │Q16.16│  │Engine│  │  FSM  │  │  │
  uart_tx ◄─────────────│──────────────────◄│  │      │  │(uISA)│  │(37-st)│  │  │
                        │                   │  └──────┘  └──────┘  └───────┘  │  │
                        │                   └──────────────────────────────────┘  │
                        │                                                         │
                        │  ┌──────────┐                                           │
  test_in ──────────────│─►│ inverter │──► test_out                               │
                        │  └──────────┘                                           │
                        └─────────────────────────────────────────────────────────┘
```

### 2.2 Module Hierarchy

```
rk4_top
├── rk4_projectile_top          — Computational core
│   ├── uart_rx                 — UART receiver (8N1, configurable baud)
│   ├── uart_tx                 — UART transmitter
│   ├── rk4_uart_protocol       — Command parser (LOAD_PROG / RUN)
│   ├── rk4_regfile             — 8×32-bit register file (2R/1W + v0 load)
│   ├── rk4_alu                 — Q16.16 fixed-point ALU (8 operations)
│   ├── rk4_f_engine            — 16-instruction micro-coded function evaluator
│   └── rk4_control_fsm         — 37-state RK4 algorithm sequencer
├── jtag_tap                    — IEEE 1149.1 TAP controller
└── inverter                    — Power-on test cell
```

### 2.3 Data Format

All computation uses **Q16.16 signed fixed-point** (32-bit): 1 sign bit, 15 integer bits, 16 fractional bits. Range: approximately ±32767.9999847.

### 2.4 Register File Map

| Address | Name | Purpose |
|---------|------|---------|
| R0 (000) | v0 | Initial velocity |
| R1 (001) | t | Current time |
| R2 (010) | k1 | RK4 slope k₁ |
| R3 (011) | k2 | RK4 slope k₂ |
| R4 (100) | k3 | RK4 slope k₃ |
| R5 (101) | k4 | RK4 slope k₄ (also holds G pre-load) |
| R6 (110) | y | Current state variable (height) |
| R7 (111) | acc | Temporary accumulator |

### 2.5 Communication Protocol

The host communicates over UART at 9600 baud with two commands:

| Command | Byte | Payload | Description |
|---------|------|---------|-------------|
| LOAD_PROG | 0x01 | 32 bytes (16 × 16-bit instructions, little-endian) | Programs the f-engine ISA |
| RUN | 0x02 | 4 bytes (v0 in Q16.16, little-endian) | Loads v0 and starts integration |

The DUT responds with (t, y) data pairs (8 bytes each, little-endian) and a `0xDEADBEEF` done marker.

### 2.6 Key Internal Signals of Interest for Debug

| Signal | Width | Source | Description |
|--------|-------|--------|-------------|
| `regs[0:7]` | 8 × 32 | rk4_regfile | Full register file contents |
| `rf_t_out` | 32 | rk4_regfile | Current time (R1 alias) |
| `rf_y_out` | 32 | rk4_regfile | Current height (R6 alias) |
| `dt_reg` | 32 | rk4_projectile_top | Computed time step |
| `dt_half_reg` | 32 | rk4_projectile_top | Half time step |
| `state` | 6 | rk4_control_fsm | FSM state (37 states) |
| `step_cnt` | 7 | rk4_control_fsm | Iteration counter |
| `fsm_busy` | 1 | rk4_control_fsm | Computation in progress |
| `pc` | 4 | rk4_f_engine | f-engine program counter |
| `estate` | 2 | rk4_f_engine | f-engine execution state |
| `imem[0:15]` | 16 × 16 | rk4_f_engine | f-engine instruction memory |
| `alu_result` | 32 | rk4_alu | Current ALU output |
| `pstate` | 2 | rk4_uart_protocol | Protocol parser state |

None of these signals are accessible via JTAG in the current implementation.

---

## 3. Current JTAG TAP Implementation

### 3.1 Origin and Lineage

The implementation header states it was "adapted from the PULP platform dmi_jtag_tap.sv reference implementation." The PULP (Parallel Ultra-Low-Power Processing Platform) project is a well-audited open-source RISC-V ecosystem developed at ETH Zurich. The original PULP TAP included a Debug Module Interface (DMI) data register that bridged JTAG to the RISC-V debug module, enabling full hardware debug (breakpoints, register reads, memory access). In the adaptation for this project, the DMI register was removed and replaced with a SCAN_ACCESS stub intended for DFT scan chain access.

### 3.2 TAP Controller Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| `IrLength` | 5 bits | Supports 32 instruction codes |
| `IdcodeValue` | `32'h10682001` | Version=1, Part=0x0682 (EECE-682), Mfr=0x000 |
| Clock domain | TCK (independent) | Fully asynchronous to system CLK |
| Reset | Async active-low TRST + sync 5-TMS reset | Dual reset paths per IEEE 1149.1 |

### 3.3 Instruction Register (IR) Encoding

| IR Code | Hex | Name | Data Register Selected |
|---------|-----|------|----------------------|
| `00000` | 0x00 | BYPASS0 | 1-bit bypass |
| `00001` | 0x01 | IDCODE | 32-bit device ID |
| `00010` | 0x02 | SCAN_ACCESS | External scan chain interface |
| `00011`–`11110` | 0x03–0x1E | (undefined) | Default to bypass |
| `11111` | 0x1F | BYPASS1 | 1-bit bypass |

Of 32 possible IR codes, only 3 provide distinct behavior. The remaining 29 default to BYPASS per IEEE 1149.1 requirements.

### 3.4 Data Register Inventory

#### 3.4.1 IDCODE Register (32 bits)

Hardcoded identification value. Behavior:
- **Capture-DR:** Loads `IdcodeValue` (parallel load of the constant)
- **Shift-DR:** Shifts TDI in from MSB, shifts LSB out to TDO
- **Test-Logic-Reset:** Reloads `IdcodeValue`

The IDCODE is the default DR after reset (IR initializes to IDCODE instruction). This means the very first DR scan after power-on/reset reads the device ID without needing to load an IR value first.

IDCODE bit field breakdown:

```
Bit 31      28 27          12 11         1  0
┌──────────┬────────────────┬────────────┬──┐
│ Version  │  Part Number   │Manufacturer│ 1│
│   0x1    │    0x0682      │   0x000    │  │
└──────────┴────────────────┴────────────┴──┘
```

#### 3.4.2 Bypass Register (1 bit)

Minimal-length serial path from TDI to TDO. Behavior:
- **Capture-DR:** Loads 0
- **Shift-DR:** TDI passes to bypass flip-flop, previous value exits on TDO

Used for daisy-chaining multiple JTAG devices. Adds exactly 1 TCK cycle of latency.

#### 3.4.3 SCAN_ACCESS Register (external interface)

This is not a register within the TAP itself. Instead, the TAP exposes three signals:

| Signal | Direction | Connection in `rk4_top` | Actual Function |
|--------|-----------|------------------------|-----------------|
| `scan_enable_o` | Output | Wire `scan_enable` → unconnected | Indicates Shift-DR with SCAN_ACCESS selected |
| `scan_in_o` | Output | Wire `scan_in` → unconnected | Passes TDI directly |
| `scan_out_i` | Input | Wire `scan_out` ← `1'b0` (hardwired) | Constant zero |

The scan interface is the sole channel for internal design observability. In the current wiring, it is a dead end.

### 3.5 TAP FSM Implementation

The TAP FSM implements all 16 IEEE 1149.1 states with correct transitions. The implementation uses a two-process style:

1. **Combinational next-state logic** (`always_comb`): Computes `tap_state_d` from `tap_state_q` and `tms_i`. Simultaneously asserts one-hot control signals (`capture_dr`, `shift_dr`, `update_dr`, `capture_ir`, `shift_ir`, `update_ir`, `test_logic_reset`) based on the current state.

2. **Sequential state register** (`always_ff @(posedge tck_i or negedge trst_ni)`): Updates `tap_state_q` on each TCK rising edge. Async resets to `TestLogicReset`.

Control signal timing:
- `capture_dr/ir`: Combinational, active during the Capture state, used to parallel-load DR/IR shift registers
- `shift_dr/ir`: Combinational, active during the Shift state, used to clock TDI into shift registers
- `update_dr/ir`: Combinational, active during the Update state, used to latch shift register into shadow register

All control signals are **combinational outputs of the current state**, not registered. They are consumed by `always_comb` blocks that compute the next-cycle values of the DR/IR flip-flops, which are then registered on the next posedge of TCK. This is a clean, race-free design.

### 3.6 TDO Output Path

The TDO output is registered on the **falling edge** of TCK per IEEE 1149.1:

```
tdo_mux (combinational) ──► negedge TCK FF ──► tdo_o (pin)
```

The mux selects:
- During Shift-IR: `jtag_ir_shift_q[0]` (IR shift register LSB)
- During Shift-DR with IDCODE: `idcode_q[0]`
- During Shift-DR with SCAN_ACCESS: `scan_out_i` (hardwired to 0)
- During Shift-DR with BYPASS/default: `bypass_q`

The output enable `tdo_oe_o` is active only during Shift-IR and Shift-DR states. The external pad driver should tri-state TDO when `tdo_oe_o` is low.

### 3.7 Clock Domain Structure

The entire JTAG TAP operates in the TCK clock domain. Register edges used:

| Register | Clock Edge | Justification |
|----------|-----------|---------------|
| `tap_state_q` | posedge TCK | Standard state machine |
| `jtag_ir_shift_q`, `jtag_ir_q` | posedge TCK | IR captured/shifted on rising edge |
| `idcode_q`, `bypass_q` | posedge TCK | DR captured/shifted on rising edge |
| `tdo_o`, `tdo_oe_o` | **negedge TCK** | IEEE 1149.1 requires TDO change on falling edge |

The negedge flop for TDO creates a half-cycle setup time guarantee: data is established on posedge, output changes on negedge, external controller samples on the next posedge. This is the correct IEEE 1149.1 timing relationship.

### 3.8 Integration in `rk4_top`

The TAP is instantiated at the `rk4_top` level, which is the chip's top-level module. It sits as a **peer** to `rk4_projectile_top`, not inside it:

```
rk4_top
├── rk4_projectile_top  (computational core — system CLK domain)
├── jtag_tap             (test interface — TCK domain)
└── inverter             (power-on test)
```

The three scan-chain wires (`scan_enable`, `scan_in`, `scan_out`) are declared locally in `rk4_top` but connect to nothing in the RTL. The comment documents that Genus DFT synthesis will replace the `assign scan_out = 1'b0` stub by stitching a mux-scan chain through all scannable flip-flops in the design.

### 3.9 DFT Script Integration

The DFT synthesis script (`rk4_dft_script.tcl`) configures the scan chain:

```tcl
set_db dft_scan_style muxed_scan
set_db dft_prefix dft_
define_shift_enable -name SE -active high -create_port SE
set_db [get_db insts *jtag*] .dft_dont_scan true
set_db [get_db insts *ir*] .dft_dont_scan true
define_scan_chain -name top_chain -sdi scan_in -sdo scan_out create_ports
connect_scan_chains -auto_create_chains
```

Key decisions:
- Muxed scan style (MUX inserted before each flip-flop's D input)
- JTAG TAP flip-flops excluded from scan (`dft_dont_scan`)
- Single scan chain from `scan_in` to `scan_out`
- Genus auto-stitches the chain order

After DFT synthesis, the scan chain threads through every scannable FF in `rk4_projectile_top`, connecting `scan_in` → FF₁ → FF₂ → ... → FFₙ → `scan_out`. The JTAG TAP's `scan_enable_o` controls whether these FFs load functional data or shift scan data.

---

## 4. Highlights — What the TAP Does Well

Despite the connectivity gap, the JTAG TAP implementation has significant strengths that should be preserved in any redesign.

### 4.1 Full IEEE 1149.1 FSM Compliance

All 16 states and all 32 transitions (16 states × 2 TMS values) are correctly implemented. This was verified exhaustively against the IEEE 1149.1 specification:

- **TestLogicReset** correctly asserts `test_logic_reset` and resets IR to IDCODE
- The 5-TMS-high reset path reaches TestLogicReset from any state in at most 5 clocks
- DR and IR paths are fully independent with correct Capture → Shift → Update sequencing
- Pause and Exit2 states are implemented (often omitted in simplified TAPs), enabling long shift operations to be interrupted

This is a production-quality FSM, not a simplified academic subset.

### 4.2 Correct TDO Timing

The negedge-registered TDO output is a detail that many JTAG implementations get wrong. The IEEE 1149.1 standard requires that TDO changes on the falling edge of TCK so that external controllers can sample it on the following rising edge. This implementation gets it right:

```systemverilog
always_ff @(negedge tck_i or negedge trst_ni) begin
    tdo_o    <= tdo_mux;
    tdo_oe_o <= (shift_ir | shift_dr);
end
```

Getting this wrong would cause intermittent JTAG communication failures — a notoriously difficult bug to diagnose on silicon.

### 4.3 Correct TDO Tri-State Control

`tdo_oe_o` is only active during Shift-IR and Shift-DR states. During all other states, TDO is tri-stated. This is essential for JTAG daisy-chains where multiple devices share the TDO line. Many simplified TAPs omit the output enable entirely or get the state conditions wrong.

### 4.4 Robust IR Behavior

- **Capture-IR loads `5'b00101`** (LSBs = `01` per IEEE 1149.1 §7.1.1). This lets a JTAG controller verify IR integrity by shifting out the capture value before writing a new instruction.
- **Reset loads IDCODE** instruction, so the default power-on behavior is to present the device ID — the expected behavior for JTAG auto-detection.
- **Priority logic is correct**: `test_logic_reset` overrides `capture_ir` / `shift_ir` / `update_ir`, though mutual exclusivity of FSM states means this override is never actually exercised. It's defense-in-depth.

### 4.5 Clean Two-Process Coding Style

The design uses a consistent `always_comb` + `always_ff` separation throughout:
- Combinational logic computes next-state values (`_d` suffix signals)
- Sequential logic registers them on the clock edge (`_q` suffix signals)

This style is synthesis-friendly, avoids latches, and is easy to audit. The naming convention (`_d` for next-state, `_q` for registered) is consistent with the PULP codebase standard and with industry SystemVerilog best practices.

### 4.6 Fully Parameterized

Both `IrLength` and `IdcodeValue` are parameters, allowing the TAP to be reused across different chips by simply changing the IDCODE. The IR length could be extended to accommodate additional instructions without modifying the FSM.

### 4.7 Complete Async Reset

All sequential elements have async active-low reset (`trst_ni`). Reset values are correct:
- FSM → TestLogicReset
- IR → IDCODE instruction
- IDCODE register → IdcodeValue
- Bypass register → 0
- TDO → 0, TDO_OE → 0

This ensures the TAP is in a known state immediately after TRST assertion, even before TCK starts toggling.

### 4.8 DFT-Aware Integration

The DFT synthesis script correctly excludes JTAG TAP flip-flops from the scan chain (`dft_dont_scan`). Including TCK-domain flops in a CLK-domain scan chain would create cross-clock-domain violations during ATPG. The current setup properly separates the two domains.

---

## 5. Lowlights — The Connectivity Problem

### 5.1 The Core Issue: SCAN_ACCESS Is a Dead End

The single most significant deficiency is that the SCAN_ACCESS data register — the only channel in the TAP designed for internal design access — is connected to a constant:

```systemverilog
// In rk4_top.sv, lines 49-50:
wire scan_enable, scan_in, scan_out;
assign scan_out = 1'b0;
```

**Effect:** When a JTAG controller selects the SCAN_ACCESS instruction (IR = 0x02) and performs a DR scan:
- `scan_enable_o` goes high → drives wire `scan_enable` → **nothing reads this wire**
- `scan_in_o` carries TDI data → drives wire `scan_in` → **nothing reads this wire**
- `scan_out_i` reads `scan_out` → **always 0**
- TDO outputs an infinite stream of zeros regardless of what TDI sends

The three scan-interface wires exist only as placeholders for Genus DFT insertion. They are not connected to any functional logic in the RTL.

### 5.2 No Custom Data Registers

The original PULP TAP had a DMI (Debug Module Interface) data register that allowed JTAG to read/write a debug module's address-data bus — effectively giving JTAG access to the processor's register file, memory, and CSRs. When the TAP was adapted for this project, the DMI register was removed. No equivalent custom data register was added to provide access to the RK4 engine's internals.

The current data register inventory is:

| Register | Bits | Observes Internal State? |
|----------|------|-------------------------|
| IDCODE | 32 | No — hardcoded constant |
| BYPASS | 1 | No — pass-through only |
| SCAN_ACCESS | (external) | No — stub wired to 0 |

There is no data register that captures, snapshots, or streams any signal from `rk4_projectile_top`.

### 5.3 No Clock-Domain Crossing Infrastructure

Even if custom data registers were added, accessing `rk4_projectile_top` signals from the TCK domain requires proper clock-domain crossing (CDC) synchronization. The current design has no CDC infrastructure between TCK and CLK:

- No synchronizer flip-flops
- No handshake protocol
- No FIFO or dual-port storage
- No request/acknowledge signaling

Any new data register that reads CLK-domain signals would need to address this.

### 5.4 No Halt/Run Control

The JTAG TAP has no ability to:
- Halt the RK4 computation mid-execution
- Single-step the FSM
- Force the FSM into a specific state
- Inject values into the register file
- Override the ALU operation

Without halt control, even if observability were added, the internal state would be changing while you try to read it through JTAG (which is much slower than the system clock).

### 5.5 scan_enable and scan_in Are Undriven Loads

The wires `scan_enable` and `scan_in` are driven by the TAP but never read by any module. In pre-DFT RTL simulation, these are dangling wires. Synthesis tools will optimize them away (along with the TAP logic that drives them) unless `set_db [get_db designs jtag_tap] .preserve true` or equivalent is used.

If the JTAG TAP is synthesized in the non-DFT flow (`rk4_script.tcl`), there is a risk that the synthesis tool removes the scan interface outputs as unconnected logic. Examining the non-DFT script:

```tcl
# rk4_script.tcl — no preserve directives for JTAG
syn_generic
syn_map
syn_opt
```

There are no `set_preserve` or `set_dont_touch` directives. Genus may or may not optimize away the scan outputs depending on its effort level and whether it can prove they have no effect on primary outputs.

### 5.6 IDCODE Provides Minimal Value

The IDCODE register confirms the chip identity (part number 0x0682). While useful for JTAG chain auto-detection on a multi-device board, it provides zero diagnostic information about:
- Whether the RK4 engine is functioning
- Whether a computation is in progress
- Whether an error has occurred
- What results have been produced

A stuck chip and a perfectly functioning chip return the same IDCODE.

### 5.7 No Status Register

There is no lightweight status register that could report basic operational status without full debug infrastructure. Even a simple register capturing `{fsm_busy, y_negative, step_cnt[6:0], state[5:0], ...}` would provide diagnostic value. This is a missed opportunity — a status register requires minimal area and no CDC complexity if it's implemented as a capture-only DR.

### 5.8 Summary of the Connectivity Gap

```
What JTAG can see:          │  What exists in the design:
                            │
✓ IDCODE (constant)         │  8 × 32-bit register file
✓ BYPASS (pass-through)     │  37-state FSM with step counter
✗ Scan chain (stub = 0)     │  16 × 16-bit instruction memory
                            │  32-bit ALU with live result
                            │  32-bit dt and dt_half registers
                            │  UART TX/RX state machines
                            │  Protocol parser state
                            │  Busy/done/error status
```

The JTAG interface has access to exactly 0 bits of live design state.

---

## 6. Impact Analysis — What Is Lost

### 6.1 FPGA Bring-Up Scenarios

During FPGA prototyping on the Nexys A7 board, the following debug scenarios cannot be addressed via JTAG:

| Scenario | Required Observability | Available via JTAG? |
|----------|----------------------|-------------------|
| "Is the FSM stuck?" | `state`, `fsm_busy` | No |
| "Did the computation finish?" | `fsm_busy`, `step_cnt` | No |
| "What is the current y value?" | `rf_y_out` (R6) | No |
| "Is dt computed correctly?" | `dt_reg` | No |
| "Did the f-engine program load?" | `imem[0:15]` | No |
| "Is the UART receiving bytes?" | `rx_valid`, `rx_data`, `pstate` | No |
| "Is the UART transmitting?" | `tx_ready`, `tx_valid`, `tx_mode` | No |
| "What iteration are we on?" | `step_cnt` | No |
| "Did y go negative (early termination)?" | `rf_y_out[31]` | No |

For every debug scenario, the only available tool is UART — but if UART itself is broken, there is no fallback.

### 6.2 Silicon Debug Scenarios

After tapeout and packaging, UART is the only I/O besides JTAG. If the UART link is non-functional (wrong baud rate, broken pad, ESD damage, signal integrity issue), there is **no alternative path** to determine whether the computational core is alive. The inverter power test confirms power delivery but nothing more.

With a functional JTAG debug interface, a post-silicon debug engineer could:
- Verify the register file contains expected values after a known input
- Confirm the FSM reaches the expected state
- Read back the f-engine program memory to verify it was loaded correctly
- Check dt computation against known-good values
- Observe t and y progression step-by-step

Without it, a non-responsive chip is a black box.

### 6.3 Manufacturing Test Limitations

The DFT scan chain (post-Genus) provides structural test coverage — it can detect stuck-at faults in individual flip-flops. However, it cannot:
- Verify functional correctness (does the RK4 algorithm produce the right answer?)
- Test the combinational ALU in isolation
- Verify the f-engine executes instructions correctly
- Test the UART at-speed

A JTAG interface with register access would enable functional manufacturing tests beyond ATPG patterns.

### 6.4 Quantified Observability Gap

Total flip-flops in the design (approximate count from RTL):

| Module | Estimated FF Count | Observable via JTAG? |
|--------|--------------------|---------------------|
| rk4_regfile | 256 (8 × 32) | No |
| rk4_control_fsm | ~20 (state, step_cnt, outputs) | No |
| rk4_f_engine | 256 + 12 (imem + pc + estate) | No |
| rk4_uart_protocol | ~50 (pstate, byte_cnt, v0_shift, etc.) | No |
| uart_rx | ~25 (baud_cnt, bit_cnt, shift_reg, etc.) | No |
| uart_tx | ~25 (baud_cnt, bit_cnt, shift_reg, etc.) | No |
| rk4_projectile_top (top) | ~80 (dt, dt_half, tx_shift, etc.) | No |
| jtag_tap | ~50 (FSM, IR, IDCODE, bypass, TDO) | N/A (self) |
| **Total design FFs** | **~774** | **0 observable (0%)** |

The JTAG interface provides visibility into 0% of the design's sequential state.

---

## 7. Proposed Changes — Architecture Options

Three architectural approaches are presented, ranging from minimal-effort to comprehensive. Each trades off complexity, area, CDC risk, and debug capability.

### 7.1 Option A: Capture-Only Status Register (Minimal)

**Concept:** Add a single new data register inside the JTAG TAP that captures a snapshot of key status signals on the Capture-DR event. No write-back capability. No CDC synchronizers needed if the captured signals are treated as asynchronous samples.

**New IR instruction:** `STATUS` (e.g., IR = 0x03)

**Register width:** 32 or 64 bits

**Captured fields (32-bit version):**

| Bits | Width | Signal | Description |
|------|-------|--------|-------------|
| [31] | 1 | `fsm_busy` | Computation in progress |
| [30] | 1 | `rf_y_out[31]` | y is negative (early termination) |
| [29] | 1 | `f_active` | f-engine executing |
| [28] | 1 | `tx_ready` | UART TX idle |
| [27:22] | 6 | `state[5:0]` | Control FSM state |
| [21:16] | 6 | `step_cnt[6:0]` | Iteration counter (truncated) |
| [15:12] | 4 | `pc[3:0]` | f-engine program counter |
| [11:10] | 2 | `estate[1:0]` | f-engine execution state |
| [9:8] | 2 | `pstate[1:0]` | Protocol parser state |
| [7:6] | 2 | `tx_mode[1:0]` | TX shift-out mode |
| [5:2] | 4 | `tx_bytes_left[3:0]` | TX bytes remaining |
| [1] | 1 | `rx_valid` | UART RX byte available (instantaneous) |
| [0] | 1 | `run_start` | Run command received (instantaneous) |

**Architecture:**

```
rk4_projectile_top signals ──► (directly wired) ──► TAP status_capture register
                                                          │
                                                     Capture-DR
                                                          │
                                                     Shift-DR ──► TDO
```

**Pros:**
- Minimal area (~32 flip-flops + mux logic inside TAP)
- No modifications to `rk4_projectile_top` (only needs output ports added)
- No CDC synchronizers required (asynchronous capture is acceptable for debug — you get a potentially metastable snapshot, but for diagnostic purposes this is sufficient)
- No risk of disturbing functional behavior
- Preserves existing DFT scan chain architecture

**Cons:**
- Read-only — cannot inject values or halt the core
- Asynchronous capture may produce inconsistent snapshots if CLK is faster than TCK (fields from different clock cycles)
- Cannot read register file contents or ALU results — only control status
- Limited to predefined signal selection at design time

**CDC Note:** The captured signals cross from CLK to TCK domain. Since this is a capture-only register (loaded in Capture-DR, which happens once per JTAG transaction), metastability can be tolerated — a corrupted status read is retried. For production use, a two-flop synchronizer on each input would eliminate metastability risk at the cost of 2 TCK cycles of latency.

**Estimated area impact:** ~200 gates (negligible relative to the design)

---

### 7.2 Option B: Register Access Bridge (Moderate)

**Concept:** Add a JTAG-to-register-file bridge that allows reading (and optionally writing) any of the 8 registers in `rk4_regfile`, plus the key control/status signals. This requires a handshake-based CDC mechanism and a halt capability to freeze the register file during reads.

**New IR instructions:**

| IR Code | Name | DR Width | Function |
|---------|------|----------|----------|
| 0x03 | STATUS | 32 | Capture-only status (same as Option A) |
| 0x04 | REG_ACCESS | 40 | Read/write register file: {rw[0], addr[2:0], wdata[31:0], padding[3:0]} |
| 0x05 | HALT_CTRL | 8 | {halt_req, single_step, resume, ...} |

**Architecture:**

```
                    TCK Domain                    │           CLK Domain
                                                  │
  TDI ──► [REG_ACCESS DR (40-bit shift reg)]     │
              │                                   │
         Update-DR                                │
              │                                   │
         ┌────▼────┐     CDC Handshake       ┌────▼────┐
         │ Request │ ◄──────────────────────► │  JTAG   │
         │  Latch  │     (req/ack + sync)     │ Bridge  │──► rf_rd_addr
         └────┬────┘                          │  (CLK)  │◄── rf_rd_data
              │                               │         │──► halt_req
         Capture-DR                           └─────────┘
              │
  TDO ◄── [40-bit shift reg with captured read data]
```

**Handshake protocol:**

1. JTAG controller writes address + R/W bit into REG_ACCESS DR via Shift-DR + Update-DR
2. Update-DR latches the request in TCK domain
3. CDC synchronizer transfers the request to CLK domain (2-FF synchronizer + pulse detector)
4. CLK-domain bridge module reads/writes the register file
5. Read data (or write-ack) is captured in CLK domain and synced back to TCK domain
6. Next Capture-DR in TCK domain loads the response into the shift register
7. JTAG controller shifts out the read data

**Halt mechanism:**

The HALT_CTRL DR allows the JTAG controller to assert a `halt_req` signal. When `halt_req` is synchronized into the CLK domain, the control FSM pauses at the next safe point (after completing the current ALU operation, before entering the next state). This freezes the register file contents so JTAG reads are consistent.

**Pros:**
- Full read access to all 8 registers (v0, t, k1–k4, y, acc) — 256 bits of state
- Optional write access for value injection
- Halt capability enables consistent snapshots
- Single-step mode enables step-by-step algorithm tracing
- Status register provides quick health check without halting

**Cons:**
- Requires CDC synchronizers (adds ~4 TCK cycles of latency per transaction)
- Requires modifications to `rk4_projectile_top` (halt input, optional debug read port)
- Bridge module adds ~500–800 gates
- Halt mechanism introduces a new interaction with the FSM (risk of deadlock if halt occurs during f-engine execution)
- Write access could corrupt computation state if used carelessly

**Estimated area impact:** ~2000–3000 gates

---

### 7.3 Option C: Full Debug Module (Comprehensive)

**Concept:** Implement a complete JTAG debug module similar to the PULP DMI, with an address-mapped register space that provides read/write access to all major internal state. This is the most capable option but also the most complex.

**New IR instruction:**

| IR Code | Name | DR Width | Function |
|---------|------|----------|----------|
| 0x03 | DBG_ACCESS | 41 | {op[1:0], addr[6:0], data[31:0]} |

**Debug register address map:**

| Address | Name | R/W | Width | Description |
|---------|------|-----|-------|-------------|
| 0x00 | STATUS | R | 32 | {busy, y_neg, f_active, tx_ready, state[5:0], step_cnt[6:0], ...} |
| 0x01 | CTRL | R/W | 32 | {halt, single_step, resume, force_reset, ...} |
| 0x02 | PC_FENGINE | R | 32 | {28'b0, pc[3:0]} |
| 0x03 | FSM_STATE | R | 32 | {26'b0, state[5:0]} |
| 0x08 | REG_V0 | R/W | 32 | Register file R0 (v0) |
| 0x09 | REG_T | R/W | 32 | Register file R1 (t) |
| 0x0A | REG_K1 | R/W | 32 | Register file R2 (k1) |
| 0x0B | REG_K2 | R/W | 32 | Register file R3 (k2) |
| 0x0C | REG_K3 | R/W | 32 | Register file R4 (k3) |
| 0x0D | REG_K4 | R/W | 32 | Register file R5 (k4) |
| 0x0E | REG_Y | R/W | 32 | Register file R6 (y) |
| 0x0F | REG_ACC | R/W | 32 | Register file R7 (acc) |
| 0x10 | DT_REG | R | 32 | Computed time step |
| 0x11 | DT_HALF | R | 32 | Half time step |
| 0x12 | ALU_RESULT | R | 32 | Current ALU output |
| 0x13 | STEP_CNT | R | 32 | {25'b0, step_cnt[6:0]} |
| 0x20–0x2F | IMEM_0–15 | R/W | 32 | f-engine instruction memory (16-bit, zero-extended) |
| 0x30 | UART_STATUS | R | 32 | {tx_ready, tx_mode, tx_bytes_left, rx_valid, pstate, ...} |

**Operation encoding (2-bit `op` field):**

| op | Name | Description |
|----|------|-------------|
| 00 | NOP | No operation (returns previous read data) |
| 01 | READ | Read from `addr`, data returned on next Capture-DR |
| 10 | WRITE | Write `data` to `addr` |
| 11 | (reserved) | — |

**Architecture:**

```
TCK Domain                              │  CLK Domain
                                        │
TDI ──► [41-bit DBG_ACCESS shift reg]   │
             │                          │
        Update-DR                       │
             │                          │
    ┌────────▼────────┐   Async FIFO    │  ┌──────────────────┐
    │ op/addr/data    │ ◄─────────────► │  │   Debug Module   │
    │ request latch   │   or CDC hshk   │  │                  │
    └────────┬────────┘                 │  │ ┌──────────────┐ │
             │                          │  │ │ Address      │ │
        Capture-DR                      │  │ │ Decoder      │ │
             │                          │  │ └──────┬───────┘ │
TDO ◄── [41-bit shift reg w/ response] │  │        │         │
                                        │  │ ┌──────▼───────┐ │
                                        │  │ │ Mux/Demux to │ │
                                        │  │ │ regfile, FSM, │ │
                                        │  │ │ f-engine,    │ │
                                        │  │ │ dt regs, etc │ │
                                        │  │ └──────────────┘ │
                                        │  │                  │
                                        │  │ ──► halt_req     │
                                        │  │ ──► rf_dbg_addr  │
                                        │  │ ◄── rf_dbg_data  │
                                        │  │ ──► imem_dbg_addr│
                                        │  │ ◄── imem_dbg_data│
                                        │  └──────────────────┘
```

**Pros:**
- Complete observability of all internal state
- Write access enables value injection and program memory updates via JTAG
- Halt/resume/single-step for interactive debug
- f-engine program memory readable for verification
- Address-mapped interface is extensible (new registers added by expanding address map)
- Matches industry-standard debug module patterns (RISC-V, ARM CoreSight)

**Cons:**
- Highest complexity: ~3000–5000 gates for the debug module
- Requires CDC FIFO or robust handshake mechanism
- Requires a third read port on the register file (or time-multiplexed access during halt)
- Requires a read port on f-engine instruction memory
- Must modify `rk4_projectile_top` to expose debug access ports
- Risk of debug logic affecting timing closure
- DFT interaction complexity (debug module flops need careful scan chain handling)

**Estimated area impact:** ~5000–8000 gates

---

### 7.4 Option Comparison Matrix

| Criterion | Option A (Status) | Option B (Reg Bridge) | Option C (Full Debug) |
|-----------|-------------------|----------------------|----------------------|
| **RTL changes to TAP** | Add 1 DR | Add 3 DRs + CDC | Add 1 DR + debug module |
| **RTL changes to core** | Add output ports only | Add halt + debug read port | Add halt + multi-port debug access |
| **Area overhead** | ~200 gates | ~2000–3000 gates | ~5000–8000 gates |
| **CDC complexity** | None (async capture) | 2-FF sync + handshake | Async FIFO or handshake |
| **Observe register file** | No | Yes (all 8 regs) | Yes (all 8 regs) |
| **Observe FSM state** | Yes | Yes | Yes |
| **Observe f-engine imem** | No | No | Yes |
| **Write registers** | No | Optional | Yes |
| **Write f-engine imem** | No | No | Yes |
| **Halt/single-step** | No | Yes | Yes |
| **Debug UART issues** | Partial (status bits) | Partial | Yes (full UART state) |
| **Implementation time** | ~1 day | ~3–5 days | ~1–2 weeks |
| **Risk to existing functionality** | Negligible | Low | Moderate |
| **DFT impact** | None | Minimal | Needs careful handling |

---

## 8. Detailed Design of Recommended Approach

**Recommendation:** Implement **Option B (Register Access Bridge)** as the primary enhancement, with the **Option A Status Register** included as a lightweight fast-path. This combination provides the best balance of debug capability, implementation effort, and risk.

Option C is deferred as a future enhancement — Option B's register access covers the most critical debug scenarios, and the address-mapped pattern from Option C can be retrofitted later if needed.

### 8.1 Modified TAP IR Map

| IR Code | Hex | Name | DR Width | Function |
|---------|-----|------|----------|----------|
| `00000` | 0x00 | BYPASS0 | 1 | Standard bypass (existing) |
| `00001` | 0x01 | IDCODE | 32 | Device ID (existing) |
| `00010` | 0x02 | SCAN_ACCESS | external | DFT scan chain (existing, stub pre-DFT) |
| `00011` | 0x03 | STATUS | 32 | Capture-only status snapshot (new) |
| `00100` | 0x04 | REG_READ | 35 | Register file read access (new) |
| `00101` | 0x05 | HALT_CTRL | 8 | Halt/resume/single-step control (new) |
| `11111` | 0x1F | BYPASS1 | 1 | Standard bypass (existing) |

### 8.2 STATUS Data Register (IR = 0x03)

This is the Option A capture-only register. It provides instant diagnostic information without requiring CDC handshakes.

**Behavior:**
- **Capture-DR:** Samples all status signals asynchronously from CLK domain
- **Shift-DR:** Shifts captured value out to TDO (LSB first), shifts TDI in (discarded)
- **Update-DR:** No effect (read-only register)

**Bit field definition (32 bits):**

```
Bit 31                                                              0
┌───┬───┬───┬───┬─────────┬──────────┬──────┬──────┬──────┬────┬───┐
│ B │ Y │ F │ T │  STATE  │ STEP_CNT │  PC  │ESTATE│PSTATE│TXMD│RSV│
│[31│[30│[29│[28│ [27:22] │ [21:15]  │[14:11│[10:9]│ [8:7]│[6:5│[4:│
│ ] │ ] │ ] │ ] │         │          │]     │      │      │ ]  │ 0]│
└───┴───┴───┴───┴─────────┴──────────┴──────┴──────┴──────┴────┴───┘
```

| Bits | Name | Source Signal | Description |
|------|------|---------------|-------------|
| [31] | BUSY | `u_fsm.busy` | Control FSM is running |
| [30] | Y_NEG | `rf_y_out[31]` | y is negative |
| [29] | F_ACT | `f_active` | f-engine is executing |
| [28] | TX_RDY | `tx_ready` | UART TX ready for data |
| [27:22] | STATE | `u_fsm.state[5:0]` | Control FSM state encoding |
| [21:15] | STEP | `u_fsm.step_cnt[6:0]` | Current iteration number |
| [14:11] | FE_PC | `u_fengine.pc[3:0]` | f-engine program counter |
| [10:9] | FE_ST | `u_fengine.estate[1:0]` | f-engine FSM state |
| [8:7] | P_ST | `u_proto.pstate[1:0]` | Protocol parser state |
| [6:5] | TX_MD | `tx_mode[1:0]` | TX shift-out mode |
| [4:0] | (reserved) | — | Reserved, reads as 0 |

**CDC consideration:** These signals are sampled asynchronously. A single Capture-DR event may capture signals from different CLK cycles, producing an inconsistent snapshot. For diagnostic purposes (determining whether the FSM is stuck, whether the system is busy, etc.), this is acceptable. For bit-exact register values, use the REG_READ register with halt.

### 8.3 REG_READ Data Register (IR = 0x04)

Provides synchronized read access to any register in `rk4_regfile`.

**DR width:** 35 bits

**Shift-in format (TDI → DR):**

```
Bit 34      32 31                                  0
┌────────────┬──────────────────────────────────────┐
│  addr[2:0] │           (don't care)               │
└────────────┴──────────────────────────────────────┘
```

**Shift-out format (DR → TDO):**

```
Bit 34      32 31                                  0
┌────────────┬──────────────────────────────────────┐
│  addr[2:0] │          read_data[31:0]             │
└────────────┴──────────────────────────────────────┘
```

**Protocol for reading a register:**

1. Load IR = 0x04 (REG_READ)
2. Shift in 35 bits: `{addr[2:0], 32'bx}`. The 3-bit address selects the target register.
3. Go to Update-DR: The address is latched and a read request is initiated.
4. Wait for the CDC handshake to complete (~4–6 TCK cycles). This can be done by going through Run-Test/Idle for several cycles.
5. Enter a new DR scan: Capture-DR loads the read response into the shift register.
6. Shift out 35 bits: bits [31:0] contain the register value.

**CDC handshake for REG_READ:**

```
TCK Domain                          CLK Domain
                                    
  Update-DR                          
      │                              
  ┌───▼───┐                         
  │ Latch │──req_tck──►[2-FF sync]──req_clk──►┌──────────┐
  │ addr  │                                    │ RF Read  │
  │       │◄─ack_tck──◄[2-FF sync]──ack_clk──◄│ addr→data│
  └───┬───┘                                    └────┬─────┘
      │                                             │
  Capture-DR                               rd_data captured
      │                                    in CLK-domain reg
  ┌───▼───┐                                        │
  │ Load  │◄──data_tck◄[2-FF sync]──data_clk──────┘
  │ shift │    (32 bits synced via                   
  │  reg  │     gray-code or per-bit sync)           
  └───────┘                                          
```

The handshake uses a req/ack protocol:

1. **TCK domain:** On Update-DR, assert `req_tck` and latch `addr_tck[2:0]`.
2. **CLK domain:** 2-FF synchronizer detects `req_clk` rising edge. Reads `regs[addr]` from the register file (using the existing asynchronous read port or a dedicated debug port). Captures the 32-bit result into `rd_data_clk`. Asserts `ack_clk`.
3. **TCK domain:** 2-FF synchronizer detects `ack_tck` rising edge. Transfers `rd_data_clk` into `rd_data_tck` (requires multi-bit CDC — see §8.6). Clears `req_tck`.
4. **CLK domain:** Detects `req_clk` falling edge. Clears `ack_clk`.
5. **TCK domain:** On next Capture-DR, loads `{addr_tck, rd_data_tck}` into the shift register.

**Latency:** 4 CLK cycles (2 for req sync + 2 for ack sync) + register file read time (1 CLK cycle, combinational read) + 2 TCK cycles for data sync. Total: ~4–6 TCK cycles between Update-DR and data availability.

### 8.4 HALT_CTRL Data Register (IR = 0x05)

Controls the halt/resume/single-step mechanism.

**DR width:** 8 bits

**Bit field definition:**

| Bit | Name | R/W | Description |
|-----|------|-----|-------------|
| [7] | HALT_REQ | W | Assert to request halt; FSM pauses at next safe point |
| [6] | RESUME | W | Pulse to resume from halted state |
| [5] | SINGLE_STEP | W | Pulse to execute one FSM state transition then re-halt |
| [4] | FORCE_RESET | W | Force async reset of the computational core |
| [3] | HALTED | R | 1 = FSM is currently halted |
| [2] | (reserved) | — | — |
| [1] | (reserved) | — | — |
| [0] | (reserved) | — | — |

**Halt mechanism in the control FSM:**

The halt signal is synchronized from TCK to CLK domain via a 2-FF synchronizer. The `rk4_control_fsm` is modified to check `halt_req_synced` at the beginning of each state:

```systemverilog
// Added to rk4_control_fsm:
input wire dbg_halt_req,
output reg dbg_halted,

// In the FSM always block, at the top of the else branch:
if (dbg_halt_req && !dbg_halted) begin
    dbg_halted <= 1'b1;
    // Do not advance state — hold current state
end else if (!dbg_halt_req && dbg_halted) begin
    dbg_halted <= 1'b0;
    // Resume normal state transitions
end else if (!dbg_halted) begin
    // ... existing FSM logic ...
end
```

**Safe halt points:** The FSM should only halt at states where the register file is not being written (i.e., `wr_en == 0`). The safest halt points are the `_WAIT` states (`S_K1_WAIT`, `S_K2_WAIT`, etc.) and `S_CHECK`. During f-engine execution, the halt should defer until `f_done` to avoid corrupting the micro-code execution.

### 8.5 Required Modifications to Existing Modules

#### 8.5.1 `rk4_projectile_top` — New Debug Output Port

Add a debug output bus that aggregates status signals for the TAP:

```systemverilog
// New output port on rk4_projectile_top:
output wire [31:0] dbg_status,
output wire signed [31:0] dbg_rf_rd_data,
input  wire [2:0]  dbg_rf_rd_addr,
input  wire        dbg_halt_req,
output wire        dbg_halted
```

The `dbg_status` bus carries the STATUS register fields. The `dbg_rf_rd_addr` / `dbg_rf_rd_data` pair provides a dedicated debug read port to the register file.

#### 8.5.2 `rk4_regfile` — Third Read Port

Add a third asynchronous read port for JTAG access:

```systemverilog
// New port on rk4_regfile:
input  wire [2:0]  dbg_rd_addr,
output wire signed [31:0] dbg_rd_data

// Implementation:
assign dbg_rd_data = regs[dbg_rd_addr];
```

This is a purely combinational read — no additional flip-flops, just an 8:1 mux on the existing register array. Area impact is minimal (~100 gates).

#### 8.5.3 `rk4_control_fsm` — Halt Input

Add `dbg_halt_req` input and `dbg_halted` output as described in §8.4.

#### 8.5.4 `rk4_top` — Updated Wiring

Connect the TAP's new data registers to `rk4_projectile_top`'s debug port through the CDC synchronizers.

### 8.6 Multi-Bit CDC for Read Data

The 32-bit register read data must cross from CLK to TCK domain. Options:

**Option 1: Gray-code FIFO (overkill)**
A small async FIFO (depth 2) with gray-coded pointers. Guarantees no data corruption. Adds ~200 gates. Appropriate if multiple reads are pipelined.

**Option 2: MUX-based recirculation (recommended)**
Use the req/ack handshake to guarantee that `rd_data_clk` is stable when sampled:
1. CLK domain asserts `ack_clk` only after `rd_data_clk` is stable.
2. TCK domain waits for `ack_tck` (2-FF synced) before sampling `rd_data_clk` into `rd_data_tck`.
3. Since `rd_data_clk` does not change while `ack_clk` is asserted (CLK domain holds the value), the multi-bit capture is safe — no gray coding needed.

This is the standard "level-based CDC with handshake" pattern. It requires:
- 2-FF synchronizer for `req` (TCK → CLK)
- 2-FF synchronizer for `ack` (CLK → TCK)
- The 32-bit data bus is sampled only when the handshake guarantees stability

**Total synchronizer flip-flops:** 4 (2 for req, 2 for ack). The 32-bit data bus does not need individual synchronizers because the handshake ensures it is stable at the sampling moment.

### 8.7 Timing Constraints Update

The SDC file must be updated to constrain the TCK domain:

```tcl
# Define TCK clock (conservative 10 MHz)
create_clock -name tck -period 100 [get_ports tck]

# False paths between clock domains (CDC handled by synchronizers)
set_false_path -from [get_clocks clk] -to [get_clocks tck]
set_false_path -from [get_clocks tck] -to [get_clocks clk]

# Constrain synchronizer paths (max_delay for metastability settling)
set_max_delay 10 -from [get_pins */sync_req_ff1/D] -to [get_pins */sync_req_ff2/D]
set_max_delay 10 -from [get_pins */sync_ack_ff1/D] -to [get_pins */sync_ack_ff2/D]
```

### 8.8 DFT Compatibility

The new debug registers and CDC synchronizers must be handled during DFT synthesis:

1. **Debug module flip-flops in CLK domain:** Can be included in the existing scan chain.
2. **CDC synchronizer flip-flops:** Must be marked as `dft_dont_scan` to prevent ATPG from creating test patterns that violate the synchronizer's timing assumptions.
3. **TAP-side flip-flops (new DRs):** Excluded from scan (same as existing TAP flops).

```tcl
# Add to rk4_dft_script.tcl:
set_db [get_db insts *sync_req*] .dft_dont_scan true
set_db [get_db insts *sync_ack*] .dft_dont_scan true
```

---

## 9. Implementation Considerations

### 9.1 Backward Compatibility

The proposed changes are **fully backward compatible**:

- Existing IR codes (BYPASS0, IDCODE, SCAN_ACCESS, BYPASS1) retain their current behavior
- New IR codes (STATUS, REG_READ, HALT_CTRL) occupy previously unused slots that defaulted to BYPASS
- Any existing JTAG test scripts or host software that only uses IDCODE/BYPASS will continue to work
- The DFT scan chain is unaffected (SCAN_ACCESS stub remains; Genus stitches it post-synthesis as before)

### 9.2 Area Budget

Estimated gate count breakdown for the recommended Option B implementation:

| Component | Gates | Notes |
|-----------|-------|-------|
| STATUS DR (32-bit capture + shift) | ~200 | Inside TAP |
| REG_READ DR (35-bit shift + latch) | ~250 | Inside TAP |
| HALT_CTRL DR (8-bit shift + latch) | ~80 | Inside TAP |
| DR select mux expansion | ~50 | Inside TAP |
| TDO mux expansion | ~30 | Inside TAP |
| CDC synchronizers (req + ack) | ~30 | 4 flip-flops + glue |
| CLK-domain bridge logic | ~200 | Handshake FSM + data latch |
| Regfile debug read port (8:1 mux × 32) | ~100 | Inside rk4_regfile |
| FSM halt logic | ~50 | Inside rk4_control_fsm |
| **Total** | **~990** | |

For comparison, the entire `jtag_tap` module currently synthesizes to approximately 400–500 gates. The enhancement roughly triples the JTAG subsystem size but remains negligible compared to the full design (~15,000–20,000 gates including the 32×32 multiplier).

### 9.3 Verification Strategy

The enhanced JTAG TAP requires verification at three levels:

**Unit-level (TAP module):**
- Verify each new DR captures, shifts, and updates correctly
- Verify TDO mux selects the correct DR for each IR code
- Verify new IR codes don't interfere with existing IDCODE/BYPASS behavior

**CDC verification:**
- Use formal CDC tools (e.g., Cadence JasperGold CDC) or simulation-based CDC checking
- Verify the req/ack handshake protocol is deadlock-free
- Verify multi-bit data transfer stability (data does not change while ack is asserted)

**Integration-level:**
- Read IDCODE and verify it still works (regression)
- Write a JTAG sequence that reads STATUS and verifies known bit fields
- Halt the FSM, read all 8 registers, verify against expected values
- Resume from halt and verify computation continues correctly
- Single-step through several FSM states and verify state progression
- Read a register during active computation (no halt) and verify no system corruption

### 9.4 Software/Host Tooling

A JTAG controller (OpenOCD, custom Python script over FTDI, or Nexys A7's built-in JTAG) needs driver support for the new instructions. A minimal command set:

```
jtag_read_idcode()        → 32-bit ID
jtag_read_status()        → 32-bit status word
jtag_halt()               → assert halt, wait for HALTED=1
jtag_resume()             → deassert halt
jtag_read_reg(addr)       → 32-bit register value (requires halt for consistency)
jtag_single_step()        → advance one FSM state
```

### 9.5 Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| CDC metastability in status register | Medium | Low (diagnostic data) | Accept for status; use handshake for reg reads |
| Halt deadlock during f-engine execution | Low | High (system hung) | Only halt at safe points; add watchdog timeout |
| Debug port contention with functional reads | Low | Medium | Separate read port on regfile |
| Synthesis area increase exceeds budget | Very Low | Low | ~1000 gates on 180nm is negligible |
| New TAP logic introduces timing violation on TDO | Low | Medium | Verify with updated SDC including TCK constraint |
| DFT scan chain disrupted by new flops | Low | Medium | Explicit `dft_dont_scan` for CDC + TAP flops |

---

## 10. Conclusion

The current JTAG TAP in the RK4 Projectile Engine is a well-implemented IEEE 1149.1 controller that provides correct IDCODE and BYPASS functionality. However, it offers **zero observability** into the computational datapath. The SCAN_ACCESS data register — its sole channel for internal access — is wired to a constant zero stub that only becomes functional after Genus DFT scan chain insertion during synthesis.

This creates a significant gap for three use cases:

1. **FPGA prototyping debug:** If UART is non-functional, there is no alternative path to diagnose the system.
2. **Post-silicon bring-up:** A non-responsive chip is a black box with only IDCODE confirming its identity.
3. **Functional manufacturing test:** Beyond structural ATPG, no functional validation can be performed through JTAG.

The recommended enhancement — **Option B (Register Access Bridge)** — adds three new JTAG instructions (STATUS, REG_READ, HALT_CTRL) that together provide:
- Instant status snapshot of all major FSM/control state (no halt required)
- Synchronized read access to all 8 registers in the register file (256 bits of computational state)
- Halt/resume/single-step control for interactive debugging

The implementation requires ~990 additional gates, modifications to three existing modules (TAP, register file, control FSM), a req/ack CDC handshake, and updated SDC constraints. It is fully backward-compatible with existing JTAG behavior and DFT flows.

This enhancement transforms the JTAG interface from a passive chip-identification-only port into a functional debug and diagnostic tool, closing the observability gap between the JTAG controller and the RK4 computational engine.

---

## 11. Appendices

### Appendix A: IEEE 1149.1 TAP State Transition Table (Reference)

| Current State | TMS=0 | TMS=1 |
|---------------|-------|-------|
| Test-Logic-Reset | Run-Test/Idle | Test-Logic-Reset |
| Run-Test/Idle | Run-Test/Idle | Select-DR-Scan |
| Select-DR-Scan | Capture-DR | Select-IR-Scan |
| Capture-DR | Shift-DR | Exit1-DR |
| Shift-DR | Shift-DR | Exit1-DR |
| Exit1-DR | Pause-DR | Update-DR |
| Pause-DR | Pause-DR | Exit2-DR |
| Exit2-DR | Shift-DR | Update-DR |
| Update-DR | Run-Test/Idle | Select-DR-Scan |
| Select-IR-Scan | Capture-IR | Test-Logic-Reset |
| Capture-IR | Shift-IR | Exit1-IR |
| Shift-IR | Shift-IR | Exit1-IR |
| Exit1-IR | Pause-IR | Update-IR |
| Pause-IR | Pause-IR | Exit2-IR |
| Exit2-IR | Shift-IR | Update-IR |
| Update-IR | Run-Test/Idle | Select-DR-Scan |

### Appendix B: IDCODE Value Breakdown

```
IdcodeValue = 32'h10682001

Binary: 0001_0000_0110_1000_0010_0000_0000_0001

Field          Bits      Hex    Value
─────────────  ────────  ─────  ──────────────────
Version        [31:28]   0x1    Version 1
Part Number    [27:12]   0x0682 EECE-682 identifier
Manufacturer   [11:1]    0x000  Unregistered (academic)
Mandatory 1    [0]       0x1    Per IEEE 1149.1
```

### Appendix C: Current Source File Inventory

| File | Lines | Description | JTAG-Related? |
|------|-------|-------------|--------------|
| `rtl/jtag_tap.sv` | 265 | JTAG TAP controller | Primary |
| `rtl/rk4_top.sv` | 67 | Chip top-level (TAP instantiation + scan stub) | Integration |
| `rtl/rk4_projectile_top.sv` | 261 | Computational core (no JTAG connection) | Target for debug access |
| `rtl/rk4_regfile.sv` | 54 | Register file (needs debug read port) | Modification target |
| `rtl/rk4_control_fsm.sv` | 423 | Control FSM (needs halt input) | Modification target |
| `rtl/rk4_f_engine.sv` | 133 | f-engine (observable via status register) | Status output |
| `rtl/rk4_uart_protocol.sv` | 134 | UART protocol parser (observable via status) | Status output |
| `synthesis/rk4_dft_script.tcl` | 65 | DFT synthesis (JTAG scan chain setup) | DFT flow |
| `synthesis/constraints.sdc` | 31 | Timing constraints (needs TCK clock) | Constraint update |

### Appendix D: Glossary

| Term | Definition |
|------|-----------|
| **ATPG** | Automatic Test Pattern Generation — creates test vectors for manufacturing fault detection |
| **CDC** | Clock Domain Crossing — signals that transition between two asynchronous clock domains |
| **DFT** | Design for Testability — modifications to a design to improve manufacturing test coverage |
| **DR** | Data Register — a shift register in the JTAG chain selected by the current IR value |
| **IR** | Instruction Register — selects which DR is placed between TDI and TDO |
| **Q16.16** | Fixed-point format: 16 integer bits + 16 fractional bits (32 bits total, signed) |
| **RK4** | 4th-order Runge-Kutta method — a numerical integration algorithm |
| **TAP** | Test Access Port — the IEEE 1149.1 interface (TCK, TMS, TDI, TDO, TRST) |
| **TCK** | Test Clock — the JTAG clock, independent of the system clock |
| **TDI** | Test Data In — serial data input to the JTAG chain |
| **TDO** | Test Data Out — serial data output from the JTAG chain |
| **TMS** | Test Mode Select — controls TAP state machine transitions |
| **TRST** | Test Reset — asynchronous reset for the TAP controller |

