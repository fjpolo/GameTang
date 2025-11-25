//
// GAMETang top level
// @fjpolo
//

// `timescale 1ns / 100ps
// `define CONTROLLER_SNES

import configPackage::*;

module gametang_top (
    input sys_clk,

    // Button S1 and pin 48 are both resets
    input s1,
    input reset2,

    // UART
    input UART_RXD,
    output UART_TXD,

    // SDRAM - Tang SDRAM pmod 1.2 for primer 25k, on-chip 32-bit 8MB SDRAM for nano 20k
    output O_sdram_clk,
    output O_sdram_cke,
    output O_sdram_cs_n,                     // chip select
    output O_sdram_cas_n,                    // columns address select
    output O_sdram_ras_n,                    // row address select
    output O_sdram_wen_n,                    // write enable
    inout [SDRAM_DATA_WIDTH-1:0] IO_sdram_dq,        // bidirectional data bus
    output [SDRAM_ROW_WIDTH-1:0] O_sdram_addr,      // multiplexed address bus
    output [1:0] O_sdram_ba,                         // two banks
    output [SDRAM_DATA_WIDTH/8-1:0] O_sdram_dqm,
    // LEDs
    output [7:0] led,

    // sgametank controllers
    output joy1_strb,
    output joy1_clk,
    input joy1_data,
    output joy2_strb,
    output joy2_clk,
    input joy2_data,

    // HDMI TX
    output tmds_clk_n,
    output tmds_clk_p,
    output [2:0] tmds_d_n,
    output [2:0] tmds_d_p
);

// Core settings
wire arm_reset = 0;
wire [1:0] system_type = 2'b0;
wire pal_video = 0;
wire [1:0] scanligametank = 2'b0;
wire joy_swap = 0;
wire mirroring_osd = 0;
wire overscan_osd = 0;
wire famicon_kbd = 0;
wire [3:0] palette_osd = 0;
wire [2:0] diskside_osd = 0;
wire blend = 0;
wire bk_save = 0;

// GAMETANK signals
// FIX: reset_gametank is now a wire driven by sys_resetn to prevent permanent reset.
wire reset_gametank;
reg clkref;
wire [5:0] color;
wire [15:0] sample;
wire [8:0] scanline;
wire [8:0] cycle;
wire [2:0] joypad_out;
wire joypad_strobe = joypad_out[0];
wire [1:0] joypad_clock;
wire [4:0] joypad1_data, joypad2_data;

wire sdram_busy;
wire [21:0] memory_addr_cpu, memory_addr_ppu;
wire memory_read_cpu, memory_read_ppu;
wire memory_write_cpu, memory_write_ppu;
wire [7:0] memory_din_cpu, memory_din_ppu;
wire [7:0] memory_dout_cpu, memory_dout_ppu;

// Wires for PPU MMIO Register Outputs from GAMETANK core
wire [7:0] ppu_control_out;
wire [7:0] ppu_mask_out;
wire [7:0] ppu_scroll_out;
wire [15:0] ppu_addr_out; // Fixed to 16-bit
wire [7:0] ppu_data_write_out;
wire ppu_data_write_enable;

reg [7:0] joypad_bits, joypad_bits2;
reg [1:0] last_joypad_clock;

// DEBUG SIGNALS: Driven by joypad input
wire [31:0] dbgadr;
wire [1:0] dbgctr;

wire [1:0] gametank_ce;

wire loading;                        // from iosys or game_data
wire [7:0] loader_do;
wire loader_do_valid;

