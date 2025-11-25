//-------------------------------------------------------------------------
// GameTank_test_top.v
// Top-level module combining WCD6502 CPU Stub.
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
    
    // CPU Inputs (Active Low unless noted)
    wire nNMI /*synthesis syn_keep=1*/;
    wire nIRQ /*synthesis syn_keep=1*/;
    wire nSO /*synthesis syn_keep=1*/;
    wire RdyIn /*synthesis syn_keep=1*/;
    
    // CPU Outputs
    wire nVP /*synthesis syn_keep=1*/;
    wire Sync /*synthesis syn_keep=1*/;
    wire nML /*synthesis syn_keep=1*/;
    wire [15:0] AB /*synthesis syn_keep=1*/;             // Address Bus
    wire [3:0] nCE /*synthesis syn_keep=1*/;             // Decoded Chip Selects
    wire nRD /*synthesis syn_keep=1*/;                   // Read Strobe (Active Low)
    wire nWR /*synthesis syn_keep=1*/;                   // Write Strobe (Active Low)
    wire [3:0] XA /*synthesis syn_keep=1*/;              // Extended Physical Address

    // **Data Bus Wires**
    wire [7:0] cpu_db_out /*synthesis syn_preserve=1*/;  // Data driven BY the CPU (WCD6502.DB)
    wire [7:0] DB_read_in /*synthesis syn_preserve=1*/;  // Data seen BY the CPU (WCD6502.DB_IN)
    
    // **NEW: Stack Pointer Output from CPU Stub**
    wire [7:0] cpu_sp_out; 

    // --- Signals for I/O Port Stubs (M65C02A legacy ports, now unused) ---
    // The WCD6502 stub does NOT support these ports, but we keep the wires for LED monitoring.
    wire [1:0] nSSel;
    wire SCK;
    wire MOSI;
    wire COM0_TxD;
    wire COM1_nRTS;
    wire COM1_DE;


    // --- Test Harness Initialization (Dummy Signals) ---
    // Set unused CPU inputs to safe/inactive values
    assign nNMI  = 1'b1;  // De-assert NMI
    assign nIRQ  = 1'b1;  // De-assert IRQ
    assign nSO   = 1'b1;  // De-assert Set Overflow
    assign RdyIn = 1'b1;  // Ready to drive bus (No wait states)
    
    // Tie unused input ports to safe values
    wire COM0_nCTS = 1'b1;
    wire COM1_nCTS = 1'b1;
    wire MISO = 1'b1;
    assign UART_TXD = COM0_TxD; 
    wire COM1_TxD_dummy; 

    // --- 2. Memory/Peripheral Stub (Replaces Arbiter Logic) ---
    
    // ROM Stub: Connect the CPU's read input to a constant for the reset vector.
    assign DB_read_in = 8'hFF; 

    
    // --- 3. Component Instantiation ---

    // 3a. Instantiate WCD6502 CPU Stub (Replaces M65C02A)
    WCD6502 u_cpu (
        // Clock and Reset
        .Clk   (sys_clk),
        .nRst  (!reset_n), // Map active-low i_rst_n to nRst
        
        // Bus Interface (Outputs)
        .AB    (AB),
        .DB    (cpu_db_out),      // CPU Write Data Output (was DB)
        .nRD   (nRD),
        .nWR   (nWR),
        
        // Bus Interface (Inputs)
        .DB_IN (DB_read_in),      // CPU Read Data Input (was DB_IN)
        
        // CPU Status
        .Status_SP (cpu_sp_out)   // NEW: Stack Pointer output
        
        // WCD6502 does not have the other ports (nNMI, nIRQ, nVP, etc.)
    );
    
    // --- 4. LED Assignment Update (Monitor SP) ---

    // LED[0] now XORs all major bus and control signals, including the new Stack Pointer (cpu_sp_out).
    assign led[0] = 
                (|nVP)^           // (CPU Outputs)
                (|Sync)^
                (|nML)^
                (|AB)^            // Address Bus
                (|nRD)^           // Read Strobe
                (|nWR)^           // Write Strobe
                (|cpu_db_out)^    // Write data
                (|DB_read_in)^    // Read data
                (|cpu_sp_out);    // **NEW: Stack Pointer Value**

    // The following signals are not driven by WCD6502, so their contribution to led[0] 
    // is based on their assigned values (mostly 1'b1 or unconnected wires, which default to 'z' or '0').
    // We remove them to reflect the minimal connections of the WCD6502 stub.
    /*
                (|nCE)^
                (|XA)^
                (|nSSel)^
                (|SCK)^
                (|MOSI)^
                (|COM0_TxD)^
                (|COM1_nRTS)^
                (|COM1_DE);
    */
    
endmodule