library IEEE;
	use IEEE.std_logic_1164.all;
   use ieee.numeric_std.all; 
	
entity Replica1_CORE is
  generic (
		ROM             : string  :=  "WOZMON65";    -- default wozmon65
		RAM_SIZE_KB     : integer :=  8;             -- 8 to 48kb
	    BAUD_RATE       : integer :=  115200         -- uart speed 1200 to 115200
  );
  port (
		main_clk        : in     std_logic;
		serial_clk      : in     std_logic;
		reset_n         : in     std_logic;
		cpu_reset_n     : in     std_logic;
		bus_phi2        : out    std_logic;
		bus_address     : out    std_logic_vector(15 downto 0);
		bus_data        : out    std_logic_vector(7  downto 0);
		bus_rw          : out    std_logic;
		bus_mrdy        : in     std_logic;
		ext_ram_cs_n    : out    std_logic;		
		ext_ram_data    : in     std_logic_vector(7  downto 0);
		uart_rx         : in     std_logic;
		uart_tx         : out    std_logic;
		tape_out        : out    std_logic;
		tape_in         : in     std_logic
  );
end entity;	

architecture rtl of Replica1_CORE is


-- PROCESSOR MODULES


component CPU_MX65 is
	port (
		-- Clock and Reset
		main_clk     : in  std_logic;        -- Main system clock
		reset_n      : in  std_logic;        -- Active low reset
		cpu_reset_n  : in  std_logic;        -- Active low reset
		phi2         : out std_logic;        -- Phase 2 clock enable
		
		-- CPU Control Interface
		rw           : out std_logic;        -- Read/Write (1=Read, 0=Write)
		vma          : out std_logic;        -- Valid Memory Access
		sync         : out std_logic;        -- Instruction fetch cycle
		
		-- Address and Data Bus
		addr         : out std_logic_vector(15 downto 0);  -- Address bus
		data_in      : in  std_logic_vector(7 downto 0);   -- Data input
		data_out     : out std_logic_vector(7 downto 0);   -- Data output
		
		-- Interrupt Interface  
		nmi_n        : in  std_logic;        -- Non-maskable interrupt (active low)
		irq_n        : in  std_logic;        -- Interrupt request (active low)
		so_n         : in  std_logic := '1';  -- Set overflow (active low)
		
		mrdy         : in  std_logic
	);
end component;


-- END OF PROCESSOR MODULES

-- ROM MODULES
	
component WOZMON65 
	port (
		clock    : in std_logic;
		cs_n     : in std_logic;
		address  : in  std_logic_vector(7 downto 0); 
		data_out : out std_logic_vector(7 downto 0)
	);
end component;

component BASIC
	port (
		clock    : in std_logic;
		cs_n     : in std_logic;
		address  : in  std_logic_vector(13 downto 0); 
		data_out : out std_logic_vector(7 downto 0)
	);
end component;

component INTBASIC
	port (
		clock    : in std_logic;
		cs_n     : in std_logic;
		address  : in  std_logic_vector(13 downto 0); 
		data_out : out std_logic_vector(7 downto 0)
	);
end component;


-- PERIPHERAL COMPONENTS

component ACI is
    port (
 	    reset_n   : in  std_logic;                           -- reset
        phi2      : in  std_logic;                           -- clock named phi2 on the 6502
        cs_n      : in  std_logic;                           -- CXXX chip select²
        address   : in  std_logic_vector(15 downto 0);       -- addresses
        data_out  : out std_logic_vector(7 downto 0);        -- data output
		tape_in   : in  std_logic;                           -- tape input
		tape_out  : out std_logic                            -- tape output
    );
end component;

component PIA_UART is
  generic (
     CLK_FREQ_HZ     : positive := 50000000;  
     BAUD_RATE       : positive := 9600;      
     BITS            : positive := 8          
  );
  port (
    -- System interface
    clock       : in  std_logic;    -- CPU clock
    serial_clk  : in  std_logic;    -- Serial clock
    reset_n     : in  std_logic;    -- Active low reset
    
    -- CPU interface
    cs_n        : in  std_logic;                     -- Chip select
    rw          : in  std_logic;                     -- Read/Write: 1=read, 0=write
    address     : in  std_logic_vector(1 downto 0);  -- Register select (for 4 registers)
    data_in     : in  std_logic_vector(7 downto 0);  -- Data from CPU
    data_out    : out std_logic_vector(7 downto 0);  -- Data to CPU
    
    -- Physical UART interface
    rx          : in  std_logic;    -- Serial input
    tx          : out std_logic     -- Serial output
  );
end component;


	attribute keep : string;

	constant RAM_LIMIT  : integer := RAM_SIZE_KB * 1024;

	signal data_bus	    : std_logic_vector(7 downto 0);
	signal address_bus  : std_logic_vector(15 downto 0);
	signal cpu_data	    : std_logic_vector(7 downto 0);
	signal pia_data	    : std_logic_vector(7 downto 0);
	signal rom_data	    : std_logic_vector(7 downto 0);
	signal ram_data	    : std_logic_vector(7 downto 0);
	signal aci_data	    : std_logic_vector(7 downto 0);
	signal ram_addr     : std_logic_vector(18 downto 0);
	signal rw			: std_logic;
	signal vma  		: std_logic;
	signal nmi_n        : std_logic := '1';
	signal irq_n        : std_logic := '1';
	signal so_n         : std_logic := '1';
	signal ram_cs_n     : std_logic;
	signal rom_cs_n     : std_logic;
	signal aci_cs_n     : std_logic;
	signal pia_cs_n     : std_logic;
	signal phi2         : std_logic;
	signal sync         : std_logic;
	signal aci_in       : std_logic;
	signal aci_out      : std_logic;
	signal mrdy         : std_logic;
	
	attribute keep of nmi_n    : signal is "true";
	attribute keep of irq_n    : signal is "true";
	attribute keep of sync     : signal is "true";
	attribute keep of so_n     : signal is "true";
	
