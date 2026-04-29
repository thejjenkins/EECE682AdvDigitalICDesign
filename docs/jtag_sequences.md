# JTAG TAP Debug Sequences

Reference for the `jtag_tap` module in `rk4_projectile_top`.

## Conventions

- All signals are sampled/driven on TCK edges: **TMS and TDI are sampled on the rising edge**, **TDO updates on the falling edge**.
- The IR is **3 bits** wide, shifted in **LSB first**.
- All data registers are shifted **LSB first**.
- After reset (`trst_n` low, or 5+ TCK cycles with TMS=1), the TAP is in `Test-Logic-Reset` and the active instruction defaults to `IDCODE`.

## IR Instruction Codes

| Code (binary) | Name     | Selected DR      | Width  |
|---------------|----------|------------------|--------|
| `001`         | IDCODE   | Chip ID register | 32-bit |
| `010`         | DBG_ADDR | Debug address    | 4-bit  |
| `011`         | DBG_DATA | Debug data       | 32-bit |
| `000`         | BYPASS   | Bypass register  | 1-bit  |
| `111`         | BYPASS   | Bypass register  | 1-bit  |

## Debug Address Map

| Address (hex) | Contents                                              |
|---------------|-------------------------------------------------------|
| `0x0`         | `{24'b0, uart_rx, step_cnt[6:0]}`                    |
| `0x1`         | `{24'b0, f_active, busy, fsm_state[5:0]}`            |
| `0x2`         | `rf_t[31:0]` (register file T value)                 |
| `0x3`         | `rf_y[31:0]` (register file Y value)                 |
| `0x4`         | `dt[31:0]` (time step)                               |
| `0x5`         | `alu_result[31:0]`                                   |
| `0x6`         | `alu_a[31:0]` (ALU operand A)                        |
| `0x7`         | `alu_b[31:0]` (ALU operand B)                        |
| `0x8`         | `{20'b0, proto_pstate[1:0], tx_bytes_left[3:0], fe_pc[3:0], fe_estate[1:0]}` |
| `0x9–0xF`     | Returns `0x00000000`                                  |

---

## A) Read the IDCODE

After reset the IR already holds `IDCODE`, so you only need to do a DR scan. If you're unsure of the current state, reset first.

### Step 1 — Reset (optional, ensures known state)

```
TCK:  __|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__
TMS:     1     1     1     1     1
TDI:     x     x     x     x     x
```

Hold TMS=1 for 5 rising edges of TCK. The TAP enters `Test-Logic-Reset`. IR defaults to `IDCODE`.

### Step 2 — Go to Run-Test/Idle

```
TCK:  __|‾‾|__
TMS:     0
```

One TCK with TMS=0 brings you to `Run-Test/Idle`.

### Step 3 — Enter DR scan path

```
TCK:  __|‾‾|__|‾‾|__
TMS:     1     0
```

| TCK edge | TMS | State transition              |
|----------|-----|-------------------------------|
| 1        | 1   | Run-Test/Idle → Select-DR-Scan|
| 2        | 0   | Select-DR-Scan → Capture-DR   |

At `Capture-DR`, the IDCODE value (`0xEECE_00DE`) is loaded into the shift register.

### Step 4 — Shift out 32 bits

```
TCK:  __|‾‾|__|‾‾|__ ... __|‾‾|__|‾‾|__
TMS:     0     0     ...    0     1
TDI:     x     x     ...    x     x
TDO:   bit0  bit1    ...  bit30  bit31
```

- Keep TMS=0 for 31 TCK cycles (bits 0–30 appear on TDO).
- On the 32nd TCK, set TMS=1 to exit (bit 31 appears on TDO, state moves to `Exit1-DR`).

You now have all 32 bits of the IDCODE, shifted out LSB first.

### Step 5 — Return to Run-Test/Idle

```
TCK:  __|‾‾|__|‾‾|__
TMS:     1     0
```

| TCK edge | TMS | State transition          |
|----------|-----|---------------------------|
| 1        | 1   | Exit1-DR → Update-DR      |
| 2        | 0   | Update-DR → Run-Test/Idle |

### Complete IDCODE waveform (all 39 TCK cycles)

```
Cycle:  R  R  R  R  R  I  S  C  D0 D1 D2 ... D30 D31 U  I
TMS:    1  1  1  1  1  0  1  0  0  0  0  ...  0   1   1  0
State: TLR .................. RTI SD CD SH SH SH  SH  E1 UD RTI
TDO:                            x  x b0 b1 b2 .. b30 b31
```

Result: reassemble the 32 TDO bits (LSB first) → `0xEECE_00DE`.

---

## B) Read a Debug Register (e.g., address 0x5 = ALU result)

This requires two operations:
1. **Write `0x5` into DBG_ADDR** (select the debug group)
2. **Read 32 bits from DBG_DATA** (shift out the selected data)

### Phase 1: Load IR with DBG_ADDR (`010`)

Starting from `Run-Test/Idle`:

