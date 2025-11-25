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
    input [7:0] DB_IN,       // Data Bus (CPU Read Data - Used on read cycles)

    // CPU Internal Status (minimal outputs)
    output [7:0] Status_SP
);

// --- Internal Registers ---
reg [15:0] PC;   // Program Counter
reg [7:0] A;     // Accumulator
reg [7:0] SP;    // Stack Pointer
reg [2:0] state; // Simple state counter for simulation

// --- Constants ---
localparam STATE_RESET_L = 3'd0;
localparam STATE_RESET_H = 3'd1;
localparam STATE_FETCH_PHA = 3'd2;
localparam STATE_PUSH_PHA = 3'd3;
localparam STATE_FETCH_PLA = 3'd4;
localparam STATE_PULL_PLA = 3'd5;
localparam STATE_IDLE = 3'd6;

// --- Outputs ---
assign Status_SP = SP;

// --- State and Bus Control Logic (Clocked) ---
always @(posedge Clk or negedge nRst) begin
    if (!nRst) begin
        // Reset sequence
        PC <= 16'hFFFF; // Start search at FFFC/FFFD
        SP <= 8'hFD;    // Typical 6502 initial SP
        A <= 8'hAA;     // Set A for testing Push
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
                // Read Reset Vector Low Byte ($FFFC)
                AB <= 16'hFFFC;
                nRD <= 1'b0;
                state <= STATE_RESET_H;
            end
            
            STATE_RESET_H: begin
                // Read Reset Vector High Byte ($FFFD)
                // PC gets the vector: PC = {DB_IN (H), DB_IN (L)}
                PC <= {DB_IN, AB[7:0]}; // Dummy assignment for PC since we don't track the low byte read
                AB <= 16'hFFFD;
                nRD <= 1'b0;
                state <= STATE_FETCH_PHA;
            end

            STATE_FETCH_PHA: begin
                // Fetch PHA (Opcode $48)
                AB <= PC;
                PC <= PC + 1;
                nRD <= 1'b0;
                state <= STATE_PUSH_PHA; // Next state will execute the instruction
            end

            STATE_PUSH_PHA: begin
                // Execute PHA (Push Accumulator)
                // 1. Write A to (0x0100 + SP)
                AB <= {8'h01, SP}; // Address is 01xx, where xx is SP
                DB <= A;           // Write A's value
                nWR <= 1'b0;       // Assert Write Strobe
                
                // 2. Decrement SP
                SP <= SP - 1; 
                A <= 8'hFF;        // Change A to prove the push worked
                state <= STATE_FETCH_PLA;
            end
            
            STATE_FETCH_PLA: begin
                // Fetch PLA (Opcode $68)
                AB <= PC;
                PC <= PC + 1;
                nRD <= 1'b0;
                state <= STATE_PULL_PLA; // Next state will execute the instruction
            end
            
            STATE_PULL_PLA: begin
                // Execute PLA (Pull Accumulator)
                // 1. Increment SP
                SP <= SP + 1;
                
                // 2. Read from (0x0100 + SP)
                AB <= {8'h01, SP + 1}; // Address is 01xx, where xx is the *new* SP
                nRD <= 1'b0;           // Assert Read Strobe
                
                // 3. Update A with read value
                A <= DB_IN;
                state <= STATE_IDLE;
            end

            STATE_IDLE: begin
                // CPU Halted
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