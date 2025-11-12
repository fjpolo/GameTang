// Copyright (c) 2025-3025 @fjpolo
// This program is GPL Licensed. See COPYING for the full license.

// `default_nettype none

module GAMETANK(
    input         i_clk_acp,        // ~14.32 MHz, from PLL in top.v (for PPU/ACP)
    input         i_clk_cpu,        // ~3.58 MHz, from PLL in top.v (for CPU)
    input         i_reset_gametank, // System Reset (Active High)
    input         i_cold_reset,
    input  [1:0]  i_sys_type,
    output [2:0]  o_gametank_div,
    input  [63:0] i_mapper_flags,
    output [15:0] o_sample,         // sample generated from APU
    output [5:0]  o_color,          // pixel generated from PPU
    output [2:0]  o_joypad_out,     // Set to 1 to strobe joypads. Then set to zero to keep the value (bit0)
    output [1:0]  o_joypad_clock,   // Set to 1 for each joypad to clock it.
    input  [4:0]  i_joypad1_data,   // Port1
    input  [4:0]  i_joypad2_data,   // Port2
    input         i_fds_busy,       // FDS Disk Swap Busy
    input         i_fds_eject,      // FDS Disk Swap Pause
    output [1:0]  o_diskside_req,
    input  [1:0]  i_diskside,
    input  [4:0]  i_audio_channels, // Enabled audio channels

    // Access signals for the SDRAM.
    output [21:0] o_cpumem_addr,
    output        o_cpumem_read,
    output        o_cpumem_write,
    output [7:0]  o_cpumem_dout,
    input  [7:0]  i_cpumem_din,
    output [21:0] o_ppumem_addr,
    output        o_ppumem_read,
    output        o_ppumem_write,
    output [7:0]  o_ppumem_dout,
    input  [7:0]  i_ppumem_din,

    // Override for BRAM
    output [17:0] o_bram_addr,      // address to access
    input  [7:0]  i_bram_din,       // Data from BRAM
    output [7:0]  o_bram_dout,
    output        o_bram_write,     // is a write operation
    output        o_bram_override,

    output [8:0]  o_cycle/* verilator public */,
    output [8:0]  o_scanline/* verilator public */,
    input         i_int_audio,
    input         i_ext_audio,
    output        o_apu_ce,
    input         i_gg,
    input  [128:0] i_gg_code,
    output        o_gg_avail,
    input         i_gg_reset,
    output [2:0]  o_emphasis,
    output        o_save_written
);

// --- Internal Wires and Registers for CPU and Bus Arbitration ---
wire [15:0] cpu_addr;        // CPU Address Bus (A0-A15)
wire cpu_rnw;              // CPU Read/Write (1=Read, 0=Write)
wire pause_cpu;            // Pause signal (for DMA or memory contention)
wire nmi;                  // NMI to CPU (Non-Maskable Interrupt)
wire mapper_irq;           // IRQ from Mapper/Cartridge
wire apu_irq;              // IRQ from APU (ACP)
wire [7:0] cpu_dout;        // Data written by CPU (Data Out)
wire [7:0] cpu_data_in;    // Data read by CPU (Data In, multiplexed)

// Reset signal for the main CPU (Active Low)
wire reset = i_reset_gametank;

// --- BUS CONTROL UNIT (BCU) Signals (Chip Enables) ---
wire gppram_ce;
wire acp_ce;
wire ppu_ce;
wire io_ce;
wire sdram_ce;
wire cart_ce;

// Peripheral Read Data Inputs to BCU
wire [7:0] gppram_data_out;
wire [7:0] acp_data_out;
wire [7:0] ppu_data_out;
wire [7:0] io_data_out;
wire [7:0] sdram_data_out;
wire [7:0] cart_data_out;

// --- PPU/GPU MMIO Controller Signals ---
wire i_vblank_flag = 1'b0; // Placeholder for VBlank status from PPU core
wire [7:0] ppu_ctrl_reg;
wire [7:0] ppu_mask_reg;
wire [15:0] ppu_vram_addr;
wire ppu_oam_dma_start;
wire [7:0] ppu_oam_addr_reg;


// ************************************************************
// ** 1. Clock and Utility Outputs **
// ************************************************************
// Provides clock and debug cycle outputs
assign o_gametank_div = {i_clk_cpu, 1'b0, 1'b0};


