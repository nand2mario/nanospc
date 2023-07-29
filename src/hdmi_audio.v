// This outputs 32K stereo audio through HDMI while showing a grey screen

`timescale 1ns / 1ps

module hdmi_audio (
	input clk,      // snes clock
	input resetn,

    // audio signal
    input [15:0] audio_l,
    input [15:0] audio_r,

	// video clocks
	input clk_pixel,
	input clk_5x_pixel,

    // text interface
    input [7:0] char_x,     // 0 - 39
    input [7:0] char_y,     // 0 - 9
    input [6:0] char,       // ASCII
    input char_valid,       // pulse to write a character to text buffer

	// output signals
	output       tmds_clk_n,
	output       tmds_clk_p,
	output [2:0] tmds_d_n,
	output [2:0] tmds_d_p
);

    localparam VIDEOID = 3;             // 480p
    localparam CLKFRQ = 27000;
    localparam WIDTH = 720;
    localparam HEIGHT = 480;
    localparam VIDEO_REFRESH = 60;
//    localparam VIDEO_REFRESH = 59.94;

//    localparam VIDEOID = 4;             // 720P
//    localparam VIDEO_REFRESH = 60.0;
//    localparam WIDTH = 1280;
//    localparam HEIGHT = 720;
//    localparam CLKFRQ = 74250;

//    localparam VIDEOID = 1;             // VGA
//    localparam CLKFRQ = 25200;
//    localparam WIDTH = 640;
//    localparam HEIGHT = 480;
//    localparam VIDEO_REFRESH = 60;
//    

    localparam AUDIO_BIT_WIDTH = 16;

    wire [9:0] cy, frameHeight;
    wire [10:0] cx, frameWidth;
    reg [23:0] rgb;
    localparam AUDIO_RATE=32000;

    `include "font.vh"

    // Video
    reg [7:0] text[500];
                               //01234567890123456789012345678901234567890123456789
    initial text[ 50: 99] = {>>{"                             _____ ____  ______   "}};     // SystemVerilog streaming operator to unpack the string
    initial text[100:149] = {>>{"     ____  ____ _____  ____ / ___// __ \\/ ____/   "}};
    initial text[150:199] = {>>{"    / __ \\/ __ `/ __ \\/ __ \\\\__ \\/ /_/ / /        "}};
    initial text[200:249] = {>>{"   / / / / /_/ / / / / /_/ /__/ / ____/ /___      "}};
    initial text[250:299] = {>>{"  /_/ /_/\\__,_/_/ /_/\\____/____/_/    \\____/      "}};

    reg [6:0] c;
    reg [7:0] pattern;

    localparam [10:0] TEXT_X0 = WIDTH/2-25*8;           // X: 160~560
    localparam [10:0] TEXT_X1 = WIDTH/2+25*8;
    localparam [9:0] TEXT_Y0 = HEIGHT/2-5*8;            // Y: 200-280
    localparam [9:0] TEXT_Y1 = HEIGHT/2+5*8;
    always_ff @(posedge clk_pixel) begin
        rgb <= 24'h0;
        if (cx + 2 >= TEXT_X0 && cx < TEXT_X1 && cy >= TEXT_Y0 && cy < TEXT_Y1) begin
            reg [10:0] xoff = cx + 11'd2 - TEXT_X0;
            reg [9:0] yoff = cy - TEXT_Y0;              // 0 - 80
            if (cx[2:0] == 3'd6)                        // load character
                c <= text[(9'(yoff[6:3]) << 5) + (9'(yoff[6:3]) << 4) 
                     + (9'(yoff[6:3]) << 1) + 9'(xoff[8:3])][6:0];        // y * 50 + x
            if (cx[2:0] == 3'd7)                        // load char pattern
                pattern <= FONT[c][cy[2:0]];
            if (cx >= TEXT_X0 && pattern[cx[2:0]])      // render pixel
                rgb <= 24'hffff80;
            else
                rgb <= 24'h404040;
        end
    end

    // Audio
    reg [15:0] audio_sample_word [1:0], audio_sample_word0 [1:0];
    always @(posedge clk_pixel) begin       // crossing clock domain
        audio_sample_word0[0] <= audio_l;
        audio_sample_word[0] <= audio_sample_word0[0];
        audio_sample_word0[1] <= audio_r;
        audio_sample_word[1] <= audio_sample_word0[1];
    end

    localparam AUDIO_CLK_DELAY = CLKFRQ * 1000 / AUDIO_RATE / 2;
    logic [$clog2(AUDIO_CLK_DELAY)-1:0] audio_divider;
    logic clk_audio;
    always_ff@(posedge clk_pixel) 
    begin
        if (audio_divider != AUDIO_CLK_DELAY - 1) 
            audio_divider++;
        else begin 
            clk_audio <= ~clk_audio; 
            audio_divider <= 0; 
        end
    end

    // text display update
    reg char_valid_r, char_valid_rr;        // clock domain crossing
    always @(posedge clk_pixel) begin
        char_valid_r <= char_valid;
        char_valid_rr <= char_valid_r;
        if (char_valid_rr && ~char_valid_r) begin
            text[(9'(char_y) << 5) + (9'(char_y) << 4) + (9'(char_y) << 1) + 9'(char_x)] <= char;
        end
    end

    // HDMI output.
    logic[2:0] tmds;

    hdmi #( .VIDEO_ID_CODE(VIDEOID), 
            .DVI_OUTPUT(0), 
            .VIDEO_REFRESH_RATE(VIDEO_REFRESH),
            .IT_CONTENT(1),
            .AUDIO_RATE(AUDIO_RATE), 
            .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
            .START_X(0),
            .START_Y(0) )

    hdmi( .clk_pixel_x5(clk_5x_pixel), 
          .clk_pixel(clk_pixel), 
          .clk_audio(clk_audio),
          .rgb(rgb), 
          .reset( ~resetn ),
          .audio_sample_word(audio_sample_word),
          .tmds(tmds), 
          .tmds_clock(tmdsClk), 
          .cx(cx), 
          .cy(cy),
          .frame_width( frameWidth ),
          .frame_height( frameHeight ) );

    // Gowin LVDS output buffer
    ELVDS_OBUF tmds_bufds [3:0] (
        .I({clk_pixel, tmds}),
        .O({tmds_clk_p, tmds_d_p}),
        .OB({tmds_clk_n, tmds_d_n})
    );

endmodule
