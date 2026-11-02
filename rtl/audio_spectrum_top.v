`timescale 1ns/1ps
// ---------------------------------------------------------------------------
// Nexys A7-100T : on-board PDM mic -> CIC -> FIR -> 1024-pt FFT -> VGA spectrum
//
//   sw[1:0] FIR mode   : 00 bypass, 01 LPF 3 kHz, 10 HPF 3 kHz, 11 BPF 2-5 kHz
//   sw[2]   freeze     : hold the displayed spectrum
//   sw[3]   zoom       : 0..9.8 kHz at 2 px/bin (else 0..19.5 kHz)
//   sw[5:4] input gain : x1, x2, x4, x8 (saturating)
//   LED[15:0]          : log-scale level meter (1 LED per 6 dB)
//   CPU_RESETN         : active-low reset
// ---------------------------------------------------------------------------
module audio_spectrum_top (
    input  wire        clk100,
    input  wire        cpu_resetn,
    input  wire [5:0]  sw,
    output reg  [15:0] led,
    // microphone
    output wire        m_clk,
    input  wire        m_data,
    output wire        m_lrsel,
    // VGA
    output wire [3:0]  vga_r, vga_g, vga_b,
    output wire        vga_hs, vga_vs
);
    // ---------------- reset ----------------
    reg [2:0] rst_sr = 3'b111;
    always @(posedge clk100) rst_sr <= {rst_sr[1:0], ~cpu_resetn};
    wire rst = rst_sr[2];

    assign m_lrsel = 1'b0;                      // left channel

    // ---------------- microphone + decimator ----------------
    wire               cic_valid;
    wire signed [15:0] cic_s;
    pdm_cic u_mic (.clk(clk100), .rst(rst), .pdm_in(m_data), .m_clk(m_clk),
                   .sample_valid(cic_valid), .sample(cic_s));

    // ---------------- gain with saturation ----------------
    wire signed [18:0] g_full = $signed({{3{cic_s[15]}}, cic_s}) <<< sw[5:4];
    wire signed [15:0] gained = (g_full >  19'sd32767)  ? 16'sd32767 :
                                (g_full < -19'sd32768)  ? -16'sd32768 : g_full[15:0];

    // ---------------- FIR ----------------
    wire               fir_valid;
    wire signed [15:0] fir_s;
    fir_seq u_fir (.clk(clk100), .rst(rst), .mode(sw[1:0]),
                   .in_valid(cic_valid), .in_data(gained),
                   .out_valid(fir_valid), .out_data(fir_s));

    // ---------------- FFT ----------------
    wire       res_valid, frame_done;
    wire [8:0] res_bin;
    wire [7:0] res_log;
    fft1024 u_fft (.clk(clk100), .rst(rst), .in_valid(fir_valid), .in_data(fir_s),
                   .res_valid(res_valid), .res_bin(res_bin), .res_log(res_log),
                   .frame_done(frame_done));

    // ---------------- spectrum memory + VGA ----------------
    wire [8:0] spec_addr;
    wire [7:0] spec_data;
    spec_store u_spec (.clk(clk100), .res_valid(res_valid & ~sw[2]), .res_bin(res_bin),
                       .res_log(res_log), .rd_addr(spec_addr), .rd_data(spec_data));

    vga_spectrum u_vga (.clk(clk100), .rst(rst), .zoom(sw[3]),
                        .spec_addr(spec_addr), .spec_data(spec_data),
                        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
                        .vga_hs(vga_hs), .vga_vs(vga_vs));

    // ---------------- LED level meter (peak envelope, log thermometer) -------
    reg  [15:0] env;
    wire [15:0] absx = fir_s[15] ? (~fir_s + 16'd1) : fir_s;
    integer i;
    always @(posedge clk100) begin
        if (rst) env <= 16'd0;
        else if (fir_valid)
            env <= (absx > env) ? absx : ((env == 16'd0) ? 16'd0 : env - ((env >> 10) + 16'd1));
        for (i = 0; i < 16; i = i + 1) led[i] <= |(env >> i);
    end
endmodule
