# Vivado Serial CRC16 IP (SDR / DDR / QDR, optional SYSCLK sync)

A configurable **Serial CRC-16** calculator implemented in SystemVerilog (with Verilog Wrapper) and intended for **Vivado IP packaging (IP-XACT)**.  
The core computes CRC over a **1-bit serial stream** and supports multiple sampling modes (**SDR / DDR / QDR**) with optional synchronization of the CRC update logic to a **system clock** (`sysclk`).

This implementation defaults to **CRC-CCITT-FALSE** (`POLYNOMIAL=0x1021`, `INIT_VAL=0xFFFF`) and provides optional “flow-control style” status outputs (`crc_valid`, `byte_valid`) to indicate bit/byte progression.

---

## Key Features

- **CRC width:** 16-bit (CRC-16)
- **Default polynomial:** `0x1021` (CRC-CCITT-FALSE)
- **Default init seed:** `0xFFFF`
- **Serial input:** `serial_in` (1-bit) with qualifier `serial_in_valid`
- **Modes:**
  - **SDR**: sample on rising OR falling edge
  - **DDR**: sample on both edges of `sclk`
  - **QDR**: sample on both edges of `sclk` and both edges of `sclk_ps` (phase-shifted clock)
- **Clocking options:**
  - **SYNC_TO_SYSTEM_CLOCK="Yes"**: edge-detects `sclk`/`sclk_ps` inside `sysclk` domain and updates CRC on `sysclk`
  - **SYNC_TO_SYSTEM_CLOCK="No"**: updates CRC directly in the serial clock domain (using edge-triggered always_ff blocks)
- **Optional output invert:** `XOR_OUT="Yes"` produces `~lfsr_q`
- **Optional progress signals:** `ENABLE_FLOW_CONTROL="Yes"` enables `crc_valid` and `byte_valid`

---

## Module: `serial_crc_ip`

### Parameters

| Parameter | Type | Default | Description |
|----------|------|---------|-------------|
| `SYNC_TO_SYSTEM_CLOCK` | string | `"Yes"` | If `"Yes"`, CRC update runs on `sysclk` with edge-detection of serial clocks. If `"No"`, CRC updates in serial clock domain. |
| `DATA_RATE_MODE` | string | `"SDR"` | `"SDR"`, `"DDR"`, or `"QDR"` sampling mode. |
| `INPUT_SAMPLING_EDGE` | string | `"RISING"` | SDR only: `"RISING"` or `"FALLING"`. |
| `POLYNOMIAL` | logic [15:0] | `16'h1021` | CRC polynomial parameter (currently CRC logic is explicitly wired for CCITT 0x1021; see Notes). |
| `INIT_VAL` | logic [15:0] | `16'hFFFF` | LFSR initialization value. |
| `XOR_OUT` | string | `"No"` | If `"Yes"`, output CRC is inverted. |
| `ENABLE_FLOW_CONTROL` | string | `"No"` | If `"Yes"`, asserts `crc_valid` on every CRC update and `byte_valid` every 8 updates. |

> **Note:** Although `POLYNOMIAL` is exposed as a parameter for IP packaging, the `next_lfsr` combinational logic is currently an explicit CRC-CCITT (0x1021) mapping. If you need a fully generic polynomial implementation, extend the RTL accordingly.

---

### Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `sysclk` | input | 1 | System clock (used when `SYNC_TO_SYSTEM_CLOCK="Yes"`). |
| `sclk` | input | 1 | Serial clock (base clock). |
| `sclk_ps` | input | 1 | Phase-shifted serial clock (used for QDR sampling). |
| `rst` | input | 1 | Reset (active high). |
| `serial_in` | input | 1 | Serial data input bit. |
| `serial_in_valid` | input | 1 | Qualifies `serial_in` (only updates CRC when high). |
| `crc_en` | input | 1 | Enables CRC calculation. |
| `crc_out` | output | 16 | CRC output (optionally inverted via `XOR_OUT`). |
| `crc_valid` | output | 1 | Pulses when CRC updated (only meaningful when `ENABLE_FLOW_CONTROL="Yes"`). |
| `byte_valid` | output | 1 | Pulses every 8 processed bits (only meaningful when `ENABLE_FLOW_CONTROL="Yes"`). |

---

## How it Works

- The core maintains a 16-bit LFSR (`lfsr_q`).
- On each selected sampling event, it computes `feedback = lfsr_q[15] ^ serial_in` and updates the LFSR with the CRC-CCITT mapping (0x1021).
- `serial_in_valid` gates CRC advancement so you can stall the stream without corrupting CRC.
- `bit_counter` tracks how many bits have been processed (0–7) and drives `byte_valid`.

---

## Operating Modes

### SDR (Single Data Rate)
Set:
- `DATA_RATE_MODE="SDR"`
- `INPUT_SAMPLING_EDGE="RISING"` **or** `"FALLING"`

CRC updates on the selected edge of `sclk` (or its inverted version).

### DDR (Dual Data Rate)
Set:
- `DATA_RATE_MODE="DDR"`

CRC updates on **both** rising and falling edges of `sclk`.

### QDR (Quad Data Rate style)
Set:
- `DATA_RATE_MODE="QDR"`

CRC updates on **four sampling events** per serial clock period:
- rising + falling of `sclk`
- rising + falling of `sclk_ps` (phase shifted clock)

> You must supply a stable phase relationship between `sclk` and `sclk_ps` using MMCM/PLL or a trusted clocking scheme.

---

## Clocking / CDC Behavior

### `SYNC_TO_SYSTEM_CLOCK="Yes"` (recommended when integrating with system logic)
- `sclk` and `sclk_ps` are synchronized into `sysclk` using 2-FF synchronizers.
- The module performs edge detection in the `sysclk` domain.
- CRC updates happen on `sysclk` when the selected edge event(s) are detected.

This makes `crc_out` naturally aligned to `sysclk` logic, but you must ensure `sysclk` is fast enough to observe the serial edges (especially DDR/QDR).

### `SYNC_TO_SYSTEM_CLOCK="No"`
- CRC updates occur directly on serial-clock edges using edge-triggered `always_ff`.
- Use this when you want the CRC strictly in the serial clock domain, and you will handle CDC outside.

> ⚠️ **Implementation Note:** The async/QDR block uses multi-event sensitivity with derived “inverted clocks” (e.g., `posedge sclk_inv`). Many FPGA flows do **not** recommend or support using combinationally inverted clocks as true clocks. Prefer using proper clocking resources (BUFG/BUFH) and/or clock enables, and avoid `~clk` as a clock input where possible.

---

## Outputs

- `crc_out` reflects the running CRC (or inverted CRC if `XOR_OUT="Yes"`).
- When `ENABLE_FLOW_CONTROL="Yes"`:
  - `crc_valid` pulses when CRC updated for a processed bit.
  - `byte_valid` pulses when `bit_counter == 7` (every 8 processed bits).

When `ENABLE_FLOW_CONTROL="No"`, the module keeps these outputs deasserted.

---