begin

	bus_address    <= address_bus;
	bus_data       <= data_bus;
	bus_phi2       <= phi2;
	bus_rw         <= rw;
	mrdy           <= bus_mrdy;
	ext_ram_cs_n   <= ram_cs_n;
	ram_data       <= ext_ram_data;
						

-- CPU PORT MAP
	cpu: CPU_MX65   port map(main_clk        => main_clk,
	                         reset_n         => reset_n,
	                         cpu_reset_n     => cpu_reset_n,
									 phi2            => phi2,
									 rw              => rw,
									 vma             => vma,
									 sync            => sync,
									 addr            => address_bus,
									 data_in         => data_bus,
									 data_out        => cpu_data,
									 nmi_n           => nmi_n,
									 irq_n           => irq_n,
									 so_n            => so_n,
									 mrdy            => mrdy);
-- END OF CPU PORT MAP

-- ROM PORT MAP
											  

woz65: if ROM = "WOZMON65"  generate
	rom: WOZMON65    port map(clock           => phi2,
							        cs_n            => rom_cs_n,
	                          address         => address_bus(7 downto 0),
							        data_out        => rom_data);
end generate woz65;

basic1: if ROM = "BASIC65"  generate
	rom: BASIC     port map(clock           => phi2,
						           cs_n            => rom_cs_n,
	                          address         => address_bus(13 downto 0),
							        data_out        => rom_data);
end generate basic1;

basic2: if ROM = "INTBASIC"  generate
	rom: INTBASIC   port map(clock           => phi2,
							       cs_n            => rom_cs_n,
	                         address         => address_bus(13 downto 0),
							       data_out        => rom_data);
end generate basic2;


-- END ROM PORT MAP
											  
	tape: ACI       port map(reset_n         => cpu_reset_n,
	                         phi2            => phi2,
	                         cs_n            => aci_cs_n,
									 address         => address_bus,
									 data_out        => aci_data,
									 tape_in         => aci_in,
									 tape_out        => aci_out);
										 
	pia: PIA_UART generic map(CLK_FREQ_HZ     => 1843200, 
								 	  BAUD_RATE       => BAUD_RATE,
									  BITS            => 8)
				        port map(clock           => phi2,
 							        serial_clk      => serial_clk,
								 	  reset_n         => cpu_reset_n,
									  cs_n            => pia_cs_n,
									  rw              => rw,
									  address         => address_bus(1 downto 0),
									  data_in         => data_bus,
									  data_out        => pia_data,
								     rx              => uart_rx,
								     tx              => uart_tx);
	
											
   aci_cs_n     <= '0' when vma = '1' and address_bus(15 downto 9)   = x"C" & "000"  else '1';   -- IF WOZACI
   pia_cs_n     <= '0' when vma = '1' and address_bus(15 downto 4)   = x"D01"        else '1';   -- REPLICA CONSOLE PIA
	
	data_bus <= cpu_data  when rw          = '0' else
		         rom_data  when rom_cs_n    = '0' else 
		         aci_data  when aci_cs_n    = '0' else 
		         ram_data  when ram_cs_n    = '0' else 
			      pia_data  when pia_cs_n    = '0' else
		         address_bus(15 downto 8);     

	
	process(vma, address_bus)
	begin
		 rom_cs_n <= '1';  -- Default inactive
		 
		 if vma = '1' then
			if ROM = "WOZMON65" then
				if address_bus(15 downto 8) = x"FF" then
					rom_cs_n <= '0';
				end if;
			elsif ROM = "BASIC65" then
				if address_bus(15 downto 13) = "111" then
					rom_cs_n <= '0';
				end if;
			elsif ROM = "INTBASIC" then
				if address_bus(15 downto 13) = "111" then
					rom_cs_n <= '0';
				end if;
			else
				rom_cs_n <= '1';  
			end if;
		end if;
	end process;	
	
	-- Generalized bit-pattern based chip select
	process(vma, address_bus)
	begin
		 ram_cs_n <= '1';  -- Default inactive
		 
		 if vma = '1' then
			  case RAM_SIZE_KB is
					when 8 =>
						 if address_bus(15 downto 13) = "000" then
							  ram_cs_n <= '0';
						 end if;
						 
					when 16 =>
						 if address_bus(15 downto 14) = "00" then
							  ram_cs_n <= '0';
						 end if;
						 
					when 24 =>
						 if (address_bus(15 downto 14) = "00") or 
							 (address_bus(15 downto 14) = "01" and address_bus(13) = '0') then
							  ram_cs_n <= '0';
						 end if;
						 
					when 32 =>
						 if address_bus(15) = '0' then
							  ram_cs_n <= '0';
						 end if;
						 
					when 40 =>
						 if (address_bus(15 downto 14) /= "11") and 
							 not (address_bus(15 downto 14) = "10" and address_bus(13) = '1') then
							  ram_cs_n <= '0';
						 end if;
						 
					when 48 =>
						 if address_bus(15 downto 14) /= "11" then
							  ram_cs_n <= '0';
						 end if;
						 
					when others =>
						 ram_cs_n <= '1';  -- Invalid size
			  end case;
		 end if;
	end process;	
	
end rtl;

