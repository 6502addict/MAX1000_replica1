--------------------------------------------------------------------------------
-- Replica1 for MAX1000
-- Copyright (c) 2026 Didier Derny
--
-- This work is licensed under the Creative Commons
-- Attribution-NonCommercial-ShareAlike 4.0 International License.
-- Full license: https://creativecommons.org/licenses/by-nc-sa/4.0/
--------------------------------------------------------------------------------
-- Board: Arrow/Trenz MAX1000 IoT Maker Board (TEI0001-04-FBC84A)
-- Size:  6.15 x 2.5 cm
--
-- FPGA:  Intel MAX10 10M08SAU169C8G
--          8,000 Logic Elements
--          378 Kbits M9K Block RAM
--          4 PLLs
--          On-board Arrow USB programmer
--
-- SDRAM: Winbond W9825G6KB-6
--          256 Mbit (32 MByte), 4M x 4 Banks x 16 bits
--          Package: 54-TFBGA (8x8 mm BGA)
--          Max clock: 133 MHz, CAS Latency 2 or 3
--          ROW_BITS=13, COL_BITS=9
--
-- FLASH: 8 MByte QSPI (bitstream storage)
--------------------------------------------------------------------------------
-- System Overview
--------------------------------------------------------------------------------
-- This is a cut-down Replica1 Apple-1 recreation running entirely from SDRAM.
-- Only the essential hardware is implemented:
--
--   CPU:  MX65 (6502 core), running at 1 to 15 MHz (configurable)
--
--   ROM:  Two options selectable via the ROM constant:
--           "WOZMON65" - Wozniak monitor only (bare minimum)
--           "BASIC65"  - Wozniak monitor + reduced Applesoft BASIC
--
--   PIA:  Console PIA - routed to the on-board UART via BDBUS
--           BDBUS(0) = TX (to terminal)
--           BDBUS(1) = RX (from terminal)
--
--   ACI:  Tape interface - routed to PMOD connector
--           PIO(0) = tape_out (audio out to cassette)
--           PIO(1) = tape_in  (audio in from cassette)
--
-- All RAM is provided by the SDRAM controller via the sram_sdram_bridge.
-- No internal Block RAM is used for program memory.
--------------------------------------------------------------------------------
-- Clock Architecture
--------------------------------------------------------------------------------
-- Input:  12 MHz crystal (CLK12M)
-- PLL (main_clock) generates three clocks:
--
--   c0 = main_clk   : 4x CPU clock (4 to 60 MHz for 1 to 15 MHz CPU speed)
--                     The Replica1 core divides this by 4 internally,
--                     so set the PLL c0 output to 4 x desired CPU speed.
--                     Example: 40 MHz c0 → 10 MHz effective CPU clock.
--
--   c1 = serial_clk : 1.8432 MHz - standard baud rate generator frequency
--                     Produces exact baud rates: 1200 to 115200 bps
--
--   c2 = sdram_clk  : 120 MHz - SDRAM controller clock
--                     Must match the SDRAM_MHZ constant below.
--                     Max safe value for W9825G6KB-6: 133 MHz.
--
-- cpu_reset_n is held low until both reset_n is asserted AND the PLL is locked.
-- This ensures the CPU never starts with an unstable clock.
--------------------------------------------------------------------------------
-- Configuration Guide  (search "Board Configuration Parameters")
--------------------------------------------------------------------------------
-- To reconfigure the machine, locate the constant block below and change:
--
--   ROM          : "WOZMON65" = monitor only
--                  "BASIC65"  = monitor + Applesoft BASIC
--
--   RAM_SIZE_KB  : Amount of RAM visible to the 6502 (8 to 48 KB)
--                  Limited by the 6502 memory map, not the SDRAM size.
--
--   BAUD_RATE    : Serial port speed (1200 to 115200 bps)
--                  Must match your terminal settings.
--
--   SDRAM_MHZ    : SDRAM clock frequency in MHz.
--                  Must match the PLL c2 output. Max 133 for W9825G6KB-6.
--
--   ROW_BITS     : 13 for W9825G6KB-6 (8192 rows)
--   COL_BITS     :  9 for W9825G6KB-6 (512 columns)
--
--   TRP_NS       : Precharge time in ns  (15 ns for W9825G6KB-6)
--   TRCD_NS      : RAS-to-CAS delay in ns (15 ns for W9825G6KB-6)
--   TRFC_NS      : Refresh cycle time in ns (60 ns for W9825G6KB-6)
--
--   CAS_LATENCY  : 2 (safe up to 133 MHz for W9825G6KB-6)
--
--   AUTO_PRECHARGE : false = row stays open between accesses (faster)
--                    true  = row closes after each access (simpler)
--
--   AUTO_REFRESH   : false = bridge generates refresh requests
--                    true  = controller generates refresh internally
--------------------------------------------------------------------------------

