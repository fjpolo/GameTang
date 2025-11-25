//-------------------------------------------------------------------------
// WCD6502.v
// Minimal WCD6502 CPU Stub for testing bus cycles, instruction fetch,
// and Stack Pointer (SP) manipulation (PHA and PLA instructions).
// Uses separate ports for read (DB_IN) and write (DB).
//-------------------------------------------------------------------------

`timescale 1ns / 1ps

module WCD6502 (
    input Clk,
    input nRst, // Active-low Reset

    // Bus Interface (CPU OUTPUTS)
    output reg [15:0] AB,    // Address Bus
    output reg [7:0] DB,     // Data Bus (CPU Write Data - Driven on write cycles)
    output reg nRD,          // Read Strobe (Low when CPU is reading)
    output reg nWR,          // Write Strobe (Low when CPU is writing)
    
    // Bus Interface (CPU INPUTS)
    input wire [7:0] DB_IN,  // Data Bus (CPU Read Data - Used on read cycles)

    // CPU Internal Status (minimal outputs)
    output [7:0] Status_SP
);

// --- Internal Registers ---
reg [15:0] PC;   // Program Counter
reg [7:0] A;     // Accumulator
reg [7:0] SP;    // Stack Pointer
reg [2:0] state; // Simple state counter for simulation

// --- Constants ---
// State machine for simulating instruction execution
localparam STATE_RESET_L = 3'd0;    // Read $FFFC (Reset Vector Low)
localparam STATE_RESET_H = 3'd1;    // Read $FFFD (Reset Vector High)
localparam STATE_FETCH_PHA = 3'd2;  // Fetch Opcode $48 (PHA)
localparam STATE_PUSH_PHA = 3'd3;   // Execute PHA (Stack write, SP--)
localparam STATE_FETCH_PLA = 3'd4;  // Fetch Opcode $68 (PLA)
localparam STATE_PULL_PLA = 3'd5;   // Execute PLA (Stack read, SP++)
localparam STATE_IDLE = 3'd6;       // Halt

// --- Outputs ---
assign Status_SP = SP;

// --- State and Bus Control Logic (Clocked) ---
always @(posedge Clk or negedge nRst) begin
    if (!nRst) begin
        // Reset sequence
        PC <= 16'hFFFF; 
        SP <= 8'hFD;    
        A <= 8'hAA;     // Test value for Push
        state <= STATE_RESET_L;
        
        // De-assert control signals
        nRD <= 1'b1;
        nWR <= 1'b1;
        DB <= 8'h00;
        AB <= 16'h0000;
    end else begin
        // Default: de-assert control signals
        nRD <= 1'b1;
        nWR <= 1'b1;
        
        case (state)
            STATE_RESET_L: begin
                // 1. Read Reset Vector Low Byte ($FFFC)
                AB <= 16'hFFFC;
                nRD <= 1'b0;
                state <= STATE_RESET_H;
            end
            
            STATE_RESET_H: begin
                // 2. Read Reset Vector High Byte ($FFFD)
                AB <= 16'hFFFD;
                nRD <= 1'b0;
                // PC is now set to $8000 (start of the 32KB ROM)
                PC <= 16'h8000; 
                state <= STATE_FETCH_PHA;
            end

            STATE_FETCH_PHA: begin
                // 3. Fetch PHA from $8000
                AB <= PC;
                PC <= PC + 1;
                nRD <= 1'b0;
                state <= STATE_PUSH_PHA;
            end

            STATE_PUSH_PHA: begin
                // 4. Execute PHA (Push Accumulator)
                // Write A to Stack: Address $0100 + SP
                AB <= {8'h01, SP}; 
                DB <= A;           
                nWR <= 1'b0;       
                
                // Decrement SP: 0xFD -> 0xFC
                SP <= SP - 1; 
                A <= 8'hFF; // Change A value
                state <= STATE_FETCH_PLA;
            end
            
            STATE_FETCH_PLA: begin
                // 5. Fetch PLA from $8001
                AB <= PC;
                PC <= PC + 1;
                nRD <= 1'b0;
                state <= STATE_PULL_PLA;
            end
            
            STATE_PULL_PLA: begin
                // 6. Execute PLA (Pull Accumulator)
                // Increment SP: 0xFC -> 0xFD
                SP <= SP + 1;
                
                // Read from Stack: Address $0100 + new SP (i.e., $01FD)
                AB <= {8'h01, SP + 1}; 
                nRD <= 1'b0;           
                
                // Update A with read value (A should become 0xAA)
                A <= DB_IN;
                state <= STATE_IDLE;
            end

            STATE_IDLE: begin
                // Halt
                AB <= 16'h0000;
                nRD <= 1'b1;
                nWR <= 1'b1;
                DB <= 8'h00;
            end
            
            default: state <= STATE_IDLE;
        endcase
    end
end
endmodule