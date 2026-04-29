# Chip Bringup — Simple Function: f(t) = v0 − g·t

This is the canonical projectile-velocity derivative already baked into
`docs/f_engine_isa.md` as the example program.  The 2-instruction f-engine
program computes the instantaneous velocity under constant gravity, and the
RK4 integrator accumulates position over 100 time steps.

---

## Background

The chip integrates dy/dt = f(t) using a 4th-order Runge-Kutta loop.
You pick f by uploading a micro-program to the f-engine over UART, then
send a `RUN` command with the initial velocity v0.  The chip streams
(t, y) pairs back over UART after each RK4 step, and closes with the
`0xDEADBEEF` done marker.

**Fixed-point format:** Q16.16 signed (32-bit).  To convert a real value
`x` to a Q16.16 integer: `x_fixed = round(x × 65536)`.

**Hardware constants (chip parameters):**

| Symbol        | Value (Q16.16 int) | Decimal approx |
|---------------|--------------------|----------------|
| `G_FIXED`     | `642252`           | 9.8 m/s²       |
| `INV_G_FIXED` | `6694`             | 1/9.8          |
| `INV6_FIXED`  | `10922`            | 1/6            |
| `INV_N_FIXED` | `655`              | 1/100          |
| `NUM_DIV`     | 100 (integer)      | steps per run  |

**UART settings:** 9600 baud, 8-N-1, no flow control.  At CLK=10 MHz,
`BAUD_DIV = 1042`.  Idle line is HIGH.

---

## Step 0 — Power-On / Reset

1. Assert `rst_n = 0` for at least 10 clock cycles, then deassert
   (`rst_n = 1`).
2. Pull `uart_rx` HIGH (idle).
3. Pull `tms = 1`, send 5+ TCK pulses to reset the JTAG TAP to
   `Test-Logic-Reset`.  IR defaults to `IDCODE`.

---

## Step 1 — Optional Sanity Check: Read IDCODE via JTAG

Verify the TAP is alive before sending UART commands.
Expected value: **`0xEECE_00DE`**.

Starting from `Test-Logic-Reset`, send these TCK edges (TMS/TDI sampled
on **rising** edge, TDO updates on **falling** edge):

```
 Cycle  TMS  TDI  TAP State
 ─────  ───  ───  ─────────────────────────────────────
  1      0    x   Test-Logic-Reset → Run-Test/Idle
  2      1    x   RTI → Select-DR-Scan
  3      0    x   Select-DR-Scan → Capture-DR       ← IDCODE loaded into shift reg
  4–34   0    x   Shift-DR (bits 0–30 appear on TDO)
  35     1    x   Shift-DR → Exit1-DR               ← bit 31 on TDO
  36     1    x   Exit1-DR → Update-DR
  37     0    x   Update-DR → Run-Test/Idle
```

Reassemble the 32 TDO bits in LSB-first order.  If you get `0xEECE_00DE`
the TAP and power supply are good.

---

## Step 2 — Load the f-Engine Program over UART

The program for **f(t) = v0 − g·t** is 2 instructions:

| Addr | Assembly             | Encoding (hex) | Operation          |
|------|----------------------|----------------|--------------------|
|  0   | `MUL R7, R5, R7`    | `0xBD70`       | R7 ← g × time_arg |
|  1   | `SUB R7, R0, R7 H`  | `0x1CF8`       | R7 ← v0 − R7; HALT|

> **Note:** The control FSM pre-loads `G_FIXED` into **R5** (`K4` slot)
> before each f-engine call, and copies the current time argument (t,
> t+dt/2, or t+dt) into **R7** (acc).  R0 always holds v0.

Send the `LOAD_PROG` command — one command byte followed by 32 payload bytes
(16 instructions × 2 bytes each, little-endian, LSB byte first):

```
UART bytes to send (hex):
 01                          ← CMD_LOAD_PROG
 70 BD                       ← instr[0] = 0xBD70, little-endian: low=0x70, high=0xBD
 F8 1C                       ← instr[1] = 0x1CF8, little-endian: low=0xF8, high=0x1C
 00 00                       ← instr[2]  = 0x0000 (unused, benign NOP)
 00 00                       ← instr[3]
 00 00                       ← instr[4]
 00 00                       ← instr[5]
 00 00                       ← instr[6]
 00 00                       ← instr[7]
 00 00                       ← instr[8]
 00 00                       ← instr[9]
 00 00                       ← instr[10]
 00 00                       ← instr[11]
 00 00                       ← instr[12]
 00 00                       ← instr[13]
 00 00                       ← instr[14]
 00 00                       ← instr[15]
```

Total: **33 bytes** (1 cmd + 32 payload).

Each byte is framed as a standard UART character:

```
 Idle  Start  D0  D1  D2  D3  D4  D5  D6  D7  Stop  Idle
  1      0    b0  b1  b2  b3  b4  b5  b6  b7   1     1
```

Wait at least one full byte-time (≈1.04 ms at 9600 baud) between bytes
if bit-banging manually, or just send them back-to-back.

---

## Step 3 — Send the RUN Command

Choose your initial velocity v0 in m/s.  Convert to Q16.16:

```
v0_fixed = round(v0_real × 65536)
```

Example: **v0 = 50 m/s** → `v0_fixed = 50 × 65536 = 3,276,800 = 0x0032_0000`

Send the `RUN` command — one command byte followed by 4 payload bytes
(v0 in Q16.16, **little-endian**):

```
UART bytes to send (hex) for v0 = 50 m/s:
 02              ← CMD_RUN
 00              ← v0[7:0]
 00              ← v0[15:8]
 32              ← v0[23:16]
 00              ← v0[31:24]
```

