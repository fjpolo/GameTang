// PPU_Controller.v
// Handles Memory-Mapped I/O (MMIO) access for the PPU registers (addresses $4000 - $4007).
// This module provides the CPU's interface to configure and control the PPU core.

module PPU_Controller (
    // System Interfaces
    input wire clk,
    input wire reset,

    // CPU MMIO Interface (Inputs from BusControlUnit/CPU)
    input wire [15:0] i_cpu_addr,  // CPU address bus (only relevant: A2:A0 for register selection)
    input wire [7:0] i_cpu_data_in, // Data from CPU for write operations
    input wire i_cpu_we,          // Write Enable from CPU
    output reg [7:0] o_cpu_data_out, // Data to CPU for read operations
    input wire i_ce,              // Chip Enable from Bus Control Unit ($4000-$4007)

    // Interface to PPU Core (Outputs to the PPU rendering logic)
    output reg [7:0] o_ppu_control,   // PPUCTRL ($4000)
    output reg [7:0] o_ppu_mask,      // PPUMASK ($4001)
    output reg [7:0] o_ppu_scroll,    // PPUSCROLL ($4005) (Placeholder for scroll data)
    output reg [7:0] o_ppu_addr,      // PPUADDR ($4006) (Placeholder for VRAM address high/low bytes)
    output reg [7:0] o_ppu_data_write_out, // PPUData output to VRAM
    output reg o_ppu_data_write_enable // VRAM write strobe

    // Note: PPUSTATUS ($4002) read/write and PPUDATA ($4007) read/write are complex
    // as they involve internal PPU state and a read buffer. We will implement simple
    // placeholder logic here, assuming an external PPU core handles VRAM interaction.
);

// Internal Registers corresponding to MMIO addresses $4000 through $4007
reg [7:0] reg_control;    // $4000: PPUCTRL
reg [7:0] reg_mask;       // $4001: PPUMASK
reg [7:0] reg_status;     // $4002: PPUSTATUS (Read-only status register)
reg [7:0] reg_oam_addr;   // $4003: OAMADDR
reg [7:0] reg_oam_data;   // $4004: OAMDATA
reg [7:0] reg_scroll_latch; // $4005: PPUSCROLL (Write twice for X and Y)
reg [7:0] reg_addr_latch; // $4006: PPUADDR (Write twice for High and Low address)
reg [7:0] reg_data_latch; // $4007: PPUDATA (Read/Write data port)

// --- Address Decoding and Write Logic ---
// We use A2:A0 to select the register within the $4000-$4007 block.
wire [2:0] register_select = i_cpu_addr[2:0];

always @(posedge clk or posedge reset) begin
    if (reset) begin
        reg_control <= 8'h00;
        reg_mask <= 8'h00;
        reg_status <= 8'h00;
        reg_oam_addr <= 8'h00;
        reg_oam_data <= 8'h00;
        reg_scroll_latch <= 8'h00;
        reg_addr_latch <= 8'h00;
        reg_data_latch <= 8'h00;
        o_ppu_data_write_enable <= 1'b0;
    end else if (i_ce && i_cpu_we) begin
        // CPU is writing to the PPU Controller MMIO range
        o_ppu_data_write_enable <= 1'b0; // Default: No VRAM write

        case (register_select)
            3'h0: reg_control <= i_cpu_data_in;    // $4000: PPUCTRL
            3'h1: reg_mask <= i_cpu_data_in;       // $4001: PPUMASK
            // $4002 is read-only, ignore writes
            3'h3: reg_oam_addr <= i_cpu_data_in;   // $4003: OAMADDR
            3'h4: reg_oam_data <= i_cpu_data_in;   // $4004: OAMDATA
            3'h5: reg_scroll_latch <= i_cpu_data_in; // $4005: PPUSCROLL
            3'h6: reg_addr_latch <= i_cpu_data_in;   // $4006: PPUADDR
            3'h7: begin                          // $4007: PPUDATA
                reg_data_latch <= i_cpu_data_in;
                o_ppu_data_write_enable <= 1'b1; // Strobe to VRAM
            end
        endcase
    end else if (i_ce && !i_cpu_we) begin
        // CPU is reading from the PPU Controller MMIO range
        // Reads are combinatorial, handled in the 'Read Logic' section below.
    end
end

// --- Read Logic (Combinatorial) ---
always @(*) begin
    o_cpu_data_out = 8'h00; // Default to 0

    if (i_ce && !i_cpu_we) begin
        case (register_select)
            // $4000, $4001, $4003, $4004, $4005, $4006 are typically write-only or use
            // read-back of written values. We will return the internal register values.
            3'h0: o_cpu_data_out = reg_control;
            3'h1: o_cpu_data_out = reg_mask;
            3'h2: o_cpu_data_out = reg_status;   // $4002: PPUSTATUS (Status returned here)
            3'h3: o_cpu_data_out = reg_oam_addr;
            3'h4: o_cpu_data_out = reg_oam_data;
            3'h5: o_cpu_data_out = reg_scroll_latch;
            3'h6: o_cpu_data_out = reg_addr_latch;
            3'h7: o_cpu_data_out = reg_data_latch; // $4007: PPUDATA (Reading VRAM is complex, placeholder)
        endcase
    end
end

// --- PPU Core Outputs ---
// Connect internal registers to the PPU Core interface
assign o_ppu_control = reg_control;
assign o_ppu_mask = reg_mask;
assign o_ppu_scroll = reg_scroll_latch; // Simplified: PPU core handles the internal X/Y latching
assign o_ppu_addr = reg_addr_latch;     // Simplified: PPU core handles the internal high/low latching
assign o_ppu_data_write_out = reg_data_latch; // Data ready to be written to VRAM
// o_ppu_data_write_enable is generated in the sequential block
endmodule