//-------------------------------------------------------------------------
// GameTank_test_top.v
// Top-level module combining WCD6502 CPU Stub and BSROM_Mapper.
//-------------------------------------------------------------------------

`timescale 1ns / 1ps

// --- 1. Top-Level Module Definition ---
module GameTank_test_top (
    input sys_clk,

    // Button S1 and pin 48 are both resets
    input s1,
    input reset2,

    // UART
    input UART_RXD,
    output UART_TXD,

    // LEDs
    output [7:0] led,

    // sgametank controllers
    output joy1_strb,
    output joy1_clk,
    input joy1_data,
    output joy2_strb,
    output joy2_clk,
    input joy2_data

    // HDMI TX
//    output tmds_clk_n,
//    output tmds_clk_p,
//    output [2:0] tmds_d_n,
//    output [2:0] tmds_d_p
) /*synthesis syn_keep=1*/;
    
    // --- Internal Wires/Signals for CPU Interface ---

    wire reset_n = ~reset2 /*synthesis syn_keep=1*/;
    
    // CPU Inputs (Active Low unless noted) - Not used by WCD6502, kept for compatibility
    wire nNMI  = 1'b1 /*synthesis syn_keep=1*/;
    wire nIRQ  = 1'b1 /*synthesis syn_keep=1*/;
    wire nSO   = 1'b1 /*synthesis syn_keep=1*/;
    wire RdyIn = 1'b1 /*synthesis syn_keep=1*/;
    
    // CPU Outputs (Not all are driven by WCD6502, but kept for full interface)
    wire nVP = 1'b1 /*synthesis syn_keep=1*/; // Not driven
    wire Sync = 1'b0 /*synthesis syn_keep=1*/; // Not driven
    wire nML = 1'b1 /*synthesis syn_keep=1*/; // Not driven
    wire [15:0] AB /*synthesis syn_keep=1*/;             // Address Bus
    wire nRD /*synthesis syn_keep=1*/;                   // Read Strobe (Active Low)
    wire nWR /*synthesis syn_keep=1*/;                   // Write Strobe (Active Low)

    // CPU Outputs (M65C02A legacy ports, left unconnected from WCD6502)
    wire [3:0] nCE = 4'b1111 /*synthesis syn_keep=1*/;
    wire [3:0] XA = 4'b0000 /*synthesis syn_keep=1*/;
    wire [1:0] nSSel;
    wire SCK;
    wire MOSI;
    wire COM0_TxD;
    wire COM1_nRTS;
    wire COM1_DE;

    // **Data Bus Wires**
    wire [7:0] cpu_db_out /*synthesis syn_preserve=1*/;  // Data driven BY the CPU (WCD6502.DB - Write Data)
    wire [7:0] DB_read_in /*synthesis syn_preserve=1*/;  // Data seen BY the CPU (WCD6502.DB_IN - Read Data)
    
    // **Stack Pointer Output from CPU Stub**
    wire [7:0] cpu_sp_out; 
    // **Instruction Register Output from CPU Stub**
    wire [7:0] cpu_ir_out; // New wire for Instruction Register

    // --- Mapper Control Wires ---
    wire rom_ce;    // Chip Enable for the ROM
    wire rom_rnw;   // Read/Not Write for the ROM (1=Read)
    wire [7:0] rom_data_out; // Data output from the ROM

    // --- 2. Minimal Bus Control Unit (BCU) Logic ---

    // 2a. ROM Selection (BSROM is now 32KB: $8000 - $FFFF)
    // The ROM is selected if A15 is high.
    assign rom_ce = AB[15];

    // 2b. Read/Not Write Signal (Active High for Read)
    // CPU reads when nRD is low. The mapper needs i_rnw high for a read.
    assign rom_rnw = !nRD; 

    // 2c. Data Bus Connection (Multiplexer Logic)
    // The CPU read input (DB_read_in) comes from either the ROM or a default value.
    // NOTE: Because the mapper output is now clocked (registered), the data will
    // be valid one clock cycle after the address is stable. We still connect it
    // directly here, assuming the CPU handles the delay or the tool handles the 
    // registered path correctly.
    assign DB_read_in = rom_data_out; // The mapper provides the 0xFF default when i_ce is low.
    
    // --- 3. Component Instantiation ---

    // 3a. Instantiate WCD6502 CPU Stub
    WCD6502 u_cpu (
        .Clk       (sys_clk),
        .nRst      (!reset_n),
        .AB        (AB),
        .DB        (cpu_db_out),      // CPU Write Data Output
        .nRD       (nRD),
        .nWR       (nWR),
        .DB_IN     (DB_read_in),      // CPU Read Data Input (fed from BCU/Mapper)
        .Status_SP (cpu_sp_out),       // Stack Pointer Status
        .Instruction_IR (cpu_ir_out) // New connection for Instruction Register
    );
    
    // 3b. Instantiate BSROM_Mapper
    BSROM_Mapper u_rom_mapper (
        .i_clk_cpu (sys_clk),
        .i_ce      (rom_ce),          // Connected via BCU logic
        .i_rnw     (rom_rnw),         // Connected via BCU logic
        .i_addr    (AB),              // Full Address Bus
        .o_data_out(rom_data_out)     // Data back to the BCU/CPU read bus
    );

    // --- 4. LED Assignments ---

    // Display the fetched Instruction Register (IR) value on all 8 LEDs.
    assign led = cpu_ir_out;

    /* Old LED assignments (commented out):
    // LED[0] monitors the state of the bus and the SP register (XOR of all bits)
    assign led[0] = 
                (|AB)^            // Address Bus
                (|nRD)^           // Read Strobe
                (|nWR)^           // Write Strobe
                (|cpu_db_out)^    // CPU Write Data
                (|DB_read_in)^    // CPU Read Data
                (|cpu_sp_out);    // Stack Pointer Value

    // LED[1-7] can show the status of the Stack Pointer
    assign led[7:1] = cpu_sp_out[6:0]; 
    */
    
    // Dummy connections for unused UART/SPI ports (required for synthesis if they are outputs)
    assign nSSel = 2'b11;
    assign SCK = 1'b0;
    assign MOSI = 1'b0;
    assign COM0_TxD = 1'b0;
    assign COM1_nRTS = 1'b1;
    assign COM1_DE = 1'b0;

    assign UART_TXD = COM0_TxD; 
    
endmodule