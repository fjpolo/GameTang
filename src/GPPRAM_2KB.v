// Copyright (c) 2025-3025 @fjpolo
// This program is GPL Licensed. See COPYING for the full license.

// `default_nettype none

// Implementation of the 2KB CPU Working RAM ($0000-$07FF)
// Modeled as a synchronous Block RAM (BRAM).
module GPPRAM_2KB (
    input wire i_clk_cpu,
    input wire i_reset, // Synchronous reset (not used to clear the array)
    
    input wire i_ce,    // Chip Enable (Active High)
    input wire i_rnw,   // Read/Not Write (1=Read, 0=Write)
    input wire [10:0] i_addr, // 11 bits for 2KB (0 to 2047)
    input wire [7:0] i_data_in, // Data written by CPU
    
    output reg [7:0] o_data_out // Read data output (Synchronous, 1 cycle latency)
) /*synthesis syn_ramstyle="block_ram"*/;

// 2KB (2048 bytes) of RAM storage
reg [7:0] ram [((2*1024)-1):0] /*synthesis syn_ramstyle="block_ram"*/;

// Block RAM logic: Read and Write operations are synchronous to the clock.
wire write = (i_ce)&&(!i_rnw);
always @(posedge i_clk_cpu)
    if (write) 
            ram[i_addr] <= i_data_in;
always @(posedge i_clk_cpu)
        // Synchronous read: The output register is updated with the data at the address
        // one clock cycle after the address is stable and CE is high.
        o_data_out <= ram[i_addr];

endmodule