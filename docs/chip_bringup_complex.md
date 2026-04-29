# Chip Bringup — Complex Function: f(t) = 2t − 5t²

This guide programs the f-engine with a polynomial derivative, demonstrates
using v0 as a scaling parameter to control the integration time window, and
shows how to interpret the (t, y) output stream.

**What the chip integrates:**

> dy/dt = f(t) = 2t − 5t²,   y(0) = 0

The analytical solution is:

> y(t) = t² − (5/3)t³

which peaks near t ≈ 0.4 s and returns to y = 0 at t = 0.6 s.  The chip
terminates when y first goes negative.

---

## Background — How the f-Engine Handles Constants

The f-engine can only read from the 8-register file.  It cannot directly
reach the hardware constant table (G, dt, 1/6, etc.).  The control FSM
pre-populates:

| Register | Content at f_start time      |
|----------|------------------------------|
| R0       | v0 (from RUN command)        |
| R1       | current t or t+dt/2 or t+dt  |
| R5       | G_FIXED (9.8 in Q16.16)      |
| R7       | same time argument as R1     |
| R2–R4    | k1, k2, k3 from earlier calls|
| R6       | y (current height)           |

For a pure polynomial f(t) = 2t − 5t², we do **not** need G_FIXED.  We
repurpose R5 as a second scratch register inside the program, overwriting
it safely (it is re-loaded by the FSM at the start of every step, before
calling f_start for k1).

**v0 controls the integration window**, not the physics:

```
dt = 2 × v0 / (G_FIXED × NUM_DIV)
   = 2 × v0 / (9.8 × 100)
```

To cover t ∈ [0, 0.6 s] in 100 steps we need dt = 0.006 s, which gives:

```
v0 = dt × 9.8 × 100 / 2 = 0.006 × 9.8 × 100 / 2 ≈ 2.94 m/s
v0 in Q16.16 = round(2.94 × 65536) = 192,676 = 0x0002_F0A4
```

---

## Step 0 — Power-On / Reset

Same as the simple guide:

1. Assert `rst_n = 0` for ≥ 10 clock cycles, then release (`rst_n = 1`).
2. Pull `uart_rx` HIGH (idle line).
3. Pull `tms = 1`, apply 5+ TCK pulses → TAP enters `Test-Logic-Reset`,
   IR defaults to `IDCODE`.

---

## Step 1 — Optional Sanity Check: Read IDCODE via JTAG

Verify `0xEECE_00DE` exactly as in the simple guide (same 37 TCK cycles
from TLR).  Skip only if you are already confident of power and TAP state.

---

## Step 2 — Design the f-Engine Program

### Derivation

We want R7 = 2t − 5t² at program exit, using only R1 (= t) and R7 / R5
as scratch.

| Step | Operation             | Register state                            |
|------|-----------------------|-------------------------------------------|
| 0    | `MUL R5, R1, R1`     | R5 ← t²  (save t² before R7 is touched)  |
| 1    | `SHL R7, R5`         | R7 ← 2t²                                 |
| 2    | `SHL R7, R7`         | R7 ← 4t²                                 |
| 3    | `ADD R7, R7, R5`     | R7 ← 5t²                                 |
| 4    | `SHL R5, R1`         | R5 ← 2t  (repurpose R5)                  |
| 5    | `SUB R7, R5, R7 HALT`| R7 ← 2t − 5t²; stop                      |

### Instruction encodings

Format: `[src_a(3) | src_b(3) | alu_op(3) | dest(3) | H(1) | 000(3)]`

ALU ops: ADD=0, SUB=1, MUL=2, SHL=3, SHR=4, ABS=5, NEG=6, PASS=7

| Addr | Assembly              | Hex    | Bytes LE | Derivation                                      |
|------|-----------------------|--------|----------|-------------------------------------------------|
|  0   | `MUL R5, R1, R1`     | `0x2550` | `50 25` | `001_001_010_101_0_000` = 0x2550               |
|  1   | `SHL R7, R5`         | `0xA1F0` | `F0 A1` | `101_000_011_111_0_000` = 0xA1F0               |
|  2   | `SHL R7, R7`         | `0xE1F0` | `F0 E1` | `111_000_011_111_0_000` = 0xE1F0               |
|  3   | `ADD R7, R7, R5`     | `0xF470` | `70 F4` | `111_101_000_111_0_000` = 0xF470               |
|  4   | `SHL R5, R1`         | `0x21D0` | `D0 21` | `001_000_011_101_0_000` = 0x21D0               |
|  5   | `SUB R7, R5, R7 H`   | `0xBCF8` | `F8 BC` | `101_111_001_111_1_000` = 0xBCF8               |
| 6–15 | (unused)             | `0x0000` | `00 00` | NOP — ADD R0,R0,R0 (benign, no halt reached)   |