// iosys softcore
wire rv_valid;
reg rv_ready;
wire [22:0] rv_addr;
wire [31:0] rv_wdata;
wire [3:0] rv_wstrb;
reg [15:0] rv_dout0;
wire [31:0] rv_rdata = {rv_dout, rv_dout0};
reg rv_valid_r;
reg rv_word;                      // which word
reg rv_req;
wire rv_req_ack;
wire [15:0] rv_dout;
reg [1:0] rv_ds;
reg rv_new_req;
wire sys_reset_n = ~reset2;
assign reset_gametank = ~sys_resetn; // FIX: Active high core reset
iosys_picorv32 #(
    .FREQ(21_477_000),
    .COLOR_LOGO(15'b00000_10101_00000),
    .CORE_ID(1)      // 1: gametang, 2: sgametang
)
i_iosys(
    .clk(sys_clk),                   // SNES mclk
    .hclk(fclk),                     // hdmi clock
    .resetn(sys_reset_n),
    // OSD display interface
    .overlay,
    .overlay_x(),           // 720p
    .overlay_y(),
    .overlay_color(),        // BGR5, [15] is opacity
    .joy1(),                 // joystick 1: (R L X A RT LT DN UP START SELECT Y B)
    .joy2(),                 // joystick 2
    // ROM loading interface
    .rom_loading(),            // 0-to-1 loading starts, 1-to-0 loading is finished
    .rom_do(),                 // first 64 bytes are snes header + 32 bytes after snes header
    .rom_do_valid(),           // strobe for rom_do
    // 32-bit wide memory interface for risc-v softcore
    // 0x_xxxx~6x_xxxx is RV RAM, 7x_xxxx is BSRAM
    .rv_valid(),                     // 1: active memory access
    .rv_ready(),                     // pulse when access is done
    .rv_addr(),              // 8MB memory space
    .rv_wdata(),             // 32-bit write data
    .rv_wstrb(),              // 4 byte write strobe
    .rv_rdata(),             // 32-bit read data
    .ram_busy(),                     // iosys starts after SDRAM initialization
    // SPI flash
    .flash_spi_cs_n(),               // chip select
    .flash_spi_miso(),               // master in slave out
    .flash_spi_mosi(),               // mster out slave in
    .flash_spi_clk(),                // spi clock
    .flash_spi_wp_n(),               // write protect
    .flash_spi_hold_n(),             // hold operations
    // UART
    .uart_rx(),
    .uart_tx(),
    // SD card
    .sd_clk(),
    .sd_cmd(),                       // MOSI
    .sd_dat0(),                      // MISO
    .sd_dat1(),                      // 1
    .sd_dat2(),                      // 1
    .sd_dat3()                       // 0 for SPI mode
);

// Controller
wire [7:0] joy_rx[0:1], joy_rx2[0:1]  /*synthesis syn_keep=1*/;;        // 6 RX bytes for all button/axis state
wire [7:0] usb_btn, usb_btn2  /*synthesis syn_keep=1*/;;
wire usb_btn_x, usb_btn_y, usb_btn_x2, usb_btn_y2  /*synthesis syn_keep=1*/;;
wire usb_conerr, usb_conerr2  /*synthesis syn_keep=1*/;;
wire auto_a, auto_b, auto_a2, auto_b2  /*synthesis syn_keep=1*/;;


// OR together when both GAMETANK and DS2 controllers are connected (right now only nano20k supports both simultaneously)
wire [11:0] joy1_btns, joy2_btns  /*synthesis syn_keep=1*/;;     // GAMETANK layout (R L X A RT LT DN UP START SELECT Y B)
                                     // Lower 8 bits are GAMETANK buttons
wire [11:0] joy_usb1, joy_usb2  /*synthesis syn_keep=1*/;;
wire [11:0] hid1, hid2  /*synthesis syn_keep=1*/;;              // From BL616
wire [11:0] joy1 = joy1_btns | hid1 | joy_usb1  /*synthesis syn_keep=1*/;;
wire [11:0] joy2 = joy2_btns | hid2 | joy_usb2  /*synthesis syn_keep=1*/;;

// GAMETANK gamepad
wire [7:0]GAMETANK_gamepad_button_state  /*synthesis syn_keep=1*/;;
wire GAMETANK_gamepad_data_available  /*synthesis syn_keep=1*/;;
wire [7:0]GAMETANK_gamepad_button_state2  /*synthesis syn_keep=1*/;;
wire GAMETANK_gamepad_data_available2  /*synthesis syn_keep=1*/;;

///////////////////////////
// Clocks
///////////////////////////

