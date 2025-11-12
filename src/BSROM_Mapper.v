// Copyright (c) 2025-3025 @fjpolo
// This program is GPL Licensed. See COPYING for the full license.

// `default_nettype none

// Simple NROM-style mapper (Mapper 0) with 32KB of Program ROM (PRG-ROM).
// Handles the CPU address space $8000-$FFFF.
module BSROM_Mapper (
    input wire i_clk_cpu,
    input wire i_ce,        // Chip Enable ($8000-$FFFF)
    input wire i_rnw,       // Read/Not Write (1=Read, 0=Write)
    input wire [15:0] i_addr, // CPU Address Bus
    
    output wire [7:0] o_data_out // Data read back to CPU
);

// The PRG-ROM is typically 32KB (256 Kbits). 
// 32KB = 32768 bytes, addressed by 15 bits (A0-A14).
localparam PRG_ROM_SIZE = 32768; // 32KB
localparam PRG_ADDR_BITS = 15; // 0 to 32767

// Internal memory array to hold the ROM data
reg [7:0] prg_rom [PRG_ROM_SIZE-1:0];

// The ROM data is typically loaded from an external file in simulation:
initial begin
    // NOTE: This instruction is for simulators (like Verilator/Icarus) 
    // to load the ROM content from a file before running.
    // Replace "prg_rom_data.hex" with the actual path/name of your extracted PRG ROM data.
    $readmemh("hello.hex", prg_rom); 
end

// The BSROM mapper is combinatorial on read:
// When the CPU reads (i_rnw=1) and the chip is enabled (i_ce=1), 
// we access the ROM array. The PRG ROM is fixed, so we only need to look 
// at the lower 15 bits of the CPU address (A0-A14) to index the 32KB array.
// $8000 (1000 0000 0000 0000) maps to index 0 of the array.
wire [PRG_ADDR_BITS-1:0] rom_index;

// CPU address $8000-$FFFF needs to be mapped to PRG ROM indices $0000-$7FFF.
// The CPU address bit A15 is 1, so the index is based on A0-A14.
// For $8000, i_addr[14:0] = 0.
// For $FFFF, i_addr[14:0] = 15'h7FFF.
assign rom_index = i_addr[PRG_ADDR_BITS-1:0];

assign o_data_out = (i_ce && i_rnw) ? prg_rom[rom_index] : 8'hFF; 

endmodule