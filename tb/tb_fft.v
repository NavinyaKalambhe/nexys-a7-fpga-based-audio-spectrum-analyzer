`timescale 1ns/1ps
// Unit test of fft1024: two bin-centred tones, checks peak bins and levels.
module tb_fft;
    reg clk = 0; always #5 clk = ~clk;
    reg rst = 1;
    reg in_valid = 0; reg signed [15:0] in_data = 0;
    wire res_valid, frame_done; wire [8:0] res_bin; wire [7:0] res_log;
    fft1024 dut(.clk(clk), .rst(rst), .in_valid(in_valid), .in_data(in_data),
                .res_valid(res_valid), .res_bin(res_bin), .res_log(res_log), .frame_done(frame_done));

    reg [7:0] spec [0:511];
    always @(posedge clk) if (res_valid) spec[res_bin] <= res_log;

    integer n, k, maxk, errors;
    real pi, v;
    initial begin
        pi = 3.14159265358979;
        errors = 0;
        repeat (10) @(posedge clk); rst = 0;
        for (n = 0; n < 1024; n = n + 1) begin
            v = 8000.0*$sin(2*pi*100*n/1024.0) + 4000.0*$sin(2*pi*300*n/1024.0) + 500.0;
            @(posedge clk); in_data <= $rtoi(v); in_valid <= 1;
            @(posedge clk); in_valid <= 0;
            repeat (1100) @(posedge clk);
        end
        @(posedge frame_done);
        repeat (20) @(posedge clk);
        $display("bin  98..102 : %0d %0d %0d %0d %0d", spec[98], spec[99], spec[100], spec[101], spec[102]);
        $display("bin 298..302 : %0d %0d %0d %0d %0d", spec[298], spec[299], spec[300], spec[301], spec[302]);
        $display("DC bins 0..4 : %0d %0d %0d %0d %0d", spec[0], spec[1], spec[2], spec[3], spec[4]);
        // expected: A/4 -> 2000 -> L ~ 175 ; 1000 -> L ~ 159
        maxk = 0;
        for (k = 3; k < 512; k = k + 1) if (spec[k] > spec[maxk]) maxk = k;
        $display("max bin = %0d  (expect 100)", maxk);
        if (maxk != 100) errors = errors + 1;
        if (spec[100] < 170 || spec[100] > 180) errors = errors + 1;
        if (spec[300] < 158 || spec[300] > 168) errors = errors + 1;   // 4000/4=1000 -> ~160
        // floor check away from tones
        for (k = 3; k < 512; k = k + 1)
            if ((k < 95 || k > 105) && (k < 295 || k > 305) && spec[k] > 40) begin
                errors = errors + 1; $display("floor too high at %0d: %0d", k, spec[k]);
            end
        if (errors == 0) $display("FFT TEST PASSED"); else $display("FFT TEST FAILED (%0d)", errors);
        $finish;
    end
endmodule
