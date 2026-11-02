`timescale 1ns/1ps
// ---------------------------------------------------------------------------
// PDM microphone front-end (ADMP421 on Nexys A7) :  clock generator + 4th-order
// CIC decimator.   100 MHz / 40 = 2.5 MHz M_CLK,  decimate by 64  ->  39.0625 kHz
//
//  * integrators run at the PDM rate (clock-enable), combs at the output rate
//  * comb section is pipelined one subtract per clock (timing friendly)
//  * Bit growth: 2 (bipolar +/-1 input) + 4*log2(64) = 26 bits, wrap-around OK
//  * Output = top 16 bits of the 26-bit result  (+/-2^24 full scale -> +/-2^14)
// ---------------------------------------------------------------------------
module pdm_cic #(
    parameter CLK_DIV = 40                 // 100 MHz / CLK_DIV = M_CLK (2.5 MHz)
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              pdm_in,       // M_DATA
    output reg               m_clk,
    output reg               sample_valid, // 1-clock strobe at 39.0625 kHz
    output reg signed [15:0] sample
);
    // ---------------- PDM clock + sampling strobe ----------------
    reg [5:0] div_cnt;
    reg [1:0] din_sync;
    reg       pdm_en;

    always @(posedge clk) begin
        if (rst) begin
            div_cnt <= 6'd0;
            m_clk   <= 1'b0;
            pdm_en  <= 1'b0;
        end else begin
            div_cnt <= (div_cnt == CLK_DIV-1) ? 6'd0 : div_cnt + 6'd1;
            m_clk   <= (div_cnt >= CLK_DIV/2);
            // Mic (L/R = GND) drives data after the falling edge and it is valid
            // until the next rising edge -> sample late in the low phase.
            pdm_en  <= (div_cnt == CLK_DIV/2 - 1);
        end
        din_sync <= {din_sync[0], pdm_in};
    end

    // ---------------- CIC integrators (run at PDM rate) ----------------
    wire signed [1:0] x = din_sync[1] ? 2'sd1 : -2'sd1;

    reg signed [25:0] i1, i2, i3, i4;
    reg        [5:0]  dec_cnt;
    reg signed [25:0] snap;
    reg               v0;

    always @(posedge clk) begin
        v0 <= 1'b0;
        if (rst) begin
            i1 <= 0; i2 <= 0; i3 <= 0; i4 <= 0;
            dec_cnt <= 6'd0;
        end else if (pdm_en) begin
            i1 <= i1 + x;
            i2 <= i2 + i1;
            i3 <= i3 + i2;
            i4 <= i4 + i3;
            dec_cnt <= dec_cnt + 6'd1;          // wraps at 64 = decimation ratio
            if (dec_cnt == 6'd63) begin
                snap <= i4;
                v0   <= 1'b1;
            end
        end
    end

    // ---------------- CIC combs (run at output rate, 1 stage / clock) ------
    reg signed [25:0] d1, d2, d3, d4, c1, c2, c3;
    reg               v1, v2, v3;
    wire signed [25:0] c4 = c3 - d4;

    always @(posedge clk) begin
        v1 <= 1'b0; v2 <= 1'b0; v3 <= 1'b0;
        sample_valid <= 1'b0;
        if (rst) begin
            d1 <= 0; d2 <= 0; d3 <= 0; d4 <= 0;
        end else begin
            if (v0) begin c1 <= snap - d1; d1 <= snap; v1 <= 1'b1; end
            if (v1) begin c2 <= c1   - d2; d2 <= c1;   v2 <= 1'b1; end
            if (v2) begin c3 <= c2   - d3; d3 <= c2;   v3 <= 1'b1; end
            if (v3) begin d4 <= c3; sample <= c4[25:10]; sample_valid <= 1'b1; end
        end
    end
endmodule
