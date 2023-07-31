// BRAM-based ARAM implementation that also reads in an SPC file
// and exposes SMP/CPU and DSP initial register values
module test_aram(
    input clk,
    input [7:0] din, 
    output reg [7:0] dout,  // data output

    // aram interface
    input wr,               // 1: do write, 0: do read
    input [15:0] a,         // 64 KB ARAM

    // SPC loading/parser interface
    input spc_rd,
    input spc_wr,
    input [16:0] spc_a,   // access to entire SPC file

    // Meta-data for player
    output [15:0] length,   // binary in seconds
    output [15:0] fade      // binary in msec
);

reg [7:0] mem [0:256 + 65536 + 128 - 1];    // 256B of header + 64KB of ARAM + 127B of DSP ram
wire [16:0] addr = (spc_rd | spc_wr) ? spc_a : 17'(a) + 17'h100;
wire write = wr | spc_wr;

reg [15:0] int_length = 16'd20;
reg [15:0] int_fade = 16'd3000;
assign length = int_length;
assign fade = int_fade;

initial begin
    $readmemh("data/test_spc.spc.hex", mem);    // length will be default valid of 20 seconds
end

always @(posedge clk) begin
    if (write) 
        mem[addr] <= din;
    else
        dout <= mem[addr];
end

// Setting meta-data
always @(posedge clk) begin
    reg isDigit = din >= 8'h30 && din <= 8'h39;
    /* verilator lint_off WIDTH */
    if (write) begin
        if (addr == 17'ha9)
            int_length <= {8'h0, din-8'h30};
        else if ((addr == 17'haa || addr == 17'hab) && isDigit)
            int_length <= (int_length << 3) + (int_length << 1) + (din - 16'h30);
        else if (addr == 17'hac)
            int_fade <= {8'h0, din-8'h30};
        else if ((addr == 17'had || addr == 17'hae) && isDigit)
            int_fade <= (int_fade << 3) + (int_fade << 1) + (din - 8'h30);
    end
    /* verilator lint_on WIDTH */
end

endmodule