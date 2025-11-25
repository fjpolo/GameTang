// Copyright (c) 2025-3025 @fjpolo
// This program is GPL Licensed. See COPYING for the full license.

// `default_nettype none

module GAMETANK(
    input              i_clk_acp,        // ~14.32 MHz, from PLL in top.v (for PPU/ACP)
    input              i_clk_cpu,        // ~3.58 MHz, from PLL in top.v (for CPU)
    input              i_reset_gametank, // System Reset (Active High)
    input              i_cold_reset,
    input  [1:0]       i_sys_type,
    output [2:0]       o_gametank_div,
    input  [63:0]      i_mapper_flags,
    output [15:0]      o_sample,         // sample generated from APU
    output [5:0]       o_color,          // pixel generated from PPU
    output [2:0]       o_joypad_out,     // Set to 1 to strobe joypads. Then set to zero to keep the value (bit0)
    output [1:0]       o_joypad_clock,   // Set to 1 for each joypad to clock it.
    input  [4:0]       i_joypad1_data,   // Port1
    input  [4:0]       i_joypad2_data,   // Port2
    input              i_fds_busy,       // FDS Disk Swap Busy
    input              i_fds_eject,      // FDS Disk Swap Pause
    output [1:0]       o_diskside_req,
    input  [1:0]       i_diskside,
    input  [4:0]       i_audio_channels, // Enabled audio channels

    // Access signals for the SDRAM.
    output [21:0] o_cpumem_addr,
    output             o_cpumem_read,
    output             o_cpumem_write,
    output [7:0]       o_cpumem_dout,
    input  [7:0]       i_cpumem_din,
    output [21:0] o_ppumem_addr,
    output             o_ppumem_read,
    output             o_ppumem_write,
    output [7:0]       o_ppumem_dout,
    input  [7:0]       i_ppumem_din,

    // Override for BRAM
    output [17:0] o_bram_addr,    // address to access
    input  [7:0]       i_bram_din,     // Data from BRAM
    output [7:0] o_bram_dout,
    output             o_bram_write,   // is a write operation
    output             o_bram_override,

    // PPU Control Ports
    output [7:0]  o_ppu_control,           // PPUCTRL Register Output ($2000)
    output [7:0]  o_ppu_mask,              // PPUMASK Register Output ($2001)
    output [7:0]  o_ppu_scroll,            // PPU Scroll (PPUSCROLL) Register Output ($2005) (Combined X/Y)
    output [15:0] o_ppu_addr,              // PPU Address (PPUADDR) Register Output ($2006)
    output [7:0]  o_ppu_data_write_out,    // Data written to PPUDATA ($2007)
    output        o_ppu_data_write_enable, // Write Enable signal for PPUDATA ($2007)

    output [8:0]  o_cycle/* verilator public */,
    output [8:0]  o_scanline/* verilator public */,
    input  [31:0]  i_dbgadr,            // ADDED: Debug Address for OSD
    input  [1:0]   i_dbgctr,            // ADDED: Debug Control for OSD
    input          i_int_audio,
    input          i_ext_audio,
    output         o_apu_ce,
    input          i_gg,
    input  [128:0] i_gg_code,
    output         o_gg_avail,
    input          i_gg_reset,
    output [2:0]   o_emphasis,
    output         o_save_written
) /*synthesis syn_keep = 1*/;

// --- Internal Wires and Registers for CPU and Bus Arbitration ---
wire [15:0] cpu_addr/*synthesis syn_keep = 1*/;      // CPU Address Bus (A0-A15)
wire cpu_rnw/*synthesis syn_keep = 1*/;              // CPU Read/Write (1=Read, 0=Write)

// Wires for the M65C02A CPU core interface
wire w_nVP, w_Sync, w_nML/*synthesis syn_keep = 1*/;
wire w_nRD, w_nWR/*synthesis syn_keep = 1*/;
wire [3:0] w_nCE_cpu/*synthesis syn_keep = 1*/;
wire [3:0] w_XA/*synthesis syn_keep = 1*/;
wire [1:0] w_nSSel/*synthesis syn_keep = 1*/;
wire w_SCK, w_MOSI/*synthesis syn_keep = 1*/;

wire pause_cpu/*synthesis syn_keep = 1*/;             // Pause signal (for DMA or memory contention)
wire mapper_irq/*synthesis syn_keep = 1*/;            // IRQ from Mapper/Cartridge
wire [7:0] cpu_dout/*synthesis syn_keep = 1*/;      // Data written by CPU (Data Out)
wire [7:0] cpu_data_in/*synthesis syn_keep = 1*/;    // Data read by CPU (Data In, multiplexed)

