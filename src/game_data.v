// zf: Feed IGAMETANK data to Game_Loader
module GameData (
    input clk, 
    input reset, 
    output reg downloading,
    output reg [7:0] odata, 
    output reg odata_clk
);

// 24KB+ buffer for ROM
localparam IGAMETANK_SIZE = 28688; // 28KB + 16
initial $readmemh("roms/gametank15.hex", IGAMETANK);
// localparam IGAMETANK_SIZE = 24592; // 24KB + 16
// initial $readmemh("roms/helloworld.hex", IGAMETANK);

reg [7:0] IGAMETANK[IGAMETANK_SIZE:0];
reg [1:0] state = 0;
reg [$clog2(IGAMETANK_SIZE)-1:0] addr = 0;
reg out_clk = 0;

reg [1:0] cnt;

always @(posedge clk) begin
    if (reset) begin
        state <= 0;
        addr <= 0;  // odata gets IGAMETANK[0]
        odata_clk <= 0;
    end else if (state == 0) begin
        // start loading
        state <= 1;
        downloading <= 1;
        cnt <= 0;
    end else if (state==1) begin
        cnt <= cnt + 1;
        odata_clk <= 0;
        case (cnt)
        2'd0: begin
            // Output one byte to Game_Loader
            odata <= IGAMETANK[addr];
            odata_clk <= 1;
        end
        2'd3: begin
            if (addr == IGAMETANK_SIZE-1) begin        // done
                state <= 2;
                downloading <= 0;
            end
            addr <= addr + 1;
        end
        default: ;
        endcase
    end
end

endmodule
