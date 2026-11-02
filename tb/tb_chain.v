`timescale 1ns/1ps
// System-level test: behavioural PDM microphone (1st-order sigma-delta) producing
// 1 kHz (amp 0.30) + 6 kHz (amp 0.30)  ->  CIC -> FIR -> FFT.
// Run with FIR mode 1 (LPF 3 kHz): the 6 kHz tone must be strongly attenuated.
// Run time: ~1.1 frames (about 2.8 M clocks).
module tb_chain;
    parameter MODE = 1;
    reg clk = 0; always #5 clk = ~clk;
    reg rst = 1;
    wire m_clk, m_data_w;
    reg  m_data = 0;

    wire cic_valid; wire signed [15:0] cic_s;
    pdm_cic u_mic(.clk(clk), .rst(rst), .pdm_in(m_data), .m_clk(m_clk),
                  .sample_valid(cic_valid), .sample(cic_s));
    wire fir_valid; wire signed [15:0] fir_s;
    fir_seq u_fir(.clk(clk), .rst(rst), .mode(MODE[1:0]), .in_valid(cic_valid), .in_data(cic_s),
                  .out_valid(fir_valid), .out_data(fir_s));
    wire res_valid, frame_done; wire [8:0] res_bin; wire [7:0] res_log;
    fft1024 u_fft(.clk(clk), .rst(rst), .in_valid(fir_valid), .in_data(fir_s),
                  .res_valid(res_valid), .res_bin(res_bin), .res_log(res_log), .frame_done(frame_done));

    // ---- microphone model: data driven ~50 ns after the falling edge ----
    real pi = 3.14159265358979;
    real integ = 0.0, y = 1.0, x, t;
    integer cnt = 0;
    always @(negedge m_clk) begin
        t = cnt / 2.5e6;
        x = 0.30*$sin(2*pi*1000.0*t) + 0.30*$sin(2*pi*6000.0*t);
        integ = integ + x - y;
        y = (integ >= 0.0) ? 1.0 : -1.0;
        cnt = cnt + 1;
        #50 m_data = (y > 0.0);
    end

    reg [7:0] spec [0:511];
    always @(posedge clk) if (res_valid) spec[res_bin] <= res_log;

    integer k, maxk, pk6, errors;
    integer b1, b6;
    initial begin
        errors = 0;
        repeat (20) @(posedge clk); rst = 0;
        @(posedge frame_done);
        repeat (20) @(posedge clk);
        // bin width = 39062.5/1024 = 38.15 Hz  -> 1 kHz = bin 26.2, 6 kHz = bin 157.3
        b1 = 0; for (k = 24; k <= 28;  k = k + 1) if (spec[k] > b1) b1 = spec[k];
        b6 = 0; for (k = 155; k <= 160; k = k + 1) if (spec[k] > b6) b6 = spec[k];
        maxk = 3; for (k = 3; k < 512; k = k + 1) if (spec[k] > spec[maxk]) maxk = k;
        $display("MODE=%0d  peak bin=%0d  L(1k)=%0d  L(6k)=%0d", MODE, maxk, b1, b6);
        // expected 1 kHz amplitude 0.3*16384 = 4915 -> |X| ~ 1229 -> L ~ 164
        if (maxk < 25 || maxk > 27) errors = errors + 1;
        if (b1 < 150) errors = errors + 1;
        if (MODE == 1 && (b1 - b6) < 64) errors = errors + 1;     // >= 4 octaves (24 dB) rejection
        if (MODE == 0 && (b1 - b6) > 8)  errors = errors + 1;
        if (errors == 0) $display("CHAIN TEST PASSED"); else $display("CHAIN TEST FAILED (%0d)", errors);
        $finish;
    end
endmodule
