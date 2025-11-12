// Copyright (c) 2025-3025 @fjpolo
// This program is GPL Licensed. See COPYING for the full license.

// `default_nettype none

// Implementation of the Bus Control Unit (BCU).
// Generates Chip Enables (CE) based on CPU address decoding and multiplexes
// read data from all peripherals onto the CPU data bus.
module BusControlUnit (
    // CPU Interface Inputs
    input wire [15:0] i_cpu_addr,
    input wire        i_cpu_rnw, // 1=Read, 0=Write (THIS WAS MISSING)
    
    // Chip Enable Outputs
    output wire o_gppram_ce,
    output wire o_acp_ce,   // APU/IO Registers ($4000-$4017)
    output wire o_ppu_ce,   // PPU MMIO Registers ($2000-$3FFF)
    output wire o_io_ce,    // I/O Registers (Typically subset of $4000-$401F)
    output wire o_sdram_ce, // SDRAM / Save RAM ($6000-$7FFF, or similar)
    output wire o_cart_ce,  // Cartridge ROM ($8000-$FFFF)

    // Peripheral Read Data Inputs (THESE WERE MISSING)
    input wire [7:0] i_gppram_data_in,
    input wire [7:0] i_acp_data_in,
    input wire [7:0] i_ppu_data_in,
    input wire [7:0] i_io_data_in,
    input wire [7:0] i_sdram_data_in,
    input wire [7:0] i_cart_data_in,
    
    // CPU Data Output (Multiplexed Read Data) (THIS WAS MISSING)
    output reg [7:0] o_data_out_to_cpu
);

// --- 1. Address Decoding and Chip Enable Generation ---

// GPPRAM: $0000-$1FFF (2KB mirrored)
assign o_gppram_ce = (i_cpu_addr[15:13] == 3'b000);

// PPU: $2000-$3FFF (8 registers mirrored)
assign o_ppu_ce = (i_cpu_addr[15:13] == 3'b001);

// APU/IO: $4000-$401F (Simplified: use the $4000 block)
assign o_acp_ce = (i_cpu_addr[15:5] == 11'b01000000000); 
assign o_io_ce = o_acp_ce; // Often tied together for $4000 range access

// SDRAM / Save RAM: $6000-$7FFF (Expansion RAM)
assign o_sdram_ce = (i_cpu_addr[15:13] == 3'b011);

// Cartridge (ROM/Mapper): $8000-$FFFF
assign o_cart_ce = i_cpu_addr[15];

// --- 2. Data Multiplexing (Read Operation) ---
// When the CPU reads (i_cpu_rnw=1), select the data input based on the active CE.
always @(*) begin
    if (!i_cpu_rnw) begin
        // CPU is writing, output is high impedance for a combinational multiplexer
        o_data_out_to_cpu = 8'hFF; // Open bus read default
    end else if (o_gppram_ce) begin
        o_data_out_to_cpu = i_gppram_data_in;
    end else if (o_ppu_ce) begin
        o_data_out_to_cpu = i_ppu_data_in;
    end else if (o_acp_ce) begin
        o_data_out_to_cpu = i_acp_data_in;
    end else if (o_io_ce) begin
        o_data_out_to_cpu = i_io_data_in;
    end else if (o_sdram_ce) begin
        o_data_out_to_cpu = i_sdram_data_in;
    end else if (o_cart_ce) begin
        o_data_out_to_cpu = i_cart_data_in;
    end else begin
        o_data_out_to_cpu = 8'hFF; // Default (Open bus behavior)
    end
end

endmodule