> The HALT bit on instruction 5 ensures the program stops before executing
> the zero-padded slots.

---

## Step 3 — Load the Program over UART

Send 33 bytes: `CMD_LOAD_PROG (0x01)` + 32 payload bytes.

```
UART bytes (hex), send in order, 9600 baud 8-N-1:

01          ← CMD_LOAD_PROG
50 25       ← instr[0]  0x2550  MUL R5,R1,R1
F0 A1       ← instr[1]  0xA1F0  SHL R7,R5
F0 E1       ← instr[2]  0xE1F0  SHL R7,R7
70 F4       ← instr[3]  0xF470  ADD R7,R7,R5
D0 21       ← instr[4]  0x21D0  SHL R5,R1
F8 BC       ← instr[5]  0xBCF8  SUB R7,R5,R7 HALT
00 00       ← instr[6]   padding
00 00       ← instr[7]
00 00       ← instr[8]
00 00       ← instr[9]
00 00       ← instr[10]
00 00       ← instr[11]
00 00       ← instr[12]
00 00       ← instr[13]
00 00       ← instr[14]
00 00       ← instr[15]
```

Each byte is a standard 8-N-1 UART frame (start bit LOW, 8 data bits LSB
first, stop bit HIGH).  Bytes may be sent back-to-back at 9600 baud
(≈ 1 ms/byte, 33 bytes ≈ 34 ms total).

The protocol parser will assert `prog_wr` 16 times, writing each
instruction into the f-engine memory.  There is no ACK — proceed
immediately.

---

## Step 4 — Send the RUN Command

We set v0 = 2.94 m/s so that 100 RK4 steps span t ∈ [0, 0.6 s], just
covering the full arch of y(t).

```
v0 real   = 2.94 m/s
v0 Q16.16 = round(2.94 × 65536) = 192,676 = 0x0002_F0A4
```

Send 5 bytes:

```
02          ← CMD_RUN
A4          ← v0[7:0]
F0          ← v0[15:8]
02          ← v0[23:16]
00          ← v0[31:24]
```

On receipt of the 4th v0 byte the chip immediately starts.

**Computing dt for verification:**

```
dt = 2 × 2.94 / (9.8 × 100) = 0.006 s exactly
dt in Q16.16 = round(0.006 × 65536) = 393
```

You can read this back via JTAG address `0x4` after the run starts.

---

## Step 5 — What the Chip Does (Internal Sequence)

```
 INIT:
   acc = v0 << 1           (= 2v0)
   acc = acc × (1/g)       → 2v0/g
   acc = acc × (1/N)       → dt = 2v0/(gN);  latch dt, dt_half
   t   = 0
   y   = 0
   R5  = G_FIXED           (← overwritten by program, but re-loaded each step!)

 For step n = 0 … 99:
   R5 ← G_FIXED   (S_PRELOAD_G)
   R7 ← t         (S_PRELOAD_T; time arg for k1)

   f_start → k1 = f(t)
     [program runs: R5←t², R7←2t², R7←4t², R7←5t², R5←2t, R7←2t−5t²]
   k1 = R7

   R7 ← t + dt/2  (K2 prep)
   f_start → k2 = f(t + dt/2)   [same 6-instruction program]

   R7 ← t + dt/2  (K3 prep)
   f_start → k3 = f(t + dt/2)

   R7 ← t + dt    (K4 prep)
   f_start → k4 = f(t + dt)

   y += dt/6 × (k1 + 2k2 + 2k3 + k4)
   t += dt
   step_cnt++

   TX: send (t[31:0], y[31:0]) → 8 bytes on uart_tx

   CHECK: if y < 0 or step_cnt == 100 → go to DONE

 DONE: TX 0xDEADBEEF (4 bytes)
```

---

## Step 6 — Receive and Decode the Output

**Per-step output (8 bytes, MSB first for each word):**

```
Byte 0  t[31:24]
Byte 1  t[23:16]
Byte 2  t[15:8]
Byte 3  t[7:0]    → t_real = signed_value / 65536.0
Byte 4  y[31:24]
Byte 5  y[23:16]
Byte 6  y[15:8]
Byte 7  y[7:0]    → y_real = signed_value / 65536.0
```