wire clk;        // 21.477Mhz main clock
wire hclk;       // 720p pixel clock: 74.25 Mhz
wire hclk5;      // 5x pixel clock: 371.25 Mhz
wire clk27;      // 27Mhz to generate hclk/hclk5
wire clk_usb;    // 12Mhz USB clock

reg sys_resetn = 0;
reg [7:0] reset_cnt = 255;      // reset for 255 cycles before start everything
always @(posedge clk) begin
    reset_cnt <= reset_cnt == 0 ? 0 : reset_cnt - 1;
    if (reset_cnt == 0)
//    if (reset_cnt == 0 && s1)       // for nano
        sys_resetn <= ~(joy1_btns[5] && joy1_btns[2]);      // 8BitDo Home button = Select + Down
end

`ifdef FULL_PLL_R
`define PLL_R
`ifdef PLL_R
// Nano uses rPLL and 27Mhz crystal
assign clk27 = sys_clk;         // Nano20K: native 27Mhz system clock
gowin_pll_gametank pll_gametank(.clkin(sys_clk), .clkoutd3(clk), .clkout(fclk), .clkoutp(O_sdram_clk));
`else
// All other boards uses 50Mhz crystal
gowin_pll_27 pll_27 (.clkin(sys_clk), .clkout0(clk27));       // Primer25K: PLL to generate 27Mhz from 50Mhz
gowin_pll_gametank pll_gametank (.clkin(sys_clk), .clkout0(clk), .clkout1(fclk), .clkout2(O_sdram_clk));
`endif
`endif // FULL_PLL_R
gowin_pll_hdmi pll_hdmi (
    .clkin(clk27),
    .clkout(hclk5)
) /*synthesis syn_keep=1*/;

CLKDIV #(.DIV_MODE(5)) div5 (
    .CLKOUT(hclk),
    .HCLKIN(hclk5),
    .RESETN(sys_resetn),
    .CALIB(1'b0)
) /*synthesis syn_keep=1*/;

wire [31:0] status /*synthesis syn_keep=1*/;

