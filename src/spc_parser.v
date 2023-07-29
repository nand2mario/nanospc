// SPC parser: parses the SPC file in test_aram and initializes
// SMP/CPU/DSP and also spcplayer
module spc_parser (
    input clk,
    input resetn,
    input start,                    // pulse to start parsing
    output done,                // parsing is finished

    // to aram
    output parser_rd,
    output [16:0] parser_a,
    input [7:0] aram_dout,

    // to smp/cpu
    output reg cpu_dbg_wr,          // write pulse to SPC registers
    output reg smp_dbg_wr,          // write pulse to SMP registers
    output reg [7:0] smpcpu_dbg_reg,
    output reg [7:0] smpcpu_dbg_din,

    // to dsp
    output reg dsp_dbg_wr,
    output reg [7:0] dsp_dbg_reg,
    output reg [7:0] dsp_dbg_din
);

// main state machine
reg [3:0] state = INIT;
reg int_done;
assign done = ~start & int_done;

localparam [3:0] INIT = 4'd0;
localparam [3:0] CPU_GET = 4'd1;    // SPC registers (A,X...)
localparam [3:0] CPU_SET = 4'd2;
localparam [3:0] SMP_GET = 4'd3;    // SMP registers (timers, etc)
localparam [3:0] SMP_SET = 4'd4;
localparam [3:0] DSP_GET = 4'd5;    // DSP registers
localparam [3:0] DSP_SET = 4'd6;
localparam [3:0] LAST_BYTE = 4'd7;

reg [2:0] cpu_reg_a;
reg [3:0] smp_reg_a;
reg [6:0] dsp_reg_a;

assign parser_rd = state == CPU_GET || state == SMP_GET || state == DSP_GET;
assign parser_a = state == CPU_GET ? 17'h25 + 17'(cpu_reg_a) :
                  state == SMP_GET ? 17'h1f0 + 17'(smp_reg_a) :
                  state == DSP_GET ? 17'h10100 + 17'(dsp_reg_a) : 17'h0;

always @(posedge clk) begin
    if (~resetn) begin
        state <= INIT;
        int_done <= 1'b0;
        cpu_reg_a <= 0;
        smp_reg_a <= 0;
        dsp_reg_a <= 0;
    end else begin
        cpu_dbg_wr <= 1'b0; smp_dbg_wr <= 1'b0; dsp_dbg_wr <= 1'b0;
        case (state)
        INIT: begin
            if (start) begin
                state <= CPU_GET;
                int_done <= 1'b0;
            end
        end
        CPU_GET: begin
            state <= CPU_SET;
        end
        CPU_SET: begin
            cpu_dbg_wr <= 1'b1;
            case (cpu_reg_a)
            3'd0: smpcpu_dbg_reg <= 8'd3; // PCL
            3'd1: smpcpu_dbg_reg <= 8'd4; // PCH
            3'd2: smpcpu_dbg_reg <= 8'd0; // A
            3'd3: smpcpu_dbg_reg <= 8'd1; // X
            3'd4: smpcpu_dbg_reg <= 8'd2; // Y
            3'd5: smpcpu_dbg_reg <= 8'd5; // PSW
            3'd6: smpcpu_dbg_reg <= 8'd6; // SP
            default: ;
            endcase
            smpcpu_dbg_din <= aram_dout;
            cpu_reg_a <= cpu_reg_a + 3'b1;
            if (cpu_reg_a == 3'd6)
                state <= SMP_GET;
            else
                state <= CPU_GET;
        end
        
        SMP_GET: begin
            // smp_reg_rd is 1 here
            state <= SMP_SET;
        end
        SMP_SET: begin
            smp_dbg_wr <= 1'b1;
            smpcpu_dbg_din <= aram_dout;
            smpcpu_dbg_reg <= 8'(smp_reg_a);
            smp_reg_a <= smp_reg_a + 4'b1;
            if (smp_reg_a == 4'd15)
                state <= DSP_GET;
            else
                state <= SMP_GET;
        end

        DSP_GET: begin
            // dsp_reg_rd is 1 here
            state <= DSP_SET;
        end
        DSP_SET: begin
            dsp_dbg_wr <= 1'b1;
            dsp_dbg_din <= aram_dout;
            dsp_dbg_reg <= 8'(dsp_reg_a);
            dsp_reg_a <= dsp_reg_a + 7'd1;
            if (dsp_reg_a == 7'd127)
                state <= LAST_BYTE;          // done
            else begin
                state <= DSP_GET;
            end
        end

        LAST_BYTE: begin
            int_done <= 1'b1;
            state <= INIT;
        end

        default: ;
        endcase
    end
end


endmodule