// ************************************************************
// ** 2. W65C02S CPU Core Instantiation **
// ** Main system processor for game logic and I/O control **
// ************************************************************
// Note: T65 module definition is assumed to be available elsewhere.
T65 cpu(
    .Mode    (0),
    .BCD_en  (0),

    .Res_n   (~reset),
    .Clk     (i_clk_cpu),
    .Enable  (1'b1),
    .Rdy     (~pause_cpu),
    .Abort_n (1'b1),

    .IRQ_n   (~(apu_irq | mapper_irq)), // Combined IRQ request
    .NMI_n   (~nmi),
    .SO_n    (1'b1),
    .R_W_n   (cpu_rnw),
    // Unused outputs tied off below
    .Sync(), .EF(), .MF(), .XF(), .ML_n(), .VP_n(), .VDA(), .VPA(), 

    .A       (cpu_addr),
    .DI      (cpu_rnw ? cpu_data_in : cpu_dout), // Data In multiplexed
    .DO      (cpu_dout),                            // Data Out from CPU

    .Regs(), .DEBUG(), .NMI_ack()
);

assign pause_cpu = 1'b0; // ** CRITICAL: Tied off for now. Will be driven by SDRAM/DMA. **


// ************************************************************
// ** 3. Bus Control Unit (BCU) Instantiation **
// ** Handles Address Decoding and Read Data Arbitration **
// ************************************************************

BusControlUnit U_BCU (
    .i_cpu_addr           (cpu_addr),
    .i_cpu_rnw            (cpu_rnw),

    // Chip Enables (Outputs to Peripherals)
    .o_gppram_ce          (gppram_ce),
    .o_acp_ce             (acp_ce),
    .o_ppu_ce             (ppu_ce),
    .o_io_ce              (io_ce),
    .o_sdram_ce           (sdram_ce),
    .o_cart_ce            (cart_ce),

    // Peripheral Data Inputs (Read Data to Multiplex)
    .i_gppram_data_in     (gppram_data_out),
    .i_acp_data_in        (acp_data_out),
    .i_ppu_data_in        (ppu_data_out),
    .i_io_data_in         (io_data_out),
    .i_sdram_data_in      (sdram_data_out),
    .i_cart_data_in       (cart_data_out),
    
    // CPU Data Output (Multiplexed Read Data)
    .o_data_out_to_cpu    (cpu_data_in)
);


// ************************************************************
// ** 4. 2KB GPPRAM Module Instantiation ($0000-$07FF) **
// ** CPU's fast internal working RAM **
// ************************************************************

GPPRAM_2KB U_GPPRAM (
   .i_clk_cpu            (i_clk_cpu),
   .i_reset              (reset),
   
   .i_ce                 (gppram_ce),
   .i_rnw                (cpu_rnw),
   .i_addr               (cpu_addr[10:0]), // 11 bits for 2KB
   .i_data_in            (cpu_dout),
   
   .o_data_out           (gppram_data_out)
);


// ************************************************************
// ** 5. PPU MMIO Controller Instantiation ($4000-$4015) **
// ** Manages Control, Mask, VRAM Address Latches, and DMA trigger **
// ************************************************************

//PPU_MMIO_Controller U_PPU_MMIO (
//    .i_clk_cpu            (i_clk_cpu),
//    .i_reset              (reset),
//    
//    .i_ce                 (ppu_ce),
//    .i_rnw                (cpu_rnw),
//    .i_addr_lsb           (cpu_addr[3:0]), // Lower 4 bits select the register
//    .i_data_in            (cpu_dout),
//    
//    .i_vblank_flag        (i_vblank_flag), // Placeholder status input from PPU core
//    
//    .o_data_out           (ppu_data_out), // Data read back to CPU
//    
// //      PPU Control Outputs
//    .o_ctrl_reg           (ppu_ctrl_reg),     // $4000
//    .o_mask_reg           (ppu_mask_reg),     // $4001
//    .o_ppu_addr           (ppu_vram_addr),    // Latch for $4006/$4007
//    .o_oam_dma_start      (ppu_oam_dma_start),// $4014 trigger
//    .o_oam_addr_reg       (ppu_oam_addr_reg)  // $4003
//);


// ************************************************************
// ** 6. APU (ACP) / Audio & Mapper Peripherals **
// ** Placeholder for future audio and cartridge modules **
// ************************************************************
// APU IRQ is required for CPU module
assign apu_irq = 1'b0; // Tied off

// Module kept for bus integrity, but implementation is outside current focus.
wire [7:0] o_audio_dac;

// Placeholder for ACP Instantiation
// Audio_CoProcessor_System U_ACP ( ... );
assign o_sample = {{8{1'b0}}, o_audio_dac};
assign o_audio_dac = 8'h00; // Tied off


// ************************************************************
// ** 7. Global Tie-Offs for Missing Modules & Unused Ports **
// ************************************************************

// Data read inputs to the BCU from tied-off components (default to open bus $FF)
assign acp_data_out = 8'hFF;    // ACP MMIO/RAM
assign io_data_out = 8'hFF;     // Joypad/IO MMIO
assign sdram_data_out = 8'hFF;  // SDRAM/Save RAM
assign cart_data_out = 8'hFF;   // Cartridge ROM

// Tie off required outputs for the compiler/simulation
assign o_cycle = 9'h00; 
assign o_scanline = 9'h00; 
assign o_apu_ce = 1'b0; 
assign o_gg_avail = 1'b0;
assign o_emphasis = 3'b000;
assign o_save_written = 1'b0;
assign o_diskside_req = 2'b00;
assign o_joypad_out = 3'b000;
assign o_joypad_clock = 2'b00;
assign nmi = 1'b0;      // Placeholder for PPU NMI
assign mapper_irq = 1'b0; // Placeholder for Cartridge IRQ

// Tie off control signals for the missing SDRAM/PPU controllers
assign o_cpumem_addr = 22'h0;
assign o_cpumem_read = 1'b0;
assign o_cpumem_write = 1'b0;
assign o_cpumem_dout = 8'h00;
assign o_ppumem_addr = 22'h0;
assign o_ppumem_read = 1'b0;
assign o_ppumem_write = 1'b0;
assign o_ppumem_dout = 8'h00;

// Tie off BRAM logic
assign o_bram_addr = 18'h0;
assign o_bram_dout = 8'h00;
assign o_bram_write = 1'b0;
assign o_bram_override = 1'b0;


endmodule