library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;

entity MAX1000_Replica1 is
    port(
        -- Clock and Reset
        CLK12M      : in    std_logic;  -- 12 MHz input clock
        RESET       : in    std_logic;  -- Active low reset
        USER_BTN    : in    std_logic;  -- User button

        -- LEDs for status
        LED         : out   std_logic_vector(7 downto 0);

        -- Accelerometer (SPI interface)
        SEN_INT1    : in    std_logic;
        SEN_INT2    : in    std_logic;
        SEN_SDI     : out   std_logic;  -- MOSI (Master Out Slave In)
        SEN_SDO     : in    std_logic;  -- MISO (Master In Slave Out)
        SEN_SPC     : out   std_logic;  -- SPI Clock
        SEN_CS      : out   std_logic;  -- Chip Select

        -- PMOD connector
        -- PIO(0) = tape_out (ACI audio output to cassette)
        -- PIO(1) = tape_in  (ACI audio input from cassette)
        PIO         : inout std_logic_vector(7 downto 0);

        -- UART (via Arrow on-board USB programmer)
        -- BDBUS(0) = TX  (to terminal)
        -- BDBUS(1) = RX  (from terminal)
        BDBUS       : inout std_logic_vector(5 downto 0);

        -- FLASH (SPI) - 8 MByte QSPI
        F_S         : out   std_logic;  -- Chip Select
        F_CLK       : out   std_logic;  -- SPI Clock
        F_DI        : out   std_logic;  -- MOSI (to flash)
        F_DO        : in    std_logic;  -- MISO (from flash)

        -- Arduino headers (general purpose I/O expansion)
        D           : inout std_logic_vector(14 downto 0);
        AIN         : in    std_logic_vector(6 downto 0);

        -- SDRAM Interface - Winbond W9825G6KB-6
        DQ          : inout std_logic_vector(15 downto 0);  -- 16-bit data bus
        DQM         : out   std_logic_vector(1  downto 0);  -- Byte mask (LDQM/UDQM)
        A           : out   std_logic_vector(13 downto 0);  -- Multiplexed row/col address
        BA          : out   std_logic_vector(1  downto 0);  -- Bank select
        CLK         : out   std_logic;                      -- SDRAM clock
        CKE         : out   std_logic;                      -- Clock enable
        RAS         : out   std_logic;                      -- Row address strobe (active low)
        WE          : out   std_logic;                      -- Write enable (active low)
        CS          : out   std_logic;                      -- Chip select (active low)
        CAS         : out   std_logic                       -- Column address strobe (active low)
    );
end MAX1000_Replica1;

architecture rtl of MAX1000_Replica1 is

-- PLL: generates main_clk (4x CPU), serial_clk (1.8432 MHz), sdram_clk (120 MHz)
component main_clock is
    port (
        areset  : in  std_logic := '0';
        inclk0  : in  std_logic := '0';
        c0      : out std_logic;  -- 4x CPU clock  (4 to 60 MHz)
        c1      : out std_logic;  -- Serial clock  (1.8432 MHz)
        c2      : out std_logic;  -- SDRAM clock   (120 MHz)
        locked  : out std_logic
    );