```
Cycle:  1   2   3   4   5   6   7   8   9
TMS:    1   1   0   0   0   0   1   1   0
State: RTI→SD→SIS→CI→SI→SI→SI→E1I→UI→RTI
TDI:              0   1   0
```

| Cycle | TMS | TDI | State              | What happens                         |
|-------|-----|-----|--------------------|--------------------------------------|
| 1     | 1   | —   | → Select-DR-Scan   |                                      |
| 2     | 1   | —   | → Select-IR-Scan   |                                      |
| 3     | 0   | —   | → Capture-IR       | Shift reg loads `001`                |
| 4     | 0   | 0   | → Shift-IR         | Shift in bit 0 of `010` → TDI=0     |
| 5     | 0   | 1   | → Shift-IR         | Shift in bit 1 of `010` → TDI=1     |
| 6     | 1   | 0   | → Exit1-IR         | Shift in bit 2 of `010` → TDI=0     |
| 7     | 1   | —   | → Update-IR        | IR latches `010` (DBG_ADDR)          |
| 8     | 0   | —   | → Run-Test/Idle    |                                      |

IR now holds `DBG_ADDR`.

### Phase 2: Write address 0x5 (`0101`) into DBG_ADDR data register

Starting from `Run-Test/Idle`:

```
Cycle:  1   2   3   4   5   6   7   8
TMS:    1   0   0   0   0   1   1   0
State: RTI→SD→CD→SH→SH→SH→SH→E1→UD→RTI
TDI:          1   0   1   0
```

| Cycle | TMS | TDI | State            | What happens                          |
|-------|-----|-----|------------------|---------------------------------------|
| 1     | 1   | —   | → Select-DR-Scan |                                       |
| 2     | 0   | —   | → Capture-DR     | Shift reg loads current addr          |
| 3     | 0   | 1   | → Shift-DR       | Shift in bit 0 of `0101` → TDI=1     |
| 4     | 0   | 0   | → Shift-DR       | Shift in bit 1 → TDI=0               |
| 5     | 0   | 1   | → Shift-DR       | Shift in bit 2 → TDI=1               |
| 6     | 1   | 0   | → Exit1-DR       | Shift in bit 3 → TDI=0               |
| 7     | 1   | —   | → Update-DR      | `dbg_addr_q` latches `0101` (= 0x5)  |
| 8     | 0   | —   | → Run-Test/Idle  |                                       |

Debug mux now selects address 0x5 → `alu_result[31:0]`.

### Phase 3: Load IR with DBG_DATA (`011`)

Same procedure as Phase 1 but shift in `011`:

```
Cycle:  1   2   3   4   5   6   7   8
TMS:    1   1   0   0   0   1   1   0
TDI:              1   1   0
```

| Cycle | TMS | TDI | State            | What happens                    |
|-------|-----|-----|------------------|---------------------------------|
| 1     | 1   | —   | → Select-DR-Scan |                                |
| 2     | 1   | —   | → Select-IR-Scan |                                |
| 3     | 0   | —   | → Capture-IR     |                                |
| 4     | 0   | 1   | → Shift-IR       | Bit 0 of `011`                 |
| 5     | 0   | 1   | → Shift-IR       | Bit 1 of `011`                 |
| 6     | 1   | 0   | → Exit1-IR       | Bit 2 of `011`                 |
| 7     | 1   | —   | → Update-IR      | IR latches `011` (DBG_DATA)    |
| 8     | 0   | —   | → Run-Test/Idle  |                                |

### Phase 4: Read 32 bits from DBG_DATA

Starting from `Run-Test/Idle`:

```
Cycle:  1   2   3   4   5  ...  33  34  35
TMS:    1   0   0   0   0  ...   0   1   1   0
TDI:          x   x   x   ...   x   x
TDO:              b0  b1  ...  b30 b31
```

| Cycle | TMS | State            | What happens                           |
|-------|-----|------------------|----------------------------------------|
| 1     | 1   | → Select-DR-Scan |                                        |
| 2     | 0   | → Capture-DR     | `alu_result` snapshot loaded into shift reg |
| 3–33  | 0   | → Shift-DR (x31) | Bits 0–30 shift out on TDO             |
| 34    | 1   | → Exit1-DR       | Bit 31 shifts out on TDO               |
| 35    | 1   | → Update-DR      |                                        |
| 36    | 0   | → Run-Test/Idle  |                                        |

Reassemble the 32 TDO bits LSB-first to get the `alu_result` value.

---

## Quick Reference: Total TCK Cycles

| Operation                | TCK cycles |
|--------------------------|------------|
| Reset                    | 5          |
| Read IDCODE (after reset)| ~36        |
| Full debug read (addr+data) | ~52     |

## Repeating Debug Reads

To read a different address, repeat from Phase 2 (write new address into DBG_ADDR). You don't need to reload `DBG_ADDR` into the IR if it's already selected.

To read the same address again, skip straight to Phase 4 (the IR already holds `DBG_DATA` and the address is latched). Just do another DR scan.
