// ====================================================================
// GameTank Bus Control Unit (BCU)
// Handles address decoding and read-data arbitration for the CPU bus.
// ====================================================================
`default_nettype none

module BusControlUnit (
    // CPU Interface
    input wire [15:0] i_cpu_addr,
    input wire i_cpu_rnw,           // 1=Read, 0=Write

    // Peripheral Chip Enables (Outputs)
    output wire o_gppram_ce,        // $0000-$07FF (2KB RAM)
    output wire o_acp_ce,           // $2000-$3FFF (ACP MMIO/RAM)
    output wire o_ppu_ce,           // $4000-$4015 (PPU MMIO Registers)
    output wire o_io_ce,            // $4016-$4017 (Joypad/IO)
    output wire o_sdram_ce,         // $6000-$7FFF (Save RAM / Mapper RAM)
    output wire o_cart_ce,          // $8000-$FFFF (Cartridge/Mapper ROM)

    // Peripheral Data Inputs (Read Data)
    input wire [7:0] i_gppram_data_in,
    input wire [7:0] i_acp_data_in,
    input wire [7:0] i_ppu_data_in,
    input wire [7:0] i_io_data_in,
    input wire [7:0] i_sdram_data_in,
    input wire [7:0] i_cart_data_in,
    
    // CPU Data Output (Multiplexed Read Data)
    output reg [7:0] o_data_out_to_cpu
);

// --- 1. Address Decoding (Chip Enables) ---

// GPPRAM (2KB) - $0000-$07FF 
assign o_gppram_ce = (i_cpu_addr[15:11] == 5'b00000); 

// ACP (Audio CoProcessor) - $2000-$3FFF
assign o_acp_ce = (i_cpu_addr[15:12] == 4'h2) || (i_cpu_addr[15:12] == 4'h3);

// PPU MMIO - $4000-$4015
assign o_ppu_ce = (i_cpu_addr[15:8] == 8'h40) && (i_cpu_addr[7:5] == 3'b000); 

// I/O and Joypad - $4016-$4017
assign o_io_ce = (i_cpu_addr[15:1] == 15'h200B); 

// SDRAM Save RAM - $6000-$7FFF
assign o_sdram_ce = (i_cpu_addr[15:13] == 3'b011);

// Cartridge/Mapper ROM - $8000-$FFFF
assign o_cart_ce = i_cpu_addr[15];


// --- 2. Read Data Arbitration (Multiplexer) ---

// Selects which component drives the CPU's data input (DI) during a read cycle.
always @(*) begin
    // Default to an open bus state ($FF for 6502 family)
    o_data_out_to_cpu = 8'hFF; 

    if (i_cpu_rnw) begin // Only arbitrate during a read cycle
        if (o_gppram_ce) begin
            o_data_out_to_cpu = i_gppram_data_in;
        end else if (o_acp_ce) begin
            o_data_out_to_cpu = i_acp_data_in;
        end else if (o_ppu_ce) begin
            o_data_out_to_cpu = i_ppu_data_in; 
        end else if (o_io_ce) begin
            o_data_out_to_cpu = i_io_data_in; 
        end else if (o_sdram_ce) begin
            o_data_out_to_cpu = i_sdram_data_in; 
        end else if (o_cart_ce) begin
            o_data_out_to_cpu = i_cart_data_in; 
        end
    end
end

endmodule