// Data bus wire for the tri-state connection to the M65C02A core
// FIX: Changed from 'wire' to 'tri' to correctly model the shared, tri-state data bus, 
// resolving the 'multiple drivers' error.
tri [7:0] w_db_bus/*synthesis syn_keep = 1*/; // Data Bus (Connects to internal tri-state net)

// Reset signal for the main CPU (Active High)
wire reset = i_reset_gametank/*synthesis syn_keep = 1*/;

// --- Interrupt Wires (Active High, driven by peripherals/placeholders) ---
wire nmi = 1'b0/*synthesis syn_keep = 1*/;             // Placeholder for PPU NMI (Active High)
wire apu_irq = 1'b0/*synthesis syn_keep = 1*/;         // Placeholder for APU IRQ (Active High)

// Active Low signals derived for the CPU Core
wire w_cpu_nmi_n = ~nmi/*synthesis syn_keep = 1*/;
wire w_cpu_irq_n = ~(apu_irq | mapper_irq)/*synthesis syn_keep = 1*/;

// --- BUS CONTROL UNIT (BCU) Signals (Chip Enables) ---
wire gppram_ce/*synthesis syn_keep = 1*/;
wire acp_ce/*synthesis syn_keep = 1*/;
wire ppu_ce/*synthesis syn_keep = 1*/;
wire io_ce/*synthesis syn_keep = 1*/;
wire sdram_ce/*synthesis syn_keep = 1*/;
wire cart_ce/*synthesis syn_keep = 1*/;

// Peripheral Read Data Inputs to BCU
wire [7:0] gppram_data_out/*synthesis syn_keep = 1*/;
wire [7:0] acp_data_out/*synthesis syn_keep = 1*/;    // <--- ACP READ DATA
wire [7:0] ppu_data_out/*synthesis syn_keep = 1*/;    // <--- PPU READ DATA
wire [7:0] io_data_out/*synthesis syn_keep = 1*/;
wire [7:0] sdram_data_out/*synthesis syn_keep = 1*/;
wire [7:0] cart_data_out/*synthesis syn_keep = 1*/;

// New wire to capture the data read specifically from the BSROM mapper
wire [7:0] bsrom_data_out/*synthesis syn_keep = 1*/;

// --- PPU MMIO Internal Registers ($2000-$2007) ---
// Registers that store the CPU-written values
reg [7:0] ppu_control_reg;      // $2000 PPUCTRL
reg [7:0] ppu_mask_reg;         // $2001 PPUMASK
reg [7:0] ppu_oam_addr_reg;     // $2003 OAMADDR

// $2005 PPUSCROLL and $2006 PPUADDR are dual-write registers.
reg ppu_addr_scroll_toggle = 1'b0; // Toggle state (0=first write, 1=second write)

reg [7:0] ppu_scroll_x_reg;      // X scroll value (first write to $2005)
reg [7:0] ppu_scroll_y_reg;      // Y scroll value (second write to $2005)

reg [15:0] ppu_addr_reg_internal; // The full 16-bit VRAM address (updated via $2006)
reg [7:0] ppu_data_write_out_reg; // Data to be written to VRAM on $2007 write
reg ppu_write_enable_reg;         // Strobe for $2007 write

// Status register (Read-only for CPU, written by PPU core)
reg [7:0] ppu_status_reg = 8'h00; // $2002 PPUSTATUS (Must be driven by PPU core logic later)

// ADDED: PPU Read Data Buffer for $2007 access (delayed read)
reg [7:0] ppu_read_buffer = 8'h00;

// ************************************************************
// ** 1. Clock and Utility Outputs **
// ************************************************************
// Provides clock and debug cycle outputs
assign o_gametank_div = {i_clk_cpu, 1'b0, 1'b0};

// --- Tri-state Bus Interface Logic for M65C02A ---

// Derive the Read/nWrite signal from the core's nWR strobe (Active Low Write)
// cpu_rnw=1 for Read, cpu_rnw=0 for Write.
assign cpu_rnw = w_nWR;

// When the core is reading (cpu_rnw=1), the BCU/peripheral drives cpu_data_in, 
// which is then driven onto the core's internal bus (w_db_bus).
// We assume the M65C02A's DB port is high-impedance when reading.
// assign w_db_bus = cpu_rnw ? cpu_data_in : 8'bz; // <--- LINE 152: Peripheral driver