end component;

-- Replica1 core: MX65 CPU + console PIA + ACI tape interface
component Replica1_CORE is
    generic (
        ROM         : string   := "WOZMON65";
        RAM_SIZE_KB : positive := 8;
        BAUD_RATE   : integer  := 9600
    );
    port (
        main_clk    : in  std_logic;
        serial_clk  : in  std_logic;
        reset_n     : in  std_logic;
        cpu_reset_n : in  std_logic;
        bus_phi2    : out std_logic;
        bus_address : out std_logic_vector(15 downto 0);
        bus_data    : out std_logic_vector(7  downto 0);
        bus_rw      : out std_logic;
        bus_mrdy    : in  std_logic;
        ext_ram_cs_n: out std_logic;
        ext_ram_data: in  std_logic_vector(7  downto 0);
        uart_rx     : in  std_logic;
        uart_tx     : out std_logic;
        tape_out    : out std_logic;
        tape_in     : in  std_logic
    );
end component;

-- SDRAM controller: handles init, refresh, read/write for W9825G6KB-6
component sdram_controller is
    generic (
        FREQ_MHZ           : integer := 100;
        ROW_BITS           : integer := 13;
        COL_BITS           : integer := 10;
        TRP_NS             : integer := 20;
        TRCD_NS            : integer := 20;
        TRFC_NS            : integer := 70;
        CAS_LATENCY        : integer := 2;
        USE_AUTO_PRECHARGE : boolean := true;
        USE_AUTO_REFRESH   : boolean := true
    );
    port(
        clk            : in    std_logic;
        reset_n        : in    std_logic;
        req            : in    std_logic;
        wr_n           : in    std_logic;
        addr           : in    std_logic_vector(ROW_BITS+COL_BITS+1 downto 0);
        din            : in    std_logic_vector(15 downto 0);
        dout           : out   std_logic_vector(15 downto 0);
        byte_en        : in    std_logic_vector(1 downto 0);
        ready          : out   std_logic;
        ack            : out   std_logic;
        refresh_req    : in    std_logic;
        refresh_active : out   std_logic;
        sdram_clk      : out   std_logic;
        sdram_cke      : out   std_logic;
        sdram_cs_n     : out   std_logic;
        sdram_ras_n    : out   std_logic;
        sdram_cas_n    : out   std_logic;
        sdram_we_n     : out   std_logic;
        sdram_ba       : out   std_logic_vector(1 downto 0);
        sdram_addr     : out   std_logic_vector(ROW_BITS - 1 downto 0);
        sdram_dq       : inout std_logic_vector(15 downto 0);
        sdram_dqm      : out   std_logic_vector(1 downto 0)
    );
end component;

-- Bridge: translates 8-bit synchronous SRAM-like bus to 16-bit SDRAM controller
-- Handles clock stretching (mrdy) and optional refresh request generation
component sram_sdram_bridge is
    generic (
        ADDR_BITS        : integer := 24;
        SDRAM_MHZ        : integer := 75;
        GENERATE_REFRESH : boolean := true
    );
    port (
        sdram_clk    : in  std_logic;
        E            : in  std_logic;
        reset_n      : in  std_logic;
        sram_ce_n    : in  std_logic;
        sram_we_n    : in  std_logic;
        sram_oe_n    : in  std_logic;
        sram_addr    : in  std_logic_vector(ADDR_BITS-1 downto 0);
        sram_din     : in  std_logic_vector(7 downto 0);
        sram_dout    : out std_logic_vector(7 downto 0);
        mrdy         : out std_logic;
        sdram_req    : out std_logic;
        sdram_wr_n   : out std_logic;
        sdram_addr   : out std_logic_vector(ADDR_BITS-2 downto 0);
        sdram_din    : out std_logic_vector(15 downto 0);
        sdram_dout   : in  std_logic_vector(15 downto 0);
        sdram_byte_en: out std_logic_vector(1 downto 0);
        sdram_ready  : in  std_logic;
        sdram_ack    : in  std_logic;
        refresh_req  : out std_logic
    );
