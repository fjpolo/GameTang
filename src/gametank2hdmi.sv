// GAMETANK video and sound to HDMI converter
// nand2mario, 2022.9
// Updated for native GameTank R2G2B2 color conversion (R8G8B8 direct mapping).

`timescale 1ns / 1ps

module gametank2hdmi (
    input wire clk,       // gametank clock
    input wire resetn,

    // gametank video signals
    input wire [5:0] color,
    input wire [8:0] cycle,
    input wire [8:0] scanline,
    input wire [15:0] sample,
    input wire aspect_8x7,      // 1: 8x7 pixel aspect ratio mode

    // overlay interface
    input  wire overlay,
    output wire  [7:0] overlay_x,
    output wire  [7:0] overlay_y,
    input  wire  [14:0] overlay_color, // BGR5

    // video clocks
    input wire clk_pixel,
    input wire clk_5x_pixel,

    // output signals
    output wire        tmds_clk_n,
    output wire        tmds_clk_p,
    output wire [2:0] tmds_d_n,
    output wire [2:0] tmds_d_p
);

// GAMETANK generates 256x240. We assume the center 256x224 is visible and scale that to 4:3 aspect ratio.
// https://www.gametankdev.org/wiki/Overscan

localparam FRAMEWIDTH = 1280;
localparam FRAMEHEIGHT = 720;
localparam TOTALWIDTH = 1650;
localparam TOTALHEIGHT = 750;
localparam SCALE = 5;
localparam VIDEOID = 4;
localparam VIDEO_REFRESH = 60.0;

localparam CLKFRQ = 74250;

localparam COLLEN = 80;
localparam AUDIO_BIT_WIDTH = 16;

localparam POWERUPNS = 100000000.0;
localparam CLKPERNS = (1.0/CLKFRQ)*1000000.0;
localparam int POWERUPCYCLES = $rtoi($ceil( POWERUPNS/CLKPERNS ));

// video stuff
wire [9:0] cy, frameHeight;
wire [10:0] cx, frameWidth;

//
// BRAM frame buffer
//
localparam MEM_DEPTH=256*240;
localparam MEM_ABITS=16;

logic [5:0] mem [0:256*240-1] /*synthesis syn_ramstyle="block_ram"*/;
logic [15:0] mem_portA_addr;
logic [5:0] mem_portA_wdata;
logic mem_portA_we;

wire [15:0] mem_portB_addr;
logic [5:0] mem_portB_rdata; // 6-bit RRGGBB color index

// BRAM port A read/write
always_ff @(posedge clk) begin
    if (mem_portA_we) begin
        mem[mem_portA_addr] <= mem_portA_wdata;
    end
end

// BRAM port B read
always_ff @(posedge clk_pixel) begin
    mem_portB_rdata <= mem[mem_portB_addr];
end

initial begin
    $readmemb("background.txt", mem);
end


// 
// Data input and initial background loading
//
logic [8:0] r_scanline;
logic [8:0] r_cycle;
always @(posedge clk) begin
    r_scanline <= scanline;
    r_cycle <= cycle;
    mem_portA_we <= 1'b0;
    if ((r_scanline != scanline || r_cycle != cycle) && scanline < 9'd240 && ~cycle[8]) begin
        mem_portA_addr <= {scanline[7:0], cycle[7:0]};
        mem_portA_wdata <= color;
        mem_portA_we <= 1'b1;
    end
end

// audio stuff
localparam AUDIO_RATE=48000;
localparam AUDIO_CLK_DELAY = CLKFRQ * 1000 / AUDIO_RATE / 2;
logic [$clog2(AUDIO_CLK_DELAY)-1:0] audio_divider;
logic clk_audio;

always_ff@(posedge clk_pixel) 
begin
    if (audio_divider != AUDIO_CLK_DELAY - 1) 
        audio_divider++;
    else begin 
        clk_audio <= ~clk_audio; 
        audio_divider <= 0; 
    end
end

reg [15:0] audio_sample_word [1:0], audio_sample_word0 [1:0];
always @(posedge clk_pixel) begin      // crossing clock domain
    audio_sample_word0[0] <= sample;
    audio_sample_word[0] <= audio_sample_word0[0];
    audio_sample_word0[1] <= sample;
    audio_sample_word[1] <= audio_sample_word0[1];
end

//
// Video
// Scale 256x224 to 1280x720
//
localparam WIDTH=256;
localparam HEIGHT=240;
reg [23:0] rgb;             // actual RGB output
reg active              /* xsynthesis syn_keep=1 */;
reg [$clog2(WIDTH)-1:0] xx  /* xsynthesis syn_keep=1 */; // scaled-down pixel position
reg [$clog2(HEIGHT)-1:0] yy /* xsynthesis syn_keep=1 */;
reg [10:0] xcnt             /* xsynthesis syn_keep=1 */;
reg [10:0] ycnt             /* xsynthesis syn_keep=1 */;          // fractional scaling counters
reg [9:0] cy_r;
assign mem_portB_addr = yy * WIDTH + xx + 8*256;
assign overlay_x = xx;
assign overlay_y = yy;
localparam XSTART = (1280 - 960) / 2;   // 960:720 = 4:3
localparam XSTOP = (1280 + 960) / 2;

// address calculation
// Assume the video occupies fully on the Y direction, we are upscaling the video by `720/height`.
// xcnt and ycnt are fractional scaling counters.
always @(posedge clk_pixel) begin
    reg active_t;
    reg [10:0] xcnt_next;
    reg [10:0] ycnt_next;
    xcnt_next = xcnt + 256;
    ycnt_next = ycnt + 224;

    active_t = 0;
    if (cx == XSTART - 1) begin
        active_t = 1;
        active <= 1;
    end else if (cx == XSTOP - 1) begin
        active_t = 0;
        active <= 0;
    end

    if (active_t | active) begin        // increment xx
        xcnt <= xcnt_next;
        if (xcnt_next >= 960) begin
            xcnt <= xcnt_next - 960;
            xx <= xx + 1;
        end
    end

    cy_r <= cy;
    if (cy[0] != cy_r[0]) begin         // increment yy at new ligametank
        ycnt <= ycnt_next;
        if (ycnt_next >= 720) begin
            ycnt <= ycnt_next - 720;
            yy <= yy + 1;
        end
    end

    if (cx == 0) begin
        xx <= 0;
        xcnt <= 0;
    end
    
    if (cy == 0) begin
        yy <= 0;
        ycnt <= 0;
    end 

end

// --- GameTank Color Conversion Logic (R2G2B2 to R8G8B8) ---
// The GameTank 6-bit color is typically R[5:4] G[3:2] B[1:0].
// R8 = R2 is implemented using bit replication (V2 -> V2V2V2V2).
wire [5:0] gametank_color_index = mem_portB_rdata;

// Red (R[5:4]) -> R[7:0]
wire [7:0] r_out = {gametank_color_index[5], gametank_color_index[4], gametank_color_index[5], gametank_color_index[4], gametank_color_index[5], gametank_color_index[4], gametank_color_index[5], gametank_color_index[4]};
// Green (G[3:2]) -> G[7:0]
wire [7:0] g_out = {gametank_color_index[3], gametank_color_index[2], gametank_color_index[3], gametank_color_index[2], gametank_color_index[3], gametank_color_index[2], gametank_color_index[3], gametank_color_index[2]};
// Blue (B[1:0]) -> B[7:0]
wire [7:0] b_out = {gametank_color_index[1], gametank_color_index[0], gametank_color_index[1], gametank_color_index[0], gametank_color_index[1], gametank_color_index[0], gametank_color_index[1], gametank_color_index[0]};

wire [23:0] gametank_rgb = {r_out, g_out, b_out};

// calc rgb value to hdmi
always @(posedge clk_pixel) begin
    if (active) begin
        if (overlay)
            // Overlay color is BGR5 (15-bit) which is expanded to R8G8B8
            rgb <= {overlay_color[4:0],3'b0,overlay_color[9:5],3'b0,overlay_color[14:10],3'b0}; 
        else
            // Use the calculated R2G2B2 to R8G8B8 color
            rgb <= gametank_rgb;
    end else
        rgb <= 24'h303030; // Border color
end

// HDMI output.
logic[2:0] tmds;
wire tmdsClk; // Need to define tmdsClk wire for the ELVDS_OBUF block

hdmi #( .VIDEO_ID_CODE(VIDEOID), 
         .DVI_OUTPUT(0), 
         .VIDEO_REFRESH_RATE(VIDEO_REFRESH),
         .IT_CONTENT(1),
         .AUDIO_RATE(AUDIO_RATE), 
         .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
         .START_X(0),
         .START_Y(0) )

hdmi( .clk_pixel_x5(clk_5x_pixel), 
      .clk_pixel(clk_pixel), 
      .clk_audio(clk_audio),
      .rgb(rgb), 
      .reset( 0 ),
      .audio_sample_word(audio_sample_word),
      .tmds(tmds), 
      .tmds_clock(tmdsClk), 
      .cx(cx), 
      .cy(cy),
      .frame_width( frameWidth ),
      .frame_height( frameHeight ) );

// Gowin LVDS output buffer
// Note: Gowin-specific primitive 'ELVDS_OBUF' is assumed to be defined elsewhere in the project environment.
ELVDS_OBUF tmds_bufds [3:0] (
    .I({clk_pixel, tmds}),
    .O({tmds_clk_p, tmds_d_p}),
    .OB({tmds_clk_n, tmds_d_n})
);

// Note: The previous 2C02 palette assignment block has been removed, 
// as the correct GameTank R2G2B2 color is now calculated directly above.

endmodule