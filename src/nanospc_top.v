
// Play SPC music through HDMI

module nanospc_top (
    input sys_clk,
    input s1,                       // s1 for next song
    input s2,                       // s2 for previous song

    // UART
    input UART_RXD,
    output UART_TXD,

    // HDMI TX
    output       tmds_clk_n,
    output       tmds_clk_p,
    output [2:0] tmds_d_n,
    output [2:0] tmds_d_p,

    // MicroSD
    output sd_clk,
    inout sd_cmd,      // MOSI
    input  sd_dat0,     // MISO
    output sd_dat1,     // 1
    output sd_dat2,     // 1
    output sd_dat3,     // 1

    // LED
    output [5:0] led

);

reg resetn = 1'b0;              // reset is cleared after 8 cycles
reg [2:0] resetcnt = 3'd7;
always @(posedge sys_clk) begin
    resetcnt <= resetcnt == 3'd0 ? 3'd0 : resetcnt - 1;
    if (resetcnt == 3'd0) 
        resetn <= 1'b1;
end

// Clock signals
wire hclk5;                     // 5x HDMI pixel clock
wire hclk;                      // 720p HDMI clock at 74.25Mhz
wire dclk;                      // DSP clock at 24.75Mhz, SMP/DSP operates on 1 in 6 phases

`ifndef VERILATOR

Gowin_rPLL_hdmi pll_hdmi (
    .clkin(sys_clk),
    .clkout(hclk5),
    .lock(pll_lock)
);

Gowin_CLKDIV clk_div (
    .clkout(hclk),
    .hclkin(hclk5),
    .resetn(resetn & pll_lock)
);

Gowin_rPLL_dsp pll_dsp (
    .clkin(sys_clk),
    .clkoutd(dclk),
    .clkout(), .clkoutp(), .lock()
);

`else

assign hclk = sys_clk;
assign dclk = sys_clk;

`endif

wire sdram_busy;
reg start = 1'b0;

wire smp_en, smp_we_n;
wire [15:0] smp_a;
wire [7:0] smp_do, smp_di;
wire [15:0] ram_a;
wire [7:0] ram_di, ram_do;
wire ram_wr;
wire lrck, bck, sdat;
wire [2:0] phase;
wire last_phase;

reg spc_ready = 1'b0;        // loaded and parsed
reg spc_reset = 1'b0;

// loading
reg loader_start;
wire loader_done, loader_fail;
reg [15:0] song;
wire [15:0] total;
wire [16:0] loader_addr;
wire [7:0] loader_dout;
wire loader_dout_valid;
wire [7:0] loader_debug;

// parsing
reg parser_start, parser_done;
wire parser_rd;
wire [16:0] parser_a;
wire cpu_dbg_wr, smp_dbg_wr;
wire [7:0] smpcpu_dbg_reg, smpcpu_dbg_din;
wire dsp_dbg_wr;
wire [7:0] dsp_dbg_reg, dsp_dbg_din;
wire [15:0] length;

// playing
reg [7:0] char_x;      // to hdmi_audio
reg [7:0] char_y;
reg [6:0] char;
reg char_valid;

// sound output
wire snd_rdy /*verilator public*/;
wire [15:0] audio_l /*verilator public*/, 
            audio_r /*verilator public*/;

SMP smp(
    .CLK(dclk), .RST_N(resetn & ~spc_reset), .ENABLE(spc_ready & smp_en & last_phase),
    .A(smp_a), .DI(smp_di), .DO(smp_do), .WE_N(smp_we_n),
    .PA(), .PARD_N(1'b1), .PAWR_N(1'b1), .CPU_DI(), .CPU_DO(),
    .CS(1'b0), .CS_N(1'b1),
    .DBG_REG(smpcpu_dbg_reg), .DBG_DAT_IN(smpcpu_dbg_din), .DBG_SMP_DAT(), .DBG_CPU_DAT(),
    .DBG_CPU_DAT_WR(cpu_dbg_wr), .DBG_SMP_DAT_WR(smp_dbg_wr), .BRK_OUT()
);

DSP dsp(
    .CLK(dclk), .RST_N(resetn & ~spc_reset), .ENABLE(spc_ready), .PHASE(phase), .LAST_PHASE(last_phase),
    .SMP_EN(smp_en), .SMP_A(smp_a), .SMP_DO(smp_do), .SMP_DI(smp_di),
    .SMP_WE_N(smp_we_n), .RAM_A(ram_a), .RAM_DI(ram_do), .RAM_DO(ram_di),
    .RAM_WR(ram_wr), .LRCK(), .BCK(), .SDAT(),
    .SND_RDY(snd_rdy), .AUDIO_L(audio_l), .AUDIO_R(audio_r),
    .DBG_REG(dsp_dbg_reg), .DBG_DAT_IN(dsp_dbg_din), .DBG_DAT_OUT(), .DBG_DAT_WR(dsp_dbg_wr)
);

test_aram aram(
    .clk(dclk), .a(ram_a), .dout(ram_do), .wr(ram_wr),
    .din(loader_dout_valid ? loader_dout : ram_di), 
    .spc_rd(parser_rd), .spc_wr(loader_dout_valid),
    .spc_a(parser_rd ? parser_a : loader_addr),
    .length(length), .fade()
);

spc_parser parser(
    .clk(dclk), .resetn(resetn), .start(parser_start), .done(parser_done),
    // to aram
    .parser_rd(parser_rd), .parser_a(parser_a), .aram_dout(ram_do),
    // to smp/cpu
    .cpu_dbg_wr(cpu_dbg_wr), .smp_dbg_wr(smp_dbg_wr),
    .smpcpu_dbg_reg(smpcpu_dbg_reg), .smpcpu_dbg_din(smpcpu_dbg_din),
    // to dsp
    .dsp_dbg_wr(dsp_dbg_wr), .dsp_dbg_reg(dsp_dbg_reg), .dsp_dbg_din(dsp_dbg_din)
);

localparam [2:0] INIT = 3'd0;
localparam [2:0] LOADING = 3'd1;
localparam [2:0] PARSING = 3'd2;
localparam [2:0] PLAYING = 3'd3;
reg [2:0] state = INIT;
reg [7:0] cnt;
reg timer_reset = 0;
reg [5:0] second, minute, ticks;
reg [15:0] played;      // in seconds
wire [7:0] second_bcd, minute_bcd, song_bcd, total_bcd;

bin2bcd b0 (.bin(second), .bcd(second_bcd));
bin2bcd b1 (.bin(minute), .bcd(minute_bcd));
bin2bcd b2 (.bin(song[6:0]+1), .bcd(song_bcd));
bin2bcd b3 (.bin(total[6:0]), .bcd(total_bcd));

always @(posedge dclk) begin
    if (~resetn) begin
        state <= INIT;
        song <= 0;
    end else begin
        parser_start <= 1'b0;
        loader_start <= 1'b0;
        timer_reset <= 0;
        case (state)
        INIT: begin
            spc_ready <= 1'b0;
            spc_reset <= 1'b1;      // reset to clear out any state
`ifndef VERILATOR
            loader_start <= 1'b1;
            state <= LOADING;
`else
            parser_start <= 1'b1;
            state <= PARSING;
`endif
        end
        LOADING: begin
            spc_reset <= 1'b0;
            if (loader_done) begin
                parser_start <= 1'b1;
                timer_reset <= 1;
                state <= PARSING;
            end
        end
        PARSING: begin
            spc_reset <= 1'b0;
            if (parser_done) begin
                spc_ready <= 1'b1;
                state <= PLAYING;
                timer_reset <= 1;
                cnt <= 0;
            end
        end
        PLAYING: begin
            if ((s1 || s2) && (played != 0) || played >= length[15:0]) begin      // ticks >= 5 to debounce
                spc_ready <= 1'b0;
                if (s2)     // previous song
                    song <= song == 0 ? total - 1 : song - 1;
                else        // next song
                    song <= song == total - 1 ? 0 : song + 1;
                state <= INIT;
            end

            // update status: 0 1 2 3 4 5 6 7 8 9 10 11 12
            //                N N / T T       M M :  S  S
            //                Song  Total     Minute Second
            cnt <= cnt + 1;     // 0 - 255
            char_valid <= 0;
            if (cnt[3] && cnt[7:4] < 13) begin
                char_valid <= 1;        // valid for 8 cycles
                char_y <= 8;
                char_x <= 19 + cnt[7:4];
                case (cnt[7:4])
                0: char <= song_bcd[7:4] + 48;    // convert to ASCII
                1: char <= song_bcd[3:0] + 48;
                2: char <= "/";
                3: char <= total_bcd[7:4] + 48;
                4: char <= total_bcd[3:0] + 48;
                8: char <= minute_bcd[7:4] + 48;
                9: char <= minute_bcd[3:0] + 48;
                10: char <= ":";
                11: char <= second_bcd[7:4] + 48;
                12: char <= second_bcd[3:0] + 48;
                default: char <= 0;
                endcase
            end
        end
        default: ;
        endcase
    end
end

// keep play time
localparam FREQ = 24_469_000;
reg [$clog2(FREQ/10)-1:0] tick_count;         
always @(posedge dclk) begin
    if (timer_reset) begin
        minute <= 0;
        second <= 0;
        played <= 0;
        ticks <= 0;
    end else begin
        if (tick_count == FREQ/10 - 1) begin
            tick_count = 0;
            if (ticks == 9) begin
                ticks <= 0;
                played <= played + 1;
                if (second == 59) begin
                    minute <= minute + 1;
                    second <= 0;
                end else 
                    second <= second + 1;
            end else
                ticks <= ticks + 1;
        end else
            tick_count <= tick_count + 1;
    end
end

`ifndef VERILATOR

sd_loader loader(
    .clk(dclk), .resetn(resetn), .start(loader_start), .num(song), .total(total),
    .dout(loader_dout), .addr(loader_addr), .dout_valid(loader_dout_valid),
    .done(loader_done), .fail(loader_fail),
    .sd_clk(sd_clk), .sd_cmd(sd_cmd), .sd_dat0(sd_dat0),
    .sd_dat1(sd_dat1), .sd_dat2(sd_dat2), .sd_dat3(sd_dat3),
    .dbg(loader_debug)
);

reg [15:0] audio_l_buf, audio_r_buf;

hdmi_audio hdmi (
	.clk(dclk), .resetn(resetn), .clk_pixel(hclk), .clk_5x_pixel(hclk5), 
    .audio_l(audio_l_buf), .audio_r(audio_r_buf),
    .char_x(char_x), .char_y(char_y), .char(char), .char_valid(char_valid),
	.tmds_clk_n(tmds_clk_n), .tmds_clk_p(tmds_clk_p), .tmds_d_n(tmds_d_n), .tmds_d_p(tmds_d_p)
);

always @(posedge dclk)
    if (snd_rdy) begin
        audio_l_buf <= audio_l;
        audio_r_buf <= audio_r;
    end

wire [7:0] level_l, level_r;
sound_level lmeter(.clk(dclk), .ready(snd_rdy), .audio(audio_l), .level(level_l));
sound_level rmeter(.clk(dclk), .ready(snd_rdy), .audio(audio_r), .level(level_r));
wire [8:0] level_lr = level_l + level_r;

wire lvl0 = level_lr[8:4] >= 5'd1;
wire lvl1 = level_lr[8:4] >= 5'd2;
wire lvl2 = level_lr[8:4] >= 5'd3;
wire lvl3 = level_lr[8:4] >= 5'd5;
wire lvl4 = level_lr[8:4] >= 5'd7;
wire lvl5 = level_lr[8:4] >= 5'd10;

// assign led = ~{lvl5, lvl4, lvl3, lvl2, lvl1, lvl0};
assign led = s2 ? ~loader_debug : ~{lvl5, lvl4, lvl3, lvl2, lvl1, lvl0};

`endif

endmodule