// --- JOYSTICK DEBUG LOGIC IMPLEMENTATION ---
// Use SELECT (joy1[5]) to enable debug mode.
// UP/DOWN selects the debug mode (dbgctr).
// 2'b00: Normal (default/no select)
// 2'b01: Show Scanline/Cycle
// 2'b10: Future Debug Mode
assign dbgctr = joy1[5] ?
                     (joy1[7] ? 2'b01 : (joy1[6] ? 2'b10 : 2'b00)) :
                     2'b00;

// Expose CPU timing and other states for debug display
assign dbgadr = {13'h0, scanline, cycle};
// ------------------------------------------

// Main GAMETANK machine
wire clk_stb = (clk)&(joy1_btns[2])/*synthesis syn_keep=1*/;
GAMETANK gametank(
    // Clocks
    .i_clk_acp(clk_stb),          // Primary PPU/ACP clock (~14.32 MHz, using 21.477Mhz 'clk')
    .i_clk_cpu(clk_stb),          // **TODO: This should be the 3.58 MHz CPU clock. Using 'clk' temporarily.**

    // Reset/System
    .i_reset_gametank(reset_gametank), // System Reset (Active High) - FIX: No longer permanently '1'
    .i_cold_reset(1'b0),
    .i_sys_type(system_type),
    .o_gametank_div(gametank_ce),        // Clock cycle dividers [2:0] (wire is [1:0] and will be truncated)

    // Mapper/Cartridge
    .i_mapper_flags(mapper_flags),

    // Video/Audio Outputs
    .o_sample(sample),
    .o_color(color),

    // Joypads/I/O
    .o_joypad_out(joypad_out),
    .o_joypad_clock(joypad_clock),
    .i_joypad1_data(joypad1_data),
    .i_joypad2_data(joy2_data), // Fix: Should be joy2_data, not joy2_data for the core input

    // Disk System (Tied off)
    .i_fds_busy(1'b0),
    .i_fds_eject(1'b0),
    .o_diskside_req(),
    .i_diskside(2'b00),
    .i_audio_channels(5'b11111),

    // CPU Memory Interface (SDRAM)
    .o_cpumem_addr(memory_addr_cpu),
    .o_cpumem_read(memory_read_cpu),
    .o_cpumem_write(memory_write_cpu),
    .o_cpumem_dout(memory_dout_cpu),
    .i_cpumem_din(memory_din_cpu),

    // PPU Memory Interface (SDRAM)
    .o_ppumem_addr(memory_addr_ppu),
    .o_ppumem_read(memory_read_ppu),
    .o_ppumem_write(memory_write_ppu),
    .o_ppumem_dout(memory_dout_ppu),
    .i_ppumem_din(memory_din_ppu),

    // PPU MMIO Register Outputs
    .o_ppu_control(ppu_control_out),
    .o_ppu_mask(ppu_mask_out),
    .o_ppu_scroll(ppu_scroll_out),
    .o_ppu_addr(ppu_addr_out),
    .o_ppu_data_write_out(ppu_data_write_out),
    .o_ppu_data_write_enable(ppu_data_write_enable),

    // BRAM Override (Tied off)
    .o_bram_addr(),
    .i_bram_din(8'h00),
    .o_bram_dout(),
    .o_bram_write(),
    .o_bram_override(),

    // Debug/Timing
    .o_cycle(cycle),
    .o_scanline(scanline),
    .i_dbgadr(dbgadr), // ADDED: Connect Debug Address from joystick logic
    .i_dbgctr(dbgctr), // ADDED: Connect Debug Control from joystick logic

    // APU/IRQ
    .i_int_audio(int_audio),
    .i_ext_audio(ext_audio),
    .o_apu_ce(),

    // Game Genie (Tied off)
    .i_gg(1'b0),
    .i_gg_code(129'b0),
    .o_gg_avail(),
    .i_gg_reset(1'b0),
    .o_emphasis(),
    .o_save_written()
) /*synthesis syn_keep=1*/;













///////////////////////////
// Peripherals
///////////////////////////

// For physical board, there's HDMI, iosys, joypads, and USB
wire overlay;                          // iosys controls overlay
wire [7:0] overlay_x /*synthesis syn_keep=1*/;
wire [7:0] overlay_y /*synthesis syn_keep=1*/;
wire [14:0] overlay_color /*synthesis syn_keep=1*/;          // BGR5

// Controller input
controller_snes joy1_sgametank (
    .clk(clk), .resetn(sys_resetn), .buttons(joy1_btns),
    .joy_strb(joy1_strb), .joy_clk(joy1_clk), .joy_data(joy1_data)
) /*synthesis syn_keep=1*/;
controller_snes joy2_sgametank (
    .clk(clk), .resetn(sys_resetn), .buttons(joy2_btns),
    .joy_strb(joy2_strb), .joy_clk(joy2_clk), .joy_data(joy2_data)
) /*synthesis syn_keep=1*/;

// Autofire for GAMETANK A (right) and B (left) buttons
Autofire af_a (.clk(clk), .resetn(sys_resetn), .btn(joy1[8]), .out(auto_a));
Autofire af_b (.clk(clk), .resetn(sys_resetn), .btn(joy1[9]), .out(auto_b));
Autofire af_a2 (.clk(clk), .resetn(sys_resetn), .btn(joy2[8]), .out(auto_a2));
Autofire af_b2 (.clk(clk), .resetn(sys_resetn), .btn(joy2[9]), .out(auto_b2));

// Joypad handling
always @(posedge clk) begin
    if (joypad_strobe) begin
        joypad_bits <= {joy1[7:2], joy1[1] | auto_b, joy1[0] | auto_a};
        joypad_bits2 <= {joy2[7:2], joy2[1] | auto_b2, joy2[0] | auto_a2};
    end
    if (!joypad_clock[0] && last_joypad_clock[0])
        joypad_bits <= {1'b1, joypad_bits[7:1]};
    if (!joypad_clock[1] && last_joypad_clock[1])
        joypad_bits2 <= {1'b1, joypad_bits2[7:1]};
    last_joypad_clock <= joypad_clock;
end
assign joypad1_data[0] = joypad_bits[0];
assign joypad2_data[0] = joypad_bits2[0];

endmodule