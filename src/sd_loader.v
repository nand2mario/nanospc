
// Load SPC files from SD card

module sd_loader #(
    parameter FREQ = 24_750_000
) (
    input clk,
    input resetn,

    input start,            // pulse to start loading
    input [15:0] num,       // song number to load (0-based)
    output reg [15:0] total,// total number of songs

    output reg [7:0] dout,  // SPC data
    output reg [16:0] addr, // address
    output reg dout_valid,  // pulse 1 when dout is valid

    output done,
    output reg fail,

    // SD card physical interface
    output sd_clk,
    inout  sd_cmd,      // MOSI
    input  sd_dat0,     // MISO
    output sd_dat1,     // 1
    output sd_dat2,     // 1
    output sd_dat3,     // 1

    output [7:0] dbg
);

// MicroSD
assign sd_dat1 = 1;
assign sd_dat2 = 1;
assign sd_dat3 = 1; // Must set sddat1~3 to 1 to avoid SD card from entering SPI mode

// state and wires
reg [31:0] magic;
reg sd_rstart = 0;
reg [23:0] sd_rsector;
wire sd_rdone;
wire sd_outen;
wire [7:0] sd_outbyte;
reg [8:0] sd_off;         // in-sector offset
reg sd_loading;
reg [16:0] int_addr;
reg int_done;

assign done = ~start & int_done;

sd_reader #(
    .CLK_DIV(3'd0), .SIMULATE(0)
) sd_reader_i (
    .rstn(resetn), .clk(clk),
    .sdclk(sd_clk), .sdcmd(sd_cmd), .sddat0(sd_dat0),
    .card_stat(),.card_type(),
    .rstart(sd_rstart), .rbusy(), .rdone(sd_rdone), .outen(sd_outen),
    .rsector({8'b0, sd_rsector}),
    .outaddr(), .outbyte(sd_outbyte)
);

// SD card loading process
reg [3:0] state;
localparam [3:0] SD_IDLE = 4'd0;
localparam [3:0] SD_READ_META = 4'd1;       // getting meta-data, starting from sector 0
localparam [3:0] SD_READ_SPC = 4'd2;
localparam [3:0] SD_FAIL = 4'd3;
localparam [3:0] SD_DONE = 4'd4;
always @(posedge clk) begin
    if (~resetn) begin
        state <= SD_IDLE;
        int_done <= 1'b0;
        fail <= 1'b0;
    end else begin
        dout_valid <= 1'b0;    
        case (state)
        SD_IDLE: begin
            if (start) begin
                int_done <= 1'b0;
                fail <= 1'b0;
                state <= SD_READ_META;
                sd_off <= 0;
                sd_rstart <= 1;     // start reading meta sector
                                    // not a pulse. SD controller requires it to be 1 the full duration
                sd_rsector <= 0;
            end
        end
        SD_READ_META: begin
            if (sd_outen) begin         // parse meta sector
                sd_off <= sd_off + 1;
                if (sd_off == 8'd0) magic[7:0] <= sd_outbyte;
                if (sd_off == 8'd1) magic[15:8] <= sd_outbyte;
                if (sd_off == 8'd2) magic[23:16] <= sd_outbyte;
                if (sd_off == 8'd3) magic[31:24] <= sd_outbyte;
                if (sd_off == 8'd4) total[7:0] <= sd_outbyte;
                if (sd_off == 8'd5) total[15:8] <= sd_outbyte;
            end
            if (sd_rdone) begin
                sd_rstart <= 1'b0;
                if (magic != 32'h20_43_50_53 || num >= total) begin        // "SPC " in reverse
                    state <= SD_FAIL;
                    fail <= 1'b1;
                end else begin
                    sd_rstart <= 1;
                    // every SPC file is 129 sectors
                    sd_rsector <= 24'd1 + (24'(num) << 7) + num;
                    int_addr <= 0;
                    state <= SD_READ_SPC;
                end
            end
        end
        SD_READ_SPC: begin
            if (int_addr == 17'h10200) begin
                sd_rstart <= 1'b0;
                int_done <= 1'b1;
                state <= SD_IDLE;
            end else begin
                if (sd_outen) begin
                    // output a byte
                    dout <= sd_outbyte;
                    dout_valid <= 1'b1;
                    addr <= int_addr;
                    int_addr <= int_addr + 1;
                end 
                if (sd_rdone) begin
                    // read next sector
                    sd_rstart <= 1;
                    sd_rsector <= sd_rsector + 24'd1;
                end                
            end
        end
        endcase
    end
end

assign dbg = {done, total[4:0]};

endmodule