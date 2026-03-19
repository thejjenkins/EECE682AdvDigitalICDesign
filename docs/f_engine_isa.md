# rk4_f_engine — Instruction Set Architecture

## Overview

The `rk4_f_engine` is a micro-coded execution engine that evaluates a
user-defined function **f(t, y, v0)** within the RK4 integrator datapath.
It contains a 16-entry instruction memory (16 bits per word) loaded over UART
at runtime, allowing the physics function to be changed without resynthesizing
the chip.

When the control FSM pulses `f_start`, the engine resets its PC to 0 and
sequentially executes instructions through a two-phase pipeline
(EXEC → WB) until it hits a **HALT** flag or reaches address 15.

---

## Instruction Format (16 bits)

```
 15  14  13  12  11  10   9   8   7   6   5   4   3   2   1   0
├───┴───┴───┼───┴───┴───┼───┴───┴───┼───┴───┴───┼───┼───┴───┴───┤
│  src_a    │  src_b    │  alu_op   │   dest    │ H │  reserved │
│  [15:13]  │  [12:10]  │  [9:7]    │  [6:4]    │[3]│  [2:0]    │
└───────────┴───────────┴───────────┴───────────┴───┴───────────┘
```

| Field    | Bits    | Width | Description                           |
|----------|---------|-------|---------------------------------------|
| `src_a`  | [15:13] | 3     | Operand A source (register address)   |
| `src_b`  | [12:10] | 3     | Operand B source (register address)   |
| `alu_op` | [9:7]   | 3     | ALU operation select                  |
| `dest`   | [6:4]   | 3     | Destination register for write-back   |
| `H`      | [3]     | 1     | Halt flag — terminates program        |
| —        | [2:0]   | 3     | Reserved (write as `000`)             |

---

## Register File

The engine shares the system register file (8 × 32-bit, Q16.16 signed
fixed-point). The control FSM pre-loads relevant state before each f-engine
invocation.

| Address | Name  | Typical Content                            |
|---------|-------|--------------------------------------------|
| `000`   | R0    | **v0** — initial velocity                  |
| `001`   | R1    | **t** — current time (or t + dt/2, t + dt) |
| `010`   | R2    | **k1** — RK4 slope k1                      |
| `011`   | R3    | **k2** — RK4 slope k2                      |
| `100`   | R4    | **k3** — RK4 slope k3                      |
| `101`   | R5    | **k4** — RK4 slope k4                      |
| `110`   | R6    | **y** — current state variable             |
| `111`   | R7    | **acc** — general-purpose accumulator      |

> **Note:** During f-engine execution the source MUX MSB is hardwired to 0
> (`{1'b0, fe_src_a}`), so the engine can only read/write registers — not
> the constant table (G, dt, etc.). Any constants the program needs must be
> pre-loaded into registers by the control FSM or by earlier instructions.

---

## ALU Operations

All operations use Q16.16 signed fixed-point. Operand A is the primary
input; operand B is the secondary input (unused for unary ops).

| `alu_op` | Binary | Mnemonic | Operation                      |
|----------|--------|----------|--------------------------------|
| 0        | `000`  | **ADD**  | dest ← A + B                  |
| 1        | `001`  | **SUB**  | dest ← A − B                  |
| 2        | `010`  | **MUL**  | dest ← (A × B) >>> 16  (Q16.16 multiply) |
| 3        | `011`  | **SHL**  | dest ← A <<< 1  (×2)          |
| 4        | `100`  | **SHR**  | dest ← A >>> 1  (÷2, signed)  |
| 5        | `101`  | **ABS**  | dest ← \|A\|                  |
| 6        | `110`  | **NEG**  | dest ← −A                     |
| 7        | `111`  | **PASS** | dest ← A  (move / copy)       |

For unary operations (SHL, SHR, ABS, NEG, PASS) the `src_b` field is
ignored but should be set to `000` by convention.

---

## Execution Model

