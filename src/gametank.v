// Copyright (c) 2025-3025 @fjpolo
// This program is GPL Licensed. See COPYING for the full license.


module GAMETANK(
	input         clk,
	input         reset_gametank,
	input         cold_reset,
	input   [1:0] sys_type,
	output  [2:0] gametank_div,
	input  [63:0] mapper_flags,
	output [15:0] sample,         // sample generated from APU
	output  [5:0] color /* verilator public */,          // pixel generated from PPU
	output  [2:0] joypad_out,     // Set to 1 to strobe joypads. Then set to zero to keep the value (bit0)
	output  [1:0] joypad_clock,   // Set to 1 for each joypad to clock it.
	input   [4:0] joypad1_data,   // Port1
	input   [4:0] joypad2_data,   // Port2
	input         fds_busy,       // FDS Disk Swap Busy
	input         fds_eject,      // FDS Disk Swap Pause
	output  [1:0] diskside_req,
	input   [1:0] diskside,
	input   [4:0] audio_channels, // Enabled audio channels

	// Access signals for the SDRAM.
	output [21:0] cpumem_addr,
	output        cpumem_read,
	output        cpumem_write,
	output  [7:0] cpumem_dout,
	input   [7:0] cpumem_din,
	output [21:0] ppumem_addr,
	output        ppumem_read,
	output        ppumem_write,
	output  [7:0] ppumem_dout,
	input   [7:0] ppumem_din,

	// Override for BRAM
	output [17:0] bram_addr,      // address to access
	input   [7:0] bram_din,       // Data from BRAM
	output  [7:0] bram_dout,
	output        bram_write,     // is a write operation
	output        bram_override,

	output  [8:0] cycle/* verilator public */,
	output  [8:0] scanline/* verilator public */,
	input         int_audio,
	input         ext_audio,
	output        apu_ce,
	input         gg,
	input [128:0] gg_code,
	output        gg_avail,
	input         gg_reset,
	output  [2:0] emphasis,
	output        save_written
);


/**********************************************************/
/*************            Clocks            ***************/
/**********************************************************/


/**********************************************************/
/*************        W65C02S CPU           ***************/
/**********************************************************/

wire [15:0] cpu_addr;
wire cpu_rnw;
wire pause_cpu;
wire nmi;
wire mapper_irq;
wire apu_irq;

// IRQ only changes once per CPU ce and with our current
// limited CPU model, NMI is only latched on the falling edge
// of M2, which corresponds with CPU ce, so no latches needed.

T65 cpu(
	.Mode   (0),
	.BCD_en (0),

	.Res_n  (~reset),
	.Clk    (clk),
	.Enable (cpu_ce),
	.Rdy    (~pause_cpu),
	.Abort_n(1'b1),

	.IRQ_n  (~(apu_irq | mapper_irq)),
	.NMI_n  (~nmi),
	.SO_n   (1'b1),
	.R_W_n  (cpu_rnw),
	.Sync(), .EF(), .MF(), .XF(), .ML_n(), .VP_n(), .VDA(), .VPA(),

	.A      (cpu_addr),
	.DI     (cpu_rnw ? from_data_bus : cpu_dout),
	.DO     (cpu_dout),

	.Regs(), .DEBUG(), .NMI_ack()
);

/**********************************************************/
/*************            GPPRAM            ***************/
/**********************************************************/

/**********************************************************/
/*************             APU              ***************/
/**********************************************************/
// W65C02S at 14 MHz with 4KB RAM, default 14 kHz sample rate

/**********************************************************/
/*************           PPU/GPU            ***************/
/**********************************************************/
// Video: 128x128 framebuffer, some rows on top and bottom hidden by most TVs
// Graphics acceleration: Hardware-accelerated byte copy, also known as a "Blitter", can transfer images to the framebuffer on every clock cycle at 3.5 MHz
// Graphics RAM: 512 KB used as source data for blitter

/**********************************************************/
/*************             Cart             ***************/
/**********************************************************/
// Custom 36-pin 0.1-inch pitch format, standard board contains 2 MB of flash memory

/**********************************************************/
/*************       Bus Arbitration        ***************/
/**********************************************************/

/**********************************************************/
/*************       Expansion Port         ***************/
/**********************************************************/
// 26-pin rear expansion port exposing 12 bits of GPIO and other system signals


endmodule
