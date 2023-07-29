// a simple sound level meter
// with max absolute value measurement every 64 samples

module sound_level (
    input clk,
    input ready,        // a sample is ready
    input signed [15:0] audio,
    output reg [7:0] level
);

localparam SAMPLES = 64;

reg [7:0] cnt = 8'b0;
reg [7:0] level_next = 8'b0;

always @(posedge clk) begin
    reg [7:0] a;
    a = (audio < 0 ? -audio : audio) >> 7;

    if (ready) begin
        cnt <= cnt + 1;
        if (cnt == SAMPLES - 1) begin
            cnt <= 0;
            level <= level_next;
            level_next <= a;
        end else begin
            if (a > level_next)
                level_next <= a;
        end
    end
end

endmodule