end component;

--------------------------------------------------------------------------
-- Board Configuration Parameters
-- Edit this section to reconfigure the machine (see header for details)
--------------------------------------------------------------------------
constant ROM              : string   := "BASIC65";   -- "WOZMON65" or "BASIC65"
constant RAM_SIZE_KB      : positive := 48;           -- RAM visible to 6502 (8 to 48 KB)
constant BAUD_RATE        : integer  := 115200;       -- Serial speed (match your terminal)

-- SDRAM / clock settings - must be consistent with PLL c2 output
constant SDRAM_MHZ        : integer  := 120;          -- SDRAM clock (max 133 for W9825G6KB-6)
constant ROW_BITS         : integer  := 13;           -- W9825G6KB-6: 8192 rows
constant COL_BITS         : integer  := 9;            -- W9825G6KB-6: 512 columns
constant TRP_NS           : integer  := 15;           -- Precharge time (ns)
constant TRCD_NS          : integer  := 15;           -- RAS-to-CAS delay (ns)
constant TRFC_NS          : integer  := 60;           -- Refresh cycle time (ns)
constant CAS_LATENCY      : integer  := 2;            -- CAS latency (2 safe at 120 MHz)

-- Access mode
constant AUTO_PRECHARGE   : boolean  := false;        -- false = row stays open (faster)
constant AUTO_REFRESH     : boolean  := false;        -- false = bridge generates refresh

-- Derived constants (do not edit)
constant ADDR_BITS        : integer  := 16;
constant SDRAM_ADDR_WIDTH : integer  := ROW_BITS + COL_BITS + 2;

--------------------------------------------------------------------------
-- Internal signals
--------------------------------------------------------------------------
signal address_bus   : std_logic_vector(15 downto 0);
signal data_bus      : std_logic_vector(7  downto 0);
signal ram_data      : std_logic_vector(7  downto 0);
signal ram_cs_n      : std_logic;
signal reset_n       : std_logic;
signal cpu_reset_n   : std_logic;
signal main_clk      : std_logic;
signal sdram_clk     : std_logic;
signal serial_clk    : std_logic;
signal main_locked   : std_logic;
signal phi2          : std_logic;
signal rw            : std_logic;
signal mrdy          : std_logic;

-- SDRAM controller <-> bridge interface
signal sdram_req     : std_logic;
signal sdram_wr_n    : std_logic;
signal sdram_addr    : std_logic_vector(ADDR_BITS - 2 downto 0);
signal sdram_din     : std_logic_vector(15 downto 0);
signal sdram_dout    : std_logic_vector(15 downto 0);
signal sdram_byte_en : std_logic_vector(1 downto 0);
signal sdram_ready   : std_logic;
signal sdram_ack     : std_logic;
signal refresh_busy  : std_logic;
signal refresh_req   : std_logic;

