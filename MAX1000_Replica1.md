# MAX1000 Replica1 – User Manual

## Overview

MAX1000_Replica1 is an FPGA recreation of the Apple-1 computer, implemented on the Arrow/Trenz MAX1000 IoT Maker Board. It features a MX65 (6502) CPU running entirely from SDRAM, with a console terminal interface and a cassette tape interface.

---

## Hardware

### Board – Arrow/Trenz MAX1000 (TEI0001-04-FBC84A)

| Item         | Details                              |
|-------------|--------------------------------------|
| Size         | 6.15 × 2.5 cm                        |
| FPGA         | Intel MAX10 10M08SAU169C8G (8K LE)   |
| SDRAM        | Winbond W9825G6KB-6 (32 MB, BGA)     |
| Flash        | 8 MB QSPI (bitstream)                |
| Programmer   | Arrow USB programmer (on-board)      |
| Clock        | 12 MHz crystal                       |

### Connections Required

| Function     | MAX1000 Pin  | Notes                                 |
|-------------|--------------|---------------------------------------|
| Terminal TX  | BDBUS(0)     | Connect to USB-UART adapter RX        |
| Terminal RX  | BDBUS(1)     | Connect to USB-UART adapter TX        |
| Tape out     | PIO(0)       | Audio output to cassette recorder     |
| Tape in      | PIO(1)       | Audio input from cassette recorder    |
| Reset        | RESET        | Active low, pull high for normal run  |

> **Note:** The on-board Arrow USB programmer provides the UART via BDBUS. No separate USB-UART adapter may be needed depending on your driver setup.

---

## System Architecture

```
  12 MHz crystal
       │
    ┌──┴──────────────────────┐
    │  PLL (main_clock)       │
    │  c0 = 4x CPU clock      │  e.g. 40 MHz for 10 MHz CPU
    │  c1 = 1.8432 MHz        │  baud rate generator
    │  c2 = 120 MHz           │  SDRAM clock
    └──┬───────────┬──────────┘
       │           │
  ┌────┴────┐  ┌───┴──────────────────────────────┐
  │Replica1 │  │sram_sdram_bridge                 │
  │  CORE   │  │ 8-bit SRAM bus → 16-bit SDRAM    │
  │         │  │ clock stretching via dy          │
  │  MX65   │  └───────────────┬──────────────────┘
  │  (6502) │                  │
  │  PIA ───┼── BDBUS (UART)   │
  │  ACI ───┼── PIO(0/1) tape  │
  └─────────┘          ┌───────┴───────────┐
                       │  sdram_controller │
                       │  W9825G6KB-6      │
                       │  32 MB SDRAM      │
                       └───────────────────┘
```

---

## ROM Options

Two ROM images are available, selected by the `ROM` constant:

### WOZMON65 — Bare minimum
The original Wozniak monitor. Allows you to examine and modify memory, enter programs in hexadecimal and run them. No BASIC.

```
\```
0000: A9 00 AA 20 EF FF ...    (enter hex bytes)
0000R                           (run from address)
0000.00FF                       (examine memory range)
\```
```

### BASIC65 — Monitor + Applesoft BASIC
Includes the Wozniak monitor plus a reduced version of Applesoft BASIC. At startup type `E000R` to launch BASIC from the monitor prompt.

```
\```
E000R
>10 PRINT "HELLO"
>20 GOTO 10
>RUN
\```
```

---

## Terminal Setup

Connect a serial terminal (e.g. PuTTY, minicom, screen) to the UART port.

| Parameter    | Value              |
|-------------|--------------------|
| Baud rate    | 115200 (default)   |
| Data bits    | 8                  |
| Parity       | None               |
| Stop bits    | 1                  |
| Flow control | None               |

The baud rate is configurable — see the Configuration section below.

---

## Cassette Tape Interface (ACI)

The ACI (Apple Cassette Interface) is routed to the PMOD connector:

- **PIO(0)** — `tape_out` : audio signal out to cassette recorder input
- **PIO(1)** — `tape_in`  : audio signal in from cassette recorder output

