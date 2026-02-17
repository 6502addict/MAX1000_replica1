# MAX1000_Replica1 – Minimal Apple-1 on FPGA

A minimal recreation of the Apple-1 computer running entirely from SDRAM, implemented on the Arrow/Trenz MAX1000 IoT Maker Board.

## ⚖️ License

Licensed under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).  
**Commercial use forbidden.** 

---

## Hardware

| Item       | Details                             |
|-----------|-------------------------------------|
| Board      | Arrow/Trenz MAX1000 TEI0001-04-FBC84A |
| FPGA       | Intel MAX10 10M08SAU169C8G (8K LE)  |
| SDRAM      | Winbond W9825G6KB-6 (32 MB, BGA)   |
| Programmer | Arrow USB programmer (on-board)     |

---

## What is implemented

This is a cut-down Replica1 — only the essential Apple-1 hardware:

- **MX65** — 6502 CPU core
- **Console PIA** — routed to the on-board UART (BDBUS)
- **ACI** — cassette tape interface, routed to PMOD (PIO 0/1)

All program memory runs from SDRAM via the sram_sdram_bridge. No internal Block RAM is used for program storage.

---

## Connections

| Signal     | Pin      | Notes                          |
|-----------|----------|--------------------------------|
| Terminal TX | BDBUS(0) | To USB-UART RX (or Arrow programmer) |
| Terminal RX | BDBUS(1) | From USB-UART TX               |
| Tape out   | PIO(0)   | Audio out to cassette          |
| Tape in    | PIO(1)   | Audio in from cassette         |

---

## Terminal Settings

| Parameter | Value  |
|-----------|--------|
| Baud rate | 115200 |
| Data bits | 8      |
| Parity    | None   |
| Stop bits | 1      |

---

## ROM Options

Select via the `ROM` constant in `MAX1000_Replica1.vhd`:

| Value       | Description                              |
|------------|------------------------------------------|
| `WOZMON65` | Wozniak monitor only (bare minimum)      |
| `BASIC65`  | Wozniak monitor + reduced Applesoft BASIC |

To launch BASIC from the monitor prompt: `E000R`

---

## Configuration

All settings are in the **Board Configuration Parameters** section of `MAX1000_Replica1.vhd`.

| Constant         | Default   | Description                              |
|-----------------|-----------|------------------------------------------|
| `ROM`            | `BASIC65` | ROM image selection                      |
| `RAM_SIZE_KB`    | 48        | RAM visible to 6502 (8 to 48 KB)        |
| `BAUD_RATE`      | 115200    | Serial port speed                        |
| `SDRAM_MHZ`      | 120       | SDRAM clock (max 133 for W9825G6KB-6)   |
| `ROW_BITS`       | 13        | Fixed for W9825G6KB-6                   |
| `COL_BITS`       | 9         | Fixed for W9825G6KB-6                   |
| `TRP_NS`         | 15        | Precharge time (ns)                      |
| `TRCD_NS`        | 15        | RAS-to-CAS delay (ns)                   |
| `TRFC_NS`        | 60        | Refresh cycle time (ns)                 |
| `CAS_LATENCY`    | 2         | CAS latency cycles                       |
| `AUTO_PRECHARGE` | false     | Row stays open between accesses         |
| `AUTO_REFRESH`   | false     | Bridge generates refresh requests       |

### CPU Speed

The PLL `c0` output runs at 4× the desired CPU speed. Edit `main_clock.vhd` to change it.

| CPU speed | PLL c0 |
|-----------|--------|
| 1 MHz     | 4 MHz  |
| 4 MHz     | 16 MHz |
| 8 MHz     | 32 MHz |
| 10 MHz    | 40 MHz |
| 15 MHz    | 60 MHz |

---

## Changelog

| Date       | Description      |
|------------|-----------------|
| 2026/02/17 | Initial version  |

