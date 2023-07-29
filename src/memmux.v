// Multiplex access for WRAM and cartridge through a single SDRAM.
// This also allows the loader to fill in cartridge memory.
//
// SDRAM allocation (22-bit address)
// 0      - 5fffff: Cartridge ROM (6MB)
// 7b0000 - 7bffff: ARAM  (64KB)
// 7c0000 - 7dffff: BSRAM (cartridge SRAM) (128KB)
// 7e0000 - 7fffff: WSRAM (128KB)

module memmux #(
    parameter FREQ = 64_800_000
)(
    input fclk,
    input clk_sdram,
    input resetn,
    input phase1,
    input phase2,

    input enable,

    // Cartridge and wram
    input [23:0] ca,
    input cpurd_n,
    input cpuwr_n,
    input [7:0] pa,
    input pard_n,
    input pawr_n,
    output [7:0] snes_di,
    input [7:0] snes_do,
    input ramsel_n,
    input romsel_n,
    input [7:0] wram_di,
    output [7:0] wram_do,

    // ARAM
    // TODO

    // SD Loader
    input [7:0] loader_map_ctrl,
    input [7:0] loader_rom_size,
    input [23:0] loader_rom_mask,
    input [23:0] loader_bsram_mask,
    input [7:0] loader_do,
    input loader_do_valid,
    input loader_done,
    output reg loader_fail = 1'b0,

    output busy,            // operation in progress

    input [7:0] dbg_reg,
    output reg [7:0] dbg_dat_out,

    // Physical SDRAM interface
	inout  [31:0] sdram_dq,   // 16 bit bidirectional data bus
	output [10:0] sdram_a,    // 13 bit multiplexed address bus
	output [1:0] sdram_ba,   // 4 banks
	output sdram_cs_n,       // a single chip select
	output sdram_we_n,  // write enable
	output sdram_ras_n, // row address select
	output sdram_cas_n, // columns address select
	output sdram_clk,
	output sdram_cke,
    output [3:0] sdram_dqm
);

reg [22:0] cart_addr, loader_addr = ~23'b0, loader_addr_end = 23'h7f_ffff;
reg cart_rd, cart_wr;
reg [7:0] cart_byte;

wire [16:0] wram_addr;
reg wram_rd, wram_wr;

reg loader_wr;
reg [7:0] loader_data;

reg refresh = 1'b0;