You will receive up to 100 × 8 = 800 bytes before the done marker.

**Expected output highlights (analytical):**

| Step | t (s)  | y(t) = t²−(5/3)t³ |
|------|--------|-------------------|
|  0   | 0.006  | 0.000036          |
| 16   | 0.096  | 0.008537          |
| 33   | 0.198  | 0.030336          |
| 50   | 0.300  | 0.045000          |
| 66   | 0.396  | 0.034032          |
| 83   | 0.498  | 0.005028          |
| 99   | 0.594  | −0.000396 (trigger)|

The run ends when step_cnt hits 100 **or** y first crosses below zero
(whichever comes first).  With these parameters the y < 0 check triggers
at the last few steps.

**Done marker (4 bytes):**

```
DE  AD  BE  EF
```

---

## Step 7 — Optional JTAG Debug During Computation

Suggested polling sequence while computation is in progress:

```
1. Poll address 0x1 until busy=1 (run started):
   DBG_REG[0x1] = {f_active[7], busy[6], fsm_state[5:0]}
   Wait for bit[6] = 1.

2. Read dt to verify it was computed correctly:
   DBG_REG[0x4] = dt in Q16.16
   Expected: round(0.006 × 65536) = 393 = 0x00000189

3. Watch y accumulate:
   DBG_REG[0x3] = rf_y, signed Q16.16
   Divide by 65536 for meters.

4. Watch ALU result mid-computation:
   DBG_REG[0x5] = alu_result
   During f-engine, this is the intermediate polynomial computation.

5. Check f-engine PC:
   DBG_REG[0x8] bits [5:2] = fe_pc
   Should cycle 0→5 then assert f_done.

6. Wait for busy=0 and TDO output from UART:
   DBG_REG[0x1] bit[6] returns to 0 when FSM back in S_IDLE.
```

Each complete debug read (addr select + data shift) takes ~52 TCK cycles.
At a conservative TCK of 1 MHz and 100 steps × 4 f-calls × 6 instructions
= 2400 ALU cycles at 10 MHz system clock, you have ample time to read
multiple registers between steps.

---

## Complete Byte Sequence Summary

```
── UART TX to chip ─────────────────────────────────────────────────────

[01]                     CMD_LOAD_PROG
[50 25]                  instr[0]  MUL R5,R1,R1  (t^2 → R5)
[F0 A1]                  instr[1]  SHL R7,R5     (2t^2 → R7)
[F0 E1]                  instr[2]  SHL R7,R7     (4t^2 → R7)
[70 F4]                  instr[3]  ADD R7,R7,R5  (5t^2 → R7)
[D0 21]                  instr[4]  SHL R5,R1     (2t → R5)
[F8 BC]                  instr[5]  SUB R7,R5,R7 H  (2t-5t^2 → R7; HALT)
[00 00] × 10             instr[6..15] unused / zero-padded

[02]                     CMD_RUN
[A4 F0 02 00]            v0 = 2.94 m/s in Q16.16 little-endian

── UART RX from chip ────────────────────────────────────────────────────

[T3 T2 T1 T0  Y3 Y2 Y1 Y0]  × (up to 100)   8-byte (t,y) pairs
[DE AD BE EF]                                  done marker
```

---

## Variant: Choose a Different Polynomial

The program structure works for any f(t) = a·t − b·t² by adjusting:

- **Coefficient `a`:** Use `SHL` (×2), double-`SHL` (×4), or a `MUL`
  with a register pre-loaded to hold `a` in Q16.16.  If `a = v0`, just
  do `MUL R7, R0, R1` (no SHL needed).
- **Coefficient `b`:** Build `b·t²` using repeated `SHL` and `ADD` of
  the saved t² in R5.  The table below shows common multipliers:

| Multiplier | Sequence (R7 ← n·R7)               |
|------------|-------------------------------------|
| ×2         | `SHL R7, R7`                       |
| ×3         | save R5=R7; `SHL R7,R7`; `ADD R7,R7,R5` |
| ×4         | `SHL` twice                        |
| ×5         | `SHL` twice + `ADD` with saved ×1  |
| ×6         | `SHL` + `ADD` + `SHL`             |
| ×8         | `SHL` three times                  |

- **Time window:** Adjust v0 so dt = desired\_step / (baud_div calc above).
  `v0 = dt × 9.8 × 100 / 2`.