// When the core is writing (cpu_rnw=0), the core drives w_db_bus.
// This data is then read by the BCU as cpu_dout.
assign cpu_dout = w_db_bus;

// pause_cpu needs to be driven by OAM DMA and SDRAM wait states. Tied low for simulation only.
assign pause_cpu = 1'b0;


// ************************************************************
// ** 2. M65C02A CPU Core Instantiation **
// ************************************************************
`define FULL_WDC65C02A
`ifdef FULL_WDC65C02A
// The M65C02A core replaces the W65C02_Full_Core.
M65C02A M65C02A_Inst (
    // System Signals
    .nRst          (~reset),           // System Reset (Active Low)
    .Clk           (i_clk_cpu),        // System Clock (Phi2)
    .RdyIn         (~pause_cpu),       // Bus Ready Input (Active High Ready, derived from ~pause_cpu)
    
    // Interrupts
    .nNMI          (w_cpu_nmi_n),        // Non-Maskable Interrupt (Active Low)
    .nIRQ          (w_cpu_irq_n),        // Maskable Interrupt (Active Low)
    .nSO           (1'b1),             // Set oVerflow (Tie inactive high)
    
    // Bus/Status Outputs (Address and Data)
    .AB            (cpu_addr),         // Physical Address Outputs
    .DB            (w_db_bus),         // Data Bus (Connects to internal tri-state wire)

    // M65C02A Specific Strobes/Outputs (Mostly tied off or derived from)
    .nVP           (w_nVP),              // Vector Pull Output Strobe
    .Sync          (w_Sync),             // Instruction Fetch Status Strobe
    .nML           (w_nML),              // Memory Lock Status
    .nRD           (w_nRD),              // Read Strobe (Active Low)
    .nWR           (w_nWR),              // Write Strobe (Active Low)
    .nCE           (w_nCE_cpu),          // Decoded Chip Selects (Unused in GAMETANK BCU)
    .XA            (w_XA),               // Extended Physical Address (Unused)

    // Peripheral Tie-Offs (SPI and UART)
    .MISO          (1'b0),             // SPI Master In (Tie low)
    .nSSel         (w_nSSel),          // SPI Slave Select (Output, tie low later)
    .SCK           (w_SCK),            // SPI Clock (Output, tie low later)
    .MOSI          (w_MOSI),           // SPI Master Out (Output, tie low later)
    
    .COM0_RxD      (1'b0),             // COM0 Rx Data (Tie low)
    .COM0_nCTS     (1'b1),             // COM0 nCTS (Tie inactive high)
    .COM0_TxD      (),                 // Unused output
    .COM0_nRTS     (),                 // Unused output
    .COM0_DE       (),                 // Unused output

    .COM1_RxD      (1'b0),             // COM1 Rx Data (Tie low)
    .COM1_nCTS     (1'b1),             // COM1 nCTS (Tie inactive high)
    .COM1_TxD      (),                 // Unused output
    .COM1_nRTS     (),                 // Unused output
    .COM1_DE       ()                  // Unused output
) /*synthesis syn_keep=1*/;
`endif // FULL_WDC65C02A

// Tie off unused outputs from the M65C02A Core
// assign {w_nVP, w_Sync, w_nML} = 3'b111; // Active low signals tied high (inactive), Sync tied low (inactive)
// assign w_nCE_cpu = 4'b1111;             // Chip selects tied inactive high
// assign w_XA = 4'b0000;                  // Extended Address tied low
// assign w_nSSel = 2'b11;                 // SPI selects tied inactive high
// assign w_SCK = 1'b0;                    // SPI clock tied low
// assign w_MOSI = 1'b0;                   // SPI MOSI tied low

// ************************************************************
// ** 3. Bus Control Unit (BCU) Instantiation **
// ************************************************************
`define FULL_BUSCONTROLUNIT
`ifdef FULL_BUSCONTROLUNIT
BusControlUnit U_BCU (
    .i_cpu_addr                (cpu_addr),
    .i_cpu_rnw                 (cpu_rnw),

    // Chip Enables (Outputs to Peripherals)
    .o_gppram_ce               (gppram_ce),
    .o_acp_ce                  (acp_ce),
    .o_ppu_ce                  (ppu_ce),
    .o_io_ce                   (io_ce),
    .o_sdram_ce                (sdram_ce),
    .o_cart_ce                 (cart_ce),

    // Peripheral Data Inputs (Read Data to Multiplex)
    .i_gppram_data_in          (gppram_data_out),
    .i_acp_data_in             (acp_data_out),
    .i_ppu_data_in             (ppu_data_out),
    .i_io_data_in              (io_data_out),
    .i_sdram_data_in           (sdram_data_out),
    .i_cart_data_in            (cart_data_out),

    // CPU Data Output (Multiplexed Read Data)
    .o_data_out_to_cpu         (cpu_data_in)
) /*synthesis syn_keep=1*/;
`endif // FULL_BUSCONTROLUNIT

// ************************************************************
// ** 4. 2KB GPPRAM Module Instantiation ($0000-$07FF) **
// ************************************************************
`define FULL_GPPRAM_2KB
`ifdef FULL_GPPRAM_2KB
GPPRAM_2KB U_GPPRAM (
    .i_clk_cpu                 (i_clk_cpu),
    .i_reset                   (reset),

    .i_ce                      (gppram_ce),
    .i_rnw                     (cpu_rnw),
    .i_addr                    (cpu_addr[10:0]), // 11 bits for 2KB
    .i_data_in                 (cpu_dout),

    .o_data_out                (gppram_data_out)
) /*synthesis syn_keep=1*/;
`endif // FULL_GPPRAM_2KB

// ************************************************************
// ** 5. BSROM Cartridge Mapper Instantiation ($8000-$FFFF) **
// ************************************************************
`define FULL_BSROM_MAPPER
`ifdef FULL_BSROM_MAPPER
BSROM_Mapper U_BSROM_Mapper (
    .i_clk_cpu                 (i_clk_cpu),
    .i_ce                      (cart_ce),       // Enabled when CPU addresses $8000-$FFFF
    .i_rnw                     (cpu_rnw),
    .i_addr                    (cpu_addr),
    .o_data_out                (bsrom_data_out)
) /*synthesis syn_keep=1*/;
`endif // FULL_BSROM_MAPPER

// Connect the BSROM output to the main cartridge data bus wire
assign cart_data_out = bsrom_data_out;


// ************************************************************
// ** 6. PPU MMIO Register Implementation ($2000-$2007)    **
// ************************************************************
// `define FULL_PPU
`ifdef FULL_PPU
// Reset logic and write side effects (synchronous to CPU clock)
always @(posedge i_clk_cpu) begin
    // Default to no write pulse
    ppu_write_enable_reg <= 1'b0;

    if (reset) begin
        ppu_control_reg <= 8'h00;
        ppu_mask_reg <= 8'h00;
        ppu_oam_addr_reg <= 8'h00;
        ppu_scroll_x_reg <= 8'h00;
        ppu_scroll_y_reg <= 8'h00;
        ppu_addr_scroll_toggle <= 1'b0;
        ppu_addr_reg_internal <= 16'h0000;
        ppu_read_buffer <= 8'h00; // Reset read buffer
    end else begin
        // Side effect: Reading PPUSTATUS ($2002) clears the $2005/$2006 address toggle.
        if (ppu_ce && cpu_rnw && cpu_addr[2:0] == 3'b010) begin
            ppu_addr_scroll_toggle <= 1'b0; // Reset toggle on $2002 read
        end
        
        // Update read buffer on PPU read (should be VRAM data). Placeholder uses VRAM din.
        // NOTE: Actual logic requires a dedicated PPU VRAM read path, this mocks the latching behavior.
        if (ppu_ce && cpu_rnw && cpu_addr[2:0] == 3'b111) begin
            // Latch the VRAM data that was read during this cycle for the *next* $2007 read.
            // Since the PPU core logic is missing, we use the PPU Memory Input as a mock VRAM data source
            // The logic here is highly dependent on the complete PPU implementation.
            ppu_read_buffer <= i_ppumem_din; 
        end


        if (ppu_ce && !cpu_rnw) begin // PPU MMIO Write
            case (cpu_addr[2:0])
                3'b000: ppu_control_reg <= cpu_dout; // PPUCTRL ($2000)
                3'b001: ppu_mask_reg <= cpu_dout;    // PPUMASK ($2001)
                // $2002 is Read Only
                3'b011: ppu_oam_addr_reg <= cpu_dout; // OAMADDR ($2003)
                // $2004 OAMDATA write is usually handled by OAM logic

                3'b101: begin // PPUSCROLL ($2005) - Dual Write
                    if (ppu_addr_scroll_toggle == 1'b0) begin
                        ppu_scroll_x_reg <= cpu_dout; // First write (X)
                    end else begin
                        ppu_scroll_y_reg <= cpu_dout; // Second write (Y)
                    end
                    ppu_addr_scroll_toggle <= ~ppu_addr_scroll_toggle;
                end
                3'b110: begin // PPUADDR ($2006) - Dual Write
                    if (ppu_addr_scroll_toggle == 1'b0) begin
                        // First write (High byte) - Upper 2 bits are often ignored
                        ppu_addr_reg_internal[15:8] <= cpu_dout;
                    end else begin
                        // Second write (Low byte)
                        ppu_addr_reg_internal[7:0] <= cpu_dout;
                    end
                    ppu_addr_scroll_toggle <= ~ppu_addr_scroll_toggle;
                end
                3'b111: begin // PPUDATA ($2007) - Write to PPU VRAM
                    ppu_data_write_out_reg <= cpu_dout;
                    ppu_write_enable_reg <= 1'b1; // Strobe high for this cycle
                end
            endcase
        end
    end
end

// PPU MMIO Read Data (Combinational to BCU)
assign ppu_data_out = (ppu_ce && cpu_rnw) ?
    (cpu_addr[2:0] == 3'b010) ? ppu_status_reg :     // PPUSTATUS ($2002)
    (cpu_addr[2:0] == 3'b111) ? ppu_read_buffer :    // PPUDATA ($2007) - Reads from the internal buffer
    8'hFF : 8'hFF;                                  // Default unhandled PPU read is Open Bus (mocked as FF)

// Assign PPU output ports to internal registers
assign o_ppu_control             = ppu_control_reg;
assign o_ppu_mask                = ppu_mask_reg;
// Expose the scroll X/Y registers.
assign o_ppu_scroll              = {ppu_scroll_y_reg[7:4], ppu_scroll_x_reg[3:0]}; // Mock combination of last written bytes
assign o_ppu_addr                = ppu_addr_reg_internal;
assign o_ppu_data_write_out      = ppu_data_write_out_reg;
assign o_ppu_data_write_enable   = ppu_write_enable_reg;
`endif // FULL_PPU

// ************************************************************
// ** 7. Global Tie-Offs and SDRAM Interface Implementation **
// ************************************************************

// ACP MMIO Inputs to BCU (Read Data)
assign acp_data_out = 8'hFF;

// IO MMIO Inputs to BCU (Read Data)
assign io_data_out = 8'hFF;      // Joypad/IO MMIO
assign sdram_data_out = i_cpumem_din; // SDRAM Data In from top level
// Interrupts Tie-offs (Active High)
assign mapper_irq = 1'b0;      // Placeholder for Cartridge IRQ

// Audio/Video/IO Outputs
assign o_sample = {{8{1'b0}}, 8'h00};
assign o_color = 6'h00;
assign o_diskside_req = 2'b00;
assign o_joypad_out = 3'b000;
assign o_joypad_clock = 2'b00;
assign o_apu_ce = 1'b0;
assign o_gg_avail = 1'b0;
assign o_emphasis = 3'b000;
assign o_save_written = 1'b0;
assign o_cycle = 9'h00;
assign o_scanline = 9'h00;

// Determine if CPU is accessing the external memory regions ($6000-FFFF)
wire cpu_external_access = sdram_ce || cart_ce;

// CPU SDRAM Interface (These signals drive the SDRAM module in gametang_top.v)
assign o_cpumem_addr = {cpu_addr[15:0], 6'b0}; // Simplified mapping for 22 bits address space
assign o_cpumem_read = cpu_external_access && cpu_rnw;
assign o_cpumem_write = cpu_external_access && !cpu_rnw;
assign o_cpumem_dout = cpu_dout; // Data written by CPU

// PPU SDRAM Interface (Still tied off, needs PPU logic to drive it)
assign o_ppumem_addr = 22'h0;
assign o_ppumem_read = 1'b0;
assign o_ppumem_write = 1'b0;
assign o_ppumem_dout = 8'h00;

// BRAM Interface Tie-Offs
assign o_bram_addr = 18'h0;
assign o_bram_dout = 8'h00;
assign o_bram_write = 1'b0;
assign o_bram_override = 1'b0;

endmodule