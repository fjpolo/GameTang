// ACP_MMIO_Registers.v
// Handles the CPU interface for the Audio Co-Processor (ACP/APU) MMIO registers.
// Address range: $4000 - $4017.

module ACP_MMIO_Registers (
    input wire i_clk_cpu,           // CPU Clock
    input wire i_reset,             // System Reset (Active Low)

    input wire i_ce,                // Chip Enable (Active High: Address $4000-$401F)
    input wire i_rnw,               // Read/Not-Write (1=Read, 0=Write)
    input wire [4:0] i_addr,        // A0-A4 (Offset within $4000 block)
    input wire [7:0] i_data_in,     // Data written by CPU

    output wire [7:0] o_data_out,   // Data read by CPU
    output wire o_irq               // APU Interrupt Request to CPU
);

    // Register storage (16 registers: $4000-$400F, $4010-$4013, $4015, $4017)
    // We will use a simple array to model the writable registers.
    // Address [4:0] covers $4000 to $401F (32 addresses).
    reg [7:0] registers [31:0];

    // APU Status Register ($4015) read-back status
    reg [7:0] status_reg_read = 8'h00;
    // APU IRQ Flag
    reg r_irq = 1'b0;
    
    // Intermediate register for combinational read data
    reg [7:0] r_acp_read_data;

    // --- Synchronous Write Logic ---
    always @(posedge i_clk_cpu) begin
        if (~i_reset) begin
            // Reset logic simplified for stub
            r_irq <= 1'b0;
            // Note: Ideal reset would clear all registers[x] to 0
        end else if (i_ce && ~i_rnw) begin
            // Write operation
            case (i_addr)
                // $4000-$400F (Pulse 1, 2, Triangle, Noise, DMC registers)
                5'h00, 5'h01, 5'h02, 5'h03, 5'h04, 5'h05, 5'h06, 5'h07,
                5'h08, 5'h0A, 5'h0B, 5'h0C, 5'h0E, 5'h0F:
                    registers[i_addr] <= i_data_in;

                // $4015: APU Status/Control Write (e.g., enable/disable channels)
                5'h15: registers[5'h15] <= i_data_in;

                // $4017: Frame Counter Control
                5'h17: registers[5'h17] <= i_data_in;

                // $4014 and $4016 handled elsewhere or ignored here
                default: ;
            endcase
        end
    end

    // --- Combinational Read Logic ---
    // Use always @(*) to multiplex the data for read access
    always @(*) begin
        // Default read value if address is not explicitly handled
        r_acp_read_data = 8'h00; 
        
        case (i_addr)
            // $4015: APU Status Read (Read-only register status)
            5'h15: r_acp_read_data = status_reg_read; 

            // Example: reading back a written register (e.g., $4000 Pulse 1 Duty/Envelope)
            5'h00: r_acp_read_data = registers[5'h00];
            
            // Add other specific register reads here as needed
            // Default case handles unmapped and read-as-zero registers
            default: r_acp_read_data = 8'h00; 
        endcase
    end

    // --- Final Output Assignment (Continuous) ---
    // If CE is high AND it's a Read, output the decoded data, otherwise output open bus $FF.
    assign o_data_out = (i_ce && i_rnw) ? r_acp_read_data : 8'hFF;

    // Output connections
    assign o_irq = r_irq;

endmodule