begin

    reset_n <= RESET;

    -- CPU reset: held low until system reset released AND PLL locked
    cpu_reset_n <= '1' when reset_n = '1' and main_locked = '1' else '0';

    -- ACI tape interface routed to PMOD connector
    -- PIO(0) = tape_out, PIO(1) = tape_in

    -- PLL: 12 MHz → main_clk (4x CPU), serial_clk (1.8432 MHz), sdram_clk (120 MHz)
    mclk : main_clock
        port map(areset => not reset_n,
                 inclk0 => CLK12M,
                 c0     => main_clk,
                 c1     => serial_clk,
                 c2     => sdram_clk,
                 locked => main_locked);

    -- Replica1 core: MX65 + console PIA (UART) + ACI (tape on PIO 0/1)
    ap1 : Replica1_CORE
        generic map(ROM         => ROM,
                    RAM_SIZE_KB => RAM_SIZE_KB,
                    BAUD_RATE   => BAUD_RATE)
        port map(main_clk    => main_clk,
                 serial_clk  => serial_clk,
                 reset_n     => reset_n,
                 cpu_reset_n => cpu_reset_n,
                 bus_phi2    => phi2,
                 bus_address => address_bus,
                 bus_data    => data_bus,
                 bus_rw      => rw,
                 bus_mrdy    => mrdy,
                 ext_ram_cs_n=> ram_cs_n,
                 ext_ram_data=> ram_data,
                 uart_rx     => BDBUS(0),
                 uart_tx     => BDBUS(1),
                 tape_out    => PIO(0),
                 tape_in     => PIO(1));

    -- Bridge: 8-bit SRAM bus → 16-bit SDRAM controller
    -- GENERATE_REFRESH = true when AUTO_REFRESH = false (bridge owns refresh)
    bridge_inst : sram_sdram_bridge
        generic map(ADDR_BITS        => ADDR_BITS,
                    SDRAM_MHZ        => SDRAM_MHZ,
                    GENERATE_REFRESH => not AUTO_REFRESH)
        port map(sdram_clk    => sdram_clk,
                 E            => phi2,
                 reset_n      => reset_n,
                 sram_ce_n    => ram_cs_n,
                 sram_we_n    => rw,
                 sram_oe_n    => not rw,
                 sram_addr    => address_bus(ADDR_BITS - 1 downto 0),
                 sram_din     => data_bus,
                 sram_dout    => ram_data,
                 mrdy         => mrdy,
                 sdram_req    => sdram_req,
                 sdram_wr_n   => sdram_wr_n,
                 sdram_addr   => sdram_addr,
                 sdram_din    => sdram_din,
                 sdram_dout   => sdram_dout,
                 sdram_byte_en=> sdram_byte_en,
                 sdram_ready  => sdram_ready,
                 sdram_ack    => sdram_ack,
                 refresh_req  => refresh_req);

    -- SDRAM controller: W9825G6KB-6, 32MB, ROW=13, COL=9, 120 MHz
    sdram_inst : sdram_controller
        generic map(FREQ_MHZ           => SDRAM_MHZ,
                    ROW_BITS           => ROW_BITS,
                    COL_BITS           => COL_BITS,
                    TRP_NS             => TRP_NS,
                    TRCD_NS            => TRCD_NS,
                    TRFC_NS            => TRFC_NS,
                    CAS_LATENCY        => CAS_LATENCY,
                    USE_AUTO_PRECHARGE => AUTO_PRECHARGE,
                    USE_AUTO_REFRESH   => AUTO_REFRESH)
        port map(clk            => sdram_clk,
                 reset_n        => reset_n,
                 req            => sdram_req,
                 wr_n           => sdram_wr_n,
                 addr           => std_logic_vector(resize(unsigned(sdram_addr), SDRAM_ADDR_WIDTH)),
                 din            => sdram_din,
                 dout           => sdram_dout,
                 byte_en        => sdram_byte_en,
                 ready          => sdram_ready,
                 ack            => sdram_ack,
                 refresh_req    => refresh_req,
                 refresh_active => refresh_busy,
                 sdram_clk      => CLK,
                 sdram_cke      => CKE,
                 sdram_cs_n     => CS,
                 sdram_ras_n    => RAS,
                 sdram_cas_n    => CAS,
                 sdram_we_n     => WE,
                 sdram_ba       => BA,
                 sdram_addr     => A(12 downto 0),
                 sdram_dq       => DQ,
                 sdram_dqm(1)   => DQM(1),
                 sdram_dqm(0)   => DQM(0));

end rtl;
