// `default_nettype none

module BusControlUnit (
    input wire [15:0] i_cpu_addr,
    input wire i_cpu_rnw,

    // Chip Enables (Outputs)
    output reg o_gppram_ce, // $0000-$1FFF (2KB mirrored up to $1FFF)
    output reg o_acp_ce,    // $4000-$4017 (APU, Joypad, etc. - ACP region)
    output reg o_ppu_ce,    // $2000-$3FFF (PPU registers mirrored up to $3FFF)
    output reg o_io_ce,     // $4018-$FFFF (General IO / Cartridge)
    output reg o_sdram_ce,  // $6000-$7FFF (SRAM/External RAM)
    output reg o_cart_ce,   // $8000-$FFFF (Cartridge ROM)

    // Peripheral Data Inputs (Read Data to Multiplex)
    input wire [7:0] i_gppram_data_in,
    input wire [7:0] i_acp_data_in,
    input wire [7:0] i_ppu_data_in,
    input wire [7:0] i_io_data_in,
    input wire [7:0] i_sdram_data_in,
    input wire [7:0] i_cart_data_in,

    // CPU Data Output (Multiplexed Read Data)
    output reg [7:0] o_data_out_to_cpu
) /*synthesis syn_ramstyle="block_ram"*/;

// Combinational logic for Chip Enables and Data Multiplexing
always @* begin
    // Default assignments (inactive)
    o_gppram_ce = 1'b0;
    o_acp_ce    = 1'b0;
    o_ppu_ce    = 1'b0;
    o_io_ce     = 1'b0;
    o_sdram_ce  = 1'b0;
    o_cart_ce   = 1'b0;
    o_data_out_to_cpu = 8'hFF; // Open bus default (read only)

    // Only proceed if it's a read operation
    if (i_cpu_rnw) begin
        case (i_cpu_addr[15:13])
            // $0000-$1FFF: 2KB Internal RAM (Mirrored)
            3'b000, 3'b001: begin 
                o_gppram_ce = 1'b1;
                o_data_out_to_cpu = i_gppram_data_in;
            end
            
            // $2000-$3FFF: PPU Registers (Mirrored)
            3'b010, 3'b011: begin
                o_ppu_ce = 1'b1;
                o_data_out_to_cpu = i_ppu_data_in;
            end

            // $4000-$5FFF: APU/IO/Expansion
            3'b100: begin
                if (i_cpu_addr[15:5] == 11'b10000000000) begin // $4000-$401F
                    o_acp_ce = 1'b1; // ACP/APU/JOYPAD
                    o_data_out_to_cpu = i_acp_data_in; // NOTE: Needs proper multiplexing for $4015, $4016, $4017 reads
                end else begin // $4020-$5FFF (Mapper Space, usually unused/RAM)
                    // Currently mapping to general IO for simplicity, should map to Cartridge MMIO/Expansion
                    o_io_ce = 1'b1; 
                    o_data_out_to_cpu = i_io_data_in;
                end
            end

            // $6000-$7FFF: SRAM/External RAM (SDRAM)
            3'b101: begin
                o_sdram_ce = 1'b1;
                o_data_out_to_cpu = i_sdram_data_in;
            end

            // $8000-$FFFF: Cartridge ROM
            3'b110, 3'b111: begin
                o_cart_ce = 1'b1;
                o_data_out_to_cpu = i_cart_data_in;
            end

            default: o_data_out_to_cpu = 8'hFF; // Should be unreachable
        endcase
    end else begin
        // --- Write Operations ---
        case (i_cpu_addr[15:13])
            // $0000-$1FFF: 2KB Internal RAM (Mirrored)
            3'b000, 3'b001: o_gppram_ce = 1'b1;

            // $2000-$3FFF: PPU Registers (Mirrored)
            3'b010, 3'b011: o_ppu_ce = 1'b1;

            // $4000-$5FFF: APU/IO/Expansion
            3'b100: begin
                if (i_cpu_addr[15:5] == 11'b10000000000) begin // $4000-$401F
                    o_acp_ce = 1'b1; // ACP/APU/OAM-DMA ($4014)
                end else begin // $4020-$5FFF (Mapper Space)
                    o_io_ce = 1'b1;
                end
            end

            // $6000-$7FFF: SRAM/External RAM (SDRAM)
            3'b101: o_sdram_ce = 1'b1;

            // $8000-$FFFF: Cartridge ROM (Mapper writes for bank switching)
            3'b110, 3'b111: o_cart_ce = 1'b1;
        endcase
    end
end

endmodule