Use standard cassette SAVE/LOAD commands from BASIC or monitor as on the original Apple-1.

---

## Configuration

To reconfigure the machine, open the top-level file `MAX1000_Replica1.vhd` and locate the **Board Configuration Parameters** section. Edit the constants as needed, then resynthesize and reprogram.

### Constants Reference

```vhdl
constant ROM          : string   := "BASIC65";
-- "WOZMON65" = monitor only
-- "BASIC65"  = monitor + Applesoft BASIC
```

```vhdl
constant RAM_SIZE_KB  : positive := 48;
-- RAM visible to the 6502: 8 to 48 KB
-- Limited by the 6502 memory map, not the SDRAM size (32 MB)
```

```vhdl
constant BAUD_RATE    : integer  := 115200;
-- Serial port speed: 1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200
-- Must match your terminal settings
```

```vhdl
constant SDRAM_MHZ    : integer  := 120;
-- SDRAM controller clock frequency in MHz
-- Must match PLL output c2
-- Maximum safe value for W9825G6KB-6: 133 MHz
```

```vhdl
constant ROW_BITS     : integer  := 13;   -- fixed for W9825G6KB-6
constant COL_BITS     : integer  := 9;    -- fixed for W9825G6KB-6
```

```vhdl
constant TRP_NS       : integer  := 15;   -- Precharge time (ns)
constant TRCD_NS      : integer  := 15;   -- RAS-to-CAS delay (ns)
constant TRFC_NS      : integer  := 60;   -- Refresh cycle time (ns)
-- These values are correct for W9825G6KB-6 - do not change unless you change the SDRAM chip
```

```vhdl
constant CAS_LATENCY  : integer  := 2;
-- CAS latency cycles: 2 (safe up to 133 MHz for W9825G6KB-6)
-- Use 3 only if running at very high frequency
```

```vhdl
constant AUTO_PRECHARGE : boolean := false;
-- false = row stays open between accesses (faster sequential access)
-- true  = row closes automatically after each access (simpler, slightly slower)
```

```vhdl
constant AUTO_REFRESH   : boolean := false;
-- false = sram_sdram_bridge generates refresh requests (recommended)
-- true  = sdram_controller generates refresh internally
```

### CPU Speed

The CPU speed is controlled by the PLL output `c0` in `main_clock.vhd`.
The Replica1 core divides `c0` internally by 4, so:

| Desired CPU speed | PLL c0 output |
|------------------|---------------|
| 1 MHz            | 4 MHz         |
| 2 MHz            | 8 MHz         |
| 4 MHz            | 16 MHz        |
| 8 MHz            | 32 MHz        |
| 10 MHz           | 40 MHz        |
| 15 MHz           | 60 MHz        |

> The valid range is **1 to 15 MHz** CPU speed (4 to 60 MHz PLL c0 output).  
> The original Apple-1 ran at 1 MHz.

---

## Tested Configuration

| Parameter    | Value             |
|-------------|-------------------|
| Board        | MAX1000 TEI0001-04 |
| FPGA         | MAX10 10M08        |
| SDRAM        | W9825G6KB-6        |
| CPU speed    | 10 MHz             |
| SDRAM clock  | 120 MHz            |
| ROM          | BASIC65            |
| RAM          | 48 KB              |
| Baud rate    | 115200             |

---

## Other Tested Boards

This SDRAM controller has been validated on the following boards with no code changes — only the configuration constants differ:

| Board    | FPGA                  | SDRAM chip        |
|---------|-----------------------|-------------------|
| DE10-Lite | Intel MAX10 10M50   | ISSI IS42S16320F  |
| DE1-SoC  | Intel Cyclone V 5CSEMA | ISSI IS42S16320F |
| AX4010   | Xilinx Artix-7 XC7A35T | Hynix H57V2562GTR |
| MAX1000  | Intel MAX10 10M08    | Winbond W9825G6KB |

---

## License

Copyright (c) 2026 Didier Derny  
Licensed under Creative Commons Attribution-NonCommercial-ShareAlike 4.0  
https://creativecommons.org/licenses/by-nc-sa/4.0/