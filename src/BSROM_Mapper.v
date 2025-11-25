// `default_nettype none

module BSROM_Mapper (
    input wire i_clk_cpu,
    input wire i_ce,        // Chip Enable from BCU ($8000-$FFFF)
    input wire i_rnw,       // Read/Not Write (1=Read, 0=Write)
    input wire [15:0] i_addr, // Full CPU address
    // input wire [7:0] i_data_in, // Unused in NROM/BSROM (read-only)

    output wire [7:0] o_data_out
) /*synthesis syn_ramstyle="block_ram"*/;

// ROM size: 32KB (15-bit address, 8-bit data)
// Address Range: $8000 - $FFFF (32KB)
// Internal ROM array size is 32768 x 8
reg [7:0] prg_rom [8191:0] /*synthesis syn_ramstyle="block_ram"*/;

// Prg ROM Address calculation:
// The 6502 addresses $8000-$FFFF (32KB). This maps directly to indices 0-32767.
// We mask off the A15 bit, as $8000 (1000 0000 0000 0000) corresponds to index 0.
wire [14:0] prg_addr = i_addr[14:0]; 

// Output is combinational (Read happens immediately)
assign o_data_out = (i_ce && i_rnw) ? prg_rom[prg_addr] : 8'hFF;


// --- Initial Block to load the simple test program ---
// The $readmemh function loads the hex data into the Verilog array.
// It loads data from the index corresponding to the CPU address $8000 up to $FFFF.
initial begin
  prg_rom[0] = 8'hA9; prg_rom[1] = 8'h60; prg_rom[2] = 8'h8D; prg_rom[3] = 8'h07; prg_rom[4] = 8'h20; prg_rom[5] = 8'h9C; prg_rom[6] = 8'h05; prg_rom[7] = 8'h20; 
  prg_rom[8] = 8'hA9; prg_rom[9] = 8'h00; prg_rom[10] = 8'hA2; prg_rom[11] = 8'h00; prg_rom[12] = 8'h9D; prg_rom[13] = 8'h00; prg_rom[14] = 8'h50; prg_rom[15] = 8'hE8; 
  prg_rom[16] = 8'h4C; prg_rom[17] = 8'h0C; prg_rom[18] = 8'hE0; prg_rom[19] = 8'h40; prg_rom[20] = 8'h40;
  prg_rom[8186] = 8'h14;
  prg_rom[8186] = 8'h14;
  prg_rom[8187] = 8'hE0;
  prg_rom[8188] = 8'h00;
  prg_rom[8189] = 8'hE0;
  prg_rom[8190] = 8'h13;
  prg_rom[8191] = 8'hE0;

end


endmodule