wire mem_rd = wram_rd | cart_rd;
wire mem_wr = loader_wr | wram_wr | cart_wr;
wire wram_read_write = (wram_rd | wram_wr) & ~busy;
wire cart_read_write = (cart_rd | cart_wr) & ~busy;
wire [22:0] mem_addr = loader_wr ? loader_addr :
                       cart_read_write ? cart_addr :
                       {6'b111_111, wram_addr};
wire [7:0] mem_di = loader_wr ? loader_data : 
                    cart_read_write ? snes_do :
                    wram_di;
wire [7:0] mem_do;
assign wram_do = mem_do;
assign snes_di = mem_do;

reg [23:0] WMADD;
reg PHASE_1r = 1'b0;

// Cartridge read and bsram read/write
reg [22:0] cart_full_addr;
always @* begin
    case(loader_map_ctrl[3:0])
    4'h0 :
      // LoROM
      cart_full_addr = {1'b0,ca[22:16],ca[14:0]};
    4'h1 :
      // HiROM
      cart_full_addr = {1'b0,ca[21:0]};
    4'h5 :
      // ExHiROM
      cart_full_addr = { ~ca[23],ca[21:0]};
    default :
      cart_full_addr = { ~ca[23],ca[21:0]};
    endcase
end

// Actual cartridge ROM and BSRAM process
reg [23:0] rom_read_cnt = 24'b0;             // operation counters
reg [23:0] wram_read_cnt = 24'b0;
reg [23:0] wram_write_cnt = 24'b0;
reg [23:0] bsram_read_cnt = 24'b0;
reg [23:0] bsram_write_cnt = 24'b0;

reg [7:0] trace_cnt = 8'b0;
reg trace_op[0:15];     // 0 for read, 1 for write
reg [22:0] trace_addr [0:15];
reg [7:0] trace_data [0:15];

// clock domain crossing
reg phase1r, phase2r;
always @(posedge fclk) begin
    phase1r <= phase1;
    phase2r <= phase2;
end

// generate cart_rd/wr and cart_addr
always @(posedge fclk) begin
    cart_rd <= 1'b0; cart_wr <= 1'b0;
    if (enable && phase1 && ~phase1r) begin
        // memory operations in phase 1
        if (~romsel_n && (~cpurd_n || ~cpuwr_n)) begin
            // ROM: 000000 - 5fffff
            cart_addr <= cart_full_addr & loader_rom_mask[22:0];
            cart_rd <= ~cpurd_n;
            if (~cpurd_n) rom_read_cnt <= rom_read_cnt + 1;
        end else if (~ramsel_n && (~cpurd_n || ~cpuwr_n)) begin
            if (ca[23:17] == 7'b0111111) begin
                // WRAM: wram_rd / wram_wr will be 1, nothing to do here
            end else begin
                // BSRAM: 7c0000 - 7dffff
                cart_addr <= {6'b111_110, cart_full_addr[16:0] & loader_rom_mask[16:0]};
                cart_rd <= ~cpurd_n;
                cart_wr <= ~cpuwr_n;
                if (~cpuwr_n) cart_byte <= snes_do;
                if (~cpurd_n) bsram_read_cnt <= bsram_read_cnt + 1;
                if (~cpuwr_n) bsram_write_cnt <= bsram_write_cnt + 1;
            end
        end
    end
end

// WRAM accesses
reg [23:0] wmadd;
wire wram_next_rd = pa == 8'h80 ? ~pard_n : 
                    ca[23:17] == 7'b0111111 ? ~cpurd_n : 1'b0;
wire wram_next_wr = pa == 8'h80 ? ~pawr_n : 
                    ca[23:17] == 7'b0111111 ? ~cpuwr_n : 1'b0;
assign wram_addr = pa == 8'h80 ? wmadd[16:0] : ca[16:0];

always @(posedge fclk) begin
    if(resetn == 1'b0) begin
        wmadd <= 24'b0;
    end else begin
        wram_rd <= 1'b0;     // ensure pulses
        wram_wr <= 1'b0;

        if (enable & phase1 & ~phase1r) begin   // start of phase 1
            if(pawr_n == 1'b0) begin
                case(pa)
                8'h80 : 
                    wmadd <= wmadd + 24'b1;
                8'h81 :
                    wmadd[7:0] <= snes_do;
                8'h82 :
                    wmadd[15:8] <= snes_do;
                8'h83 :
                    wmadd[23:16] <= snes_do;
                default : ;
                endcase
            end else if(pard_n == 1'b0) begin
                case(pa)
                8'h80 : 
                    wmadd <= wmadd + 24'b1;
                default : ;
                endcase
            end
            wram_rd <= wram_next_rd;
            wram_wr <= wram_next_wr;
        end
    end
end

always @(posedge fclk) begin
    if (wram_rd) wram_read_cnt <= wram_read_cnt + 1;
    if (wram_wr) wram_write_cnt <= wram_write_cnt + 1;
end

// refresh
reg [3:0] loader_refresh_cnt = 4'd15;
reg [23:0] refresh_cnt = 24'b0;
always @(posedge fclk) begin
    refresh <= 1'b0;
    if (loader_done) begin
        if (phase1 && ~phase1r) 
            refresh <= ~enable | (cpurd_n & cpuwr_n & ~wram_next_rd & ~wram_next_wr);
    end else if (loader_refresh_cnt == 4'd7 || loader_refresh_cnt == 4'd14) 
        // do a refresh 7 and 14 cycles after a loader byte
        // we need 15us refresh interval
        // assuming 1mb baudrate, bytes come in 10us intervals, so should be enough
        refresh <= 1'b1;
    
    if (refresh) refresh_cnt <= refresh_cnt + 24'b1;
end

// Loading cartridge from sd card
reg loader_do_valid_r;
wire [22:0] next_loader_addr = loader_addr + 23'b1;
always @(posedge fclk) begin
    if (~resetn) begin
        loader_addr <= ~23'b0;
        loader_do_valid_r <= 1'b0;
        loader_addr_end <= 23'h7f_ffff;     // max 8MB of rom
    end else begin
        loader_do_valid_r <= loader_do_valid;
        loader_wr <= 1'b0;
        loader_refresh_cnt <= loader_refresh_cnt == 4'd15 ? loader_refresh_cnt : loader_refresh_cnt + 4'd1;
        if (loader_do_valid && ~loader_do_valid_r && next_loader_addr != loader_addr_end) begin
            if (busy)               // data is coming too fast
                loader_fail <= 1'b1;
            loader_wr <= 1'b1;
            loader_data <= loader_do;
            loader_addr <= loader_addr + 23'b1;
            loader_refresh_cnt <= 4'b0;
            loader_addr_end <= 23'h400 << loader_rom_size;      // 1KB << loader_size
        end
    end
end

// debug tracing - record all non-loader reads and writes
reg [2:0] trace_cycle = 3'd7;
reg trace_rd = 1'b0; 
always @(posedge fclk) begin
    trace_cycle <= trace_cycle == 3'd7 ? trace_cycle : trace_cycle + 3'b1;
    if ((mem_rd || mem_wr) && ~loader_wr && trace_cycle == 3'd7 && trace_cnt <= 8'd15) begin
        trace_addr[trace_cnt[3:0]] <= mem_addr;
        trace_cycle <= 3'b1;
        trace_rd <= mem_rd;
        trace_op[dbg_reg[5:2]] <= mem_wr ? 1'b1 : 1'b0;
    end
    if (trace_cycle == 3'd4) begin
        trace_data[trace_cnt[3:0]] <= trace_rd ? mem_do : 8'b0;
        trace_rd <= 1'b0;
        trace_cnt <= trace_cnt + 8'b1;
    end
end

always @* begin
    casez (dbg_reg)
    8'h00: dbg_dat_out = loader_addr[7:0];
    8'h01: dbg_dat_out = loader_addr[15:8];
    8'h02: dbg_dat_out = {1'b0, loader_addr[22:16]};

    8'h03: dbg_dat_out = wram_read_cnt[7:0];
    8'h04: dbg_dat_out = wram_read_cnt[15:8];
    8'h05: dbg_dat_out = wram_read_cnt[23:16];
    8'h06: dbg_dat_out = wram_write_cnt[7:0];
    8'h07: dbg_dat_out = wram_write_cnt[15:8];
    8'h08: dbg_dat_out = wram_write_cnt[23:16];

    8'h09: dbg_dat_out = rom_read_cnt[7:0];
    8'h0a: dbg_dat_out = rom_read_cnt[15:8];
    8'h0b: dbg_dat_out = rom_read_cnt[23:16];

    // 8'h0c: dbg_dat_out <= bsram_read_cnt[7:0];
    // 8'h0d: dbg_dat_out <= bsram_read_cnt[15:8];
    // 8'h0e: dbg_dat_out <= bsram_read_cnt[23:16];
    // 8'h0f: dbg_dat_out <= bsram_write_cnt[7:0];
    // 8'h10: dbg_dat_out <= bsram_write_cnt[15:8];
    // 8'h11: dbg_dat_out <= bsram_write_cnt[23:16];

    8'h12: dbg_dat_out = trace_cnt;
    8'h13: dbg_dat_out = ca[7:0];
    8'h14: dbg_dat_out = ca[15:8];
    8'h15: dbg_dat_out = ca[23:16];
    8'h16: dbg_dat_out = snes_di;
    8'h17: dbg_dat_out = snes_do;

    // memmux status word
    8'h18: dbg_dat_out = {loader_fail, loader_do_valid, wram_rd, wram_wr, cpurd_n, cpuwr_n, ramsel_n, romsel_n};
    8'h19: dbg_dat_out = {4'b0, enable, refresh, mem_rd, mem_wr};
    8'h1a: dbg_dat_out = mem_di;
    8'h1b: dbg_dat_out = mem_do;
    8'h1c: dbg_dat_out = mem_addr[7:0];
    8'h1d: dbg_dat_out = mem_addr[15:8];
    8'h1e: dbg_dat_out = {1'b0, mem_addr[22:16]};

    // refresh statistics
    8'h20: dbg_dat_out = refresh_cnt[7:0];
    8'h21: dbg_dat_out = refresh_cnt[15:8];
    8'h22: dbg_dat_out = refresh_cnt[23:16];

    // memory access traces
    8'b10??_??00:           // 80-82: read_addr0, 83: read_data0
                            // 84-86: read_addr1, 87: read_data1 ...
        dbg_dat_out = trace_addr[dbg_reg[5:2]][7:0];
    8'b10??_??01:
        dbg_dat_out = trace_addr[dbg_reg[5:2]][15:8];
    8'b10??_??10:
        dbg_dat_out = {trace_op[dbg_reg[5:2]], trace_addr[dbg_reg[5:2]][22:16]};
    8'b10??_??11:
        dbg_dat_out = trace_data[dbg_reg[5:2]];

    default: 
        dbg_dat_out = 8'b0;
    endcase
end


`ifndef VERILATOR

// SDRAM PHY
sdram #(
    .FREQ(FREQ)
) u_sdram (
    .clk(fclk), .clk_sdram(clk_sdram), .resetn(resetn),
	.addr(mem_addr), .rd(mem_rd),
    .wr(mem_wr), .refresh(refresh),
	.din(mem_di), .dout(mem_do), .busy(busy), .data_ready(data_ready),

    .SDRAM_DQ(sdram_dq), .SDRAM_A(sdram_a), .SDRAM_BA(sdram_ba),
    .SDRAM_nCS(sdram_cs_n), .SDRAM_nWE(sdram_we_n), .SDRAM_nRAS(sdram_ras_n),
    .SDRAM_nCAS(sdram_cas_n), .SDRAM_CLK(sdram_clk), .SDRAM_CKE(sdram_cke),
    .SDRAM_DQM(sdram_dqm)
);

`else

// Fake SDRAM for verilator

reg [7:0] SIM_MEM [0:8*1024*1024-1];       // 8MB

// always @(posedge fclk) init_cnt <= init_cnt == 8'h0 ? 8'h0 : init_cnt - 8'h1;
assign busy = 1'b0;

reg [2:0] mem_cnt = 3'd5;                 // 5 means idle
reg [7:0] rd_res;
reg reading;
reg [7:0] mem_do_buf;
assign mem_do = mem_do_buf;

always @(posedge fclk) begin
    if (~resetn) begin
        mem_cnt <= 3'd5;                  // idle
        reading <= 1'b0;
    end begin
        mem_cnt <= mem_cnt == 3'd5 ? 3'd5 : mem_cnt + 1;
        if (reading && mem_cnt == 3'd3) begin
            mem_do_buf <= rd_res;
            reading <= 1'b0;
        end
        if (~busy && mem_cnt == 3'd5) begin
            if (mem_rd) begin               // read is availabe after 4 cycles
                mem_cnt <= 3'd1;
                reading <= 1'b1;
                rd_res <= SIM_MEM[mem_addr];
                // $display("sdram_read[%x] => %x, ca=%x, romsel_n=%x, ramsel_n=%x", mem_addr, SIM_MEM[mem_addr], ca, romsel_n, ramsel_n);
            end if (mem_wr) begin           // write
                SIM_MEM[mem_addr] <= mem_di;
                // $display("sdram_write[%x] <= %x, ca=%x, romsel_n=%x, ramsel_n=%x", mem_addr, mem_di, ca, romsel_n, ramsel_n);
            end
        end
    end
end

`endif
endmodule