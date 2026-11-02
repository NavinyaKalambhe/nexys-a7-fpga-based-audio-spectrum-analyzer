`timescale 1ns/1ps
// ---------------------------------------------------------------------------
// Sequential (time-multiplexed) 127-tap FIR.   ONE multiplier / DSP48 only.
//
//  fs = 39.0625 kHz  ->  2560 clocks available per sample, 128 needed.
//  This is the classic area-vs-throughput trade-off: a fully parallel
//  direct-form FIR would need 127 multipliers (or 64 when exploiting symmetry).
//
//  Pipeline (all registered, easily >100 MHz):
//    issue addr -> BRAM/ROM read -> multiply -> accumulate -> round/saturate
//
//  mode: 0 bypass(impulse), 1 LPF 3 kHz, 2 HPF 3 kHz, 3 BPF 2-5 kHz
//  Coefficients Q1.15 from fir_coeffs.mem (see scripts/gen_mem.py)
// ---------------------------------------------------------------------------
module fir_seq #(
    parameter TAPS = 128
)(
    input  wire              clk,
    input  wire              rst,
    input  wire        [1:0] mode,
    input  wire              in_valid,
    input  wire signed [15:0] in_data,
    output reg               out_valid,
    output reg  signed [15:0] out_data
);
    reg signed [15:0] smp_mem  [0:127];     // circular sample buffer
    reg signed [15:0] coef_rom [0:511];     // 4 modes x 128 taps
    integer ii;
    initial begin
        for (ii = 0; ii < 128; ii = ii + 1) smp_mem[ii] = 16'sd0;
        $readmemh("fir_coeffs.mem", coef_rom);
    end

    reg  [6:0] cur_ptr;                      // address of newest sample
    reg  [7:0] k;                            // tap counter
    reg        busy;
    wire [6:0] rd_addr = cur_ptr - k[6:0];

    reg signed [15:0] smp_q, coef_q;
    reg               v1, f1, l1;            // stage-1 valid / first / last
    reg               v2, f2, l2;
    reg signed [31:0] prod;
    reg signed [39:0] acc;
    reg               done;

    // memory access (inferred BRAM / LUTRAM, synchronous read)
    always @(posedge clk) begin
        if (in_valid) smp_mem[cur_ptr + 7'd1] <= in_data;
        smp_q  <= smp_mem[rd_addr];
        coef_q <= coef_rom[{mode, k[6:0]}];
    end

    wire signed [39:0] rnd = acc + 40'sd16384;           // round to nearest
    wire signed [39:0] shr = rnd >>> 15;

    always @(posedge clk) begin
        if (rst) begin
            cur_ptr <= 7'd0; k <= 8'd0; busy <= 1'b0;
            v1 <= 1'b0; v2 <= 1'b0; f1 <= 1'b0; f2 <= 1'b0; l1 <= 1'b0; l2 <= 1'b0;
            done <= 1'b0; out_valid <= 1'b0; acc <= 40'sd0; out_data <= 16'sd0;
        end else begin
            out_valid <= 1'b0;
            v1        <= 1'b0;
            done      <= 1'b0;

            // ---- stage 0: sequencer ----
            if (in_valid) begin
                cur_ptr <= cur_ptr + 7'd1;
                k       <= 8'd0;
                busy    <= 1'b1;
            end else if (busy) begin
                v1 <= 1'b1;
                f1 <= (k == 8'd0);
                l1 <= (k == TAPS-1);
                k  <= k + 8'd1;
                if (k == TAPS-1) busy <= 1'b0;
            end

            // ---- stage 1 -> 2: multiply ----
            prod <= smp_q * coef_q;
            v2 <= v1; f2 <= f1; l2 <= l1;

            // ---- stage 3: accumulate ----
            if (v2) begin
                acc <= (f2 ? 40'sd0 : acc) + prod;
                if (l2) done <= 1'b1;
            end

            // ---- stage 4: round + saturate ----
            if (done) begin
                out_data  <= (shr >  40'sd32767)  ? 16'sd32767 :
                             (shr < -40'sd32768)  ? -16'sd32768 : shr[15:0];
                out_valid <= 1'b1;
            end
        end
    end
endmodule
