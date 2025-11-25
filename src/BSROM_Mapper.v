// `default_nettype none

module BSROM_Mapper (
    input wire i_clk_cpu,
    input wire i_ce,        // Chip Enable from BCU ($8000-$FFFF)
    input wire i_rnw,       // Read/Not Write (1=Read, 0=Write)
    input wire [15:0] i_addr, // Full CPU address
    // input wire [7:0] i_data_in, // Unused in NROM/BSROM (read-only)

    output reg [7:0] o_data_out
) /*synthesis syn_ramstyle="block_ram"*/;

// ROM size: 32KB (15-bit address, 8-bit data)
// Internal ROM array size is 32768 x 8 (indices 0 to 32767)
reg [7:0] prg_rom [32767:0] /*synthesis syn_ramstyle="block_ram"*/;

// Prg ROM Address calculation:
// 6502 addresses $8000-$FFFF (32KB). Base address $8000.
// We map the low 15 bits (A14:A0) directly to the ROM index.
wire [14:0] prg_addr = i_addr[14:0]; 

// Output is registered (D-Flip Flop on RAM output, typical for BRAM inference)
wire read_enable = (i_ce)&&(i_rnw);
always @(posedge i_clk_cpu) begin
    if(read_enable) begin
        // The output registers the data read from the ROM array
        o_data_out <= prg_rom[prg_addr];
    end else if (!i_ce) begin
        // If chip is not enabled, output float/default value (0xFF)
        // This 'else if' is important since we need to ensure the register
        // holds a defined value when not reading the ROM.
        o_data_out <= 8'hFF;
    end
end


// --- Initial Block to load the simple test program ---
initial begin
    
    // Program at $8000 (index 0):
    // The CPU stub is hardcoded to *simulate* PHA/PLA execution
    // but the mapper must still provide the correct opcodes for the fetch cycle.
    prg_rom[16'h8000 - 16'h8000] = 8'h48; // $8000: PHA (Push Accumulator)
    prg_rom[16'h8001 - 16'h8000] = 8'h68; // $8001: PLA (Pull Accumulator)
    prg_rom[16'h8002 - 16'h8000] = 8'hEA; // $8002: NOP

    // Reset Vector: $FFFC/$FFFD maps to indices 32764 and 32765
    // Set PC to start at $8000 (index 0)
    prg_rom[32764] = 8'h00; // $FFFC (Reset Vector Low - points to $8000)
    prg_rom[32765] = 8'h80; // $FFFD (Reset Vector High - points to $8000)

    // Fill the very end of the ROM
    prg_rom[32766] = 8'hEA; 
    prg_rom[32767] = 8'hEA; 
end

endmodule