Total: **5 bytes**.

On receipt of the 4th v0 byte, the protocol parser asserts `run_start`
and the control FSM begins.

---

## Step 4 — What the Chip Does (Internal Sequence)

You do not drive any signals during computation.  For reference:

1. **INIT (states 1–6):** Compute `dt = 2·v0 / (g·N)` using the ALU,
   latch it.  Zero out t and y.  Pre-load `G_FIXED` into R5.
2. **Per step (states 7–36, repeated up to 100 times):**
   - Copy current time argument to R7.
   - Call f-engine 4× (k1 at t, k2 at t+dt/2, k3 at t+dt/2, k4 at t+dt).
   - Accumulate: `y += dt/6 · (k1 + 2k2 + 2k3 + k4)`, `t += dt`.
   - Transmit the (t, y) pair over UART (8 bytes, MSB-first for each
     32-bit word: t_high … t_low y_high … y_low).
3. **Termination:** When `y < 0` or `step_cnt == 100`, transmit
   `0xDEAD_BEEF` (4 bytes: `0xDE 0xAD 0xBE 0xEF`).

---

## Step 5 — Receive Output over UART

Each RK4 step produces **8 bytes** on `uart_tx`:

```
 Byte 0  t[31:24]   ← most-significant byte of t (Q16.16)
 Byte 1  t[23:16]
 Byte 2  t[15:8]
 Byte 3  t[7:0]     ← least-significant byte of t
 Byte 4  y[31:24]   ← MSB of y
 Byte 5  y[23:16]
 Byte 6  y[15:8]
 Byte 7  y[7:0]
```

Convert received values to real numbers:
```
t_real = t_fixed / 65536.0
y_real = y_fixed / 65536.0   (interpret as signed 32-bit first)
```

After the last step, receive the 4-byte done marker:
```
 0xDE  0xAD  0xBE  0xEF
```

---

## Step 6 — Optional JTAG Debug Reads During / After Computation

You can interleave JTAG reads at any time to watch the computation.
The most useful registers:

| JTAG addr | Contents                  | What to watch for          |
|-----------|---------------------------|----------------------------|
| `0x1`     | `{f_active, busy, state}` | `busy=1` while running     |
| `0x2`     | `rf_t` (current t)        | advances by dt each step   |
| `0x3`     | `rf_y` (current y)        | projectile height           |
| `0x4`     | `dt`                      | check computed time step   |
| `0x5`     | `alu_result`              | live ALU output            |

To read, e.g., `rf_y` (address `0x3`):

```
Phase 1 — Load IR = DBG_ADDR (3'b010, LSB first = 0, 1, 0):
  Cycle  TMS  TDI  State
    1     1    –   RTI → Select-DR-Scan
    2     1    –   → Select-IR-Scan
    3     0    –   → Capture-IR
    4     0    0   → Shift-IR   (IR bit 0 = 0)
    5     0    1   → Shift-IR   (IR bit 1 = 1)
    6     1    0   → Exit1-IR   (IR bit 2 = 0)
    7     1    –   → Update-IR  (IR latches 010 = DBG_ADDR)
    8     0    –   → Run-Test/Idle

Phase 2 — Write address 0x3 (0011 in binary, LSB first = 1, 1, 0, 0):
  Cycle  TMS  TDI  State
    1     1    –   RTI → Select-DR-Scan
    2     0    –   → Capture-DR
    3     0    1   → Shift-DR   (addr bit 0 = 1)
    4     0    1   → Shift-DR   (addr bit 1 = 1)
    5     0    0   → Shift-DR   (addr bit 2 = 0)
    6     1    0   → Exit1-DR   (addr bit 3 = 0)
    7     1    –   → Update-DR  (dbg_addr latches 0x3)
    8     0    –   → Run-Test/Idle

Phase 3 — Load IR = DBG_DATA (3'b011, LSB first = 1, 1, 0):
  Cycle  TMS  TDI  State
    1     1    –   RTI → Select-DR-Scan
    2     1    –   → Select-IR-Scan
    3     0    –   → Capture-IR
    4     0    1   → Shift-IR   (IR bit 0 = 1)
    5     0    1   → Shift-IR   (IR bit 1 = 1)
    6     1    0   → Exit1-IR   (IR bit 2 = 0)
    7     1    –   → Update-IR  (IR latches 011 = DBG_DATA)
    8     0    –   → Run-Test/Idle

Phase 4 — Shift out 32 bits (rf_y captured at Capture-DR):
  Cycle  TMS  State
    1     1    RTI → Select-DR-Scan
    2     0    → Capture-DR   ← rf_y snapshot loaded
    3–33  0    Shift-DR       ← bits 0–30 on TDO (LSB first)
    34    1    → Exit1-DR     ← bit 31 on TDO
    35    1    → Update-DR
    36    0    → Run-Test/Idle
```

Reassemble 32 TDO bits (bit 0 first) and divide by 65536 for the height
in meters.

---

## Complete Byte Sequence Summary

```
UART TX to chip:
  [01]                              — CMD_LOAD_PROG
  [70 BD F8 1C 00×28]               — 16 instructions (2 instructions + 14 zero-padded)
  [02]                              — CMD_RUN
  [XX XX XX XX]                     — v0 in Q16.16, little-endian
                                      e.g. v0=50m/s → [00 00 32 00]

UART RX from chip (per step, up to 100 times):
  [T3 T2 T1 T0 Y3 Y2 Y1 Y0]        — 8 bytes: t then y, MSB first

UART RX from chip (end of run):
  [DE AD BE EF]                     — done marker
```