```
                 ┌──────────────────────────┐
                 │        S_IDLE            │
                 │  (wait for f_start)      │
                 └────────┬─────────────────┘
                          │ f_start
                          ▼
                 ┌──────────────────────────┐
          ┌─────│        S_EXEC            │
          │      │  decode → drive outputs  │
          │      └────────┬─────────────────┘
          │               │ (1 cycle for ALU)
          │               ▼
          │      ┌──────────────────────────┐
          │      │        S_WB             │
          │      │  assert wr_en           │
          │      │  check halt / PC==15    │
          │      └────────┬─────────────────┘
          │               │
          │       ┌───────┴────────┐
          │       │ halt or PC=15? │
          │       └───┬────────┬───┘
          │       no  │        │ yes
          │           ▼        ▼
          │      PC ← PC+1   f_done=1
          └──────┘           f_active=0
                              → S_IDLE
```

Each instruction takes **2 clock cycles** (EXEC + WB).
Maximum program length is **16 instructions** (PC 0–15).

---

## Instruction Encoding Quick Reference

Assembly-style shorthand:

```
<MNEMONIC>  <dest>, <src_a> [, <src_b>]  [HALT]
```

### Binary encoding helper

```
src_a[2:0]  src_b[2:0]  alu_op[2:0]  dest[2:0]  H  reserved[2:0]
  AAA          BBB          OOO         DDD       H     000
```

### Encoding examples

| Assembly              | Hex      | Binary                  | Description                     |
|-----------------------|----------|-------------------------|---------------------------------|
| `ADD R7, R6, R0`     | `0xC070` | `110_000_000_111_0_000` | acc ← y + v0                    |
| `SUB R7, R7, R1`     | `0xE4F0` | `111_001_001_111_0_000` | acc ← acc − t                   |
| `MUL R7, R7, R2`     | `0xE970` | `111_010_010_111_0_000` | acc ← acc × k1 (Q16.16)        |
| `PASS R2, R7`        | `0xE3A0` | `111_000_111_010_0_000` | k1 ← acc (move)                |
| `NEG R7, R6`         | `0xC370` | `110_000_110_111_0_000` | acc ← −y                        |
| `SHL R7, R7`         | `0xE1F0` | `111_000_011_111_0_000` | acc ← acc × 2                   |
| `SHR R7, R7`         | `0xE270` | `111_000_100_111_0_000` | acc ← acc / 2                   |
| `ABS R7, R7`         | `0xE2F0` | `111_000_101_111_0_000` | acc ← \|acc\|                   |
| `ADD R7, R6, R0 HALT`| `0xC078` | `110_000_000_111_1_000` | acc ← y + v0; then stop         |

---

## Programming Notes

1. **Maximum 16 instructions.** The PC is 4 bits wide (0–15). If the program
   does not contain a HALT, execution stops automatically after address 15.

2. **Register-only operands.** The f-engine cannot directly access the
   constant MUX (G_FIXED, dt, INV6, etc.). If a constant is needed, the
   control FSM must pre-load it into a spare register before calling
   `f_start`, or the program must compute it from available register values.

3. **Write-back every instruction.** Every instruction writes its ALU result
   to `dest`. Use R7 (acc) as a scratch register to avoid clobbering live
   state variables unintentionally.

4. **HALT on the last meaningful instruction.** Set bit [3] on the final
   instruction rather than wasting a slot on a NOP+HALT.

5. **Program loading.** Instructions are written via the UART protocol parser
   using the program-write interface (`prog_wr`, `prog_addr[3:0]`,
   `prog_data[15:0]`). Address 0 is executed first.

6. **Unused slots.** After reset, all instruction memory is zero
   (`16'h0000`), which decodes as `ADD R0, R0, R0` with no halt — a benign
   NOP that writes R0 ← R0 + R0. Always program a HALT to avoid executing
   stale zeros.

---

## Example Program: f(t, y, v0) = v0 − g·t

Evaluates the derivative of projectile height under constant gravity.
Assumes `g` is pre-loaded in R2 by the control FSM.

| Addr | Assembly             | Hex      | Comment                         |
|------|----------------------|----------|---------------------------------|
| 0    | `MUL R7, R2, R1`    | `0x4570` | acc ← g × t                    |
| 1    | `SUB R7, R0, R7 H`  | `0x1CF8` | acc ← v0 − acc; HALT           |

Result is left in R7 (acc) for the control FSM to route to the appropriate
k-register.
