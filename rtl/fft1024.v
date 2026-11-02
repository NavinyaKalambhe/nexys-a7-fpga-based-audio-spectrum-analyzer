`timescale 1ns/1ps
// ---------------------------------------------------------------------------
// 1024-point radix-2 DIT FFT, in-place, ONE butterfly (4 multipliers),
// block scaling 1/2 per stage, Q1.15 data, 16-bit real/imag.
//
//   capture RAM (1024x16) --Hann window--> bit-reversed write into work RAM
//   work RAM (1024x32 = {re,im}, true dual port) <-> butterfly engine
//   post stage: |X| ~ max + 3/8*min  ->  log2 (4.4 fixed) -> bin stream
//
// Timing: 9 clocks/butterfly * 5120 butterflies = 46k clocks = 0.46 ms,
// versus 26 ms to collect a frame -> plenty of slack for a minimal-area engine.
// To go faster: pipeline the butterfly (1 result / clock) or use radix-4.
//
// Output scaling: a tone of amplitude A (bin-centred) gives |X| = A/4
// (1/N from the stage scaling, 0.5 Hann coherent gain, 0.5 real-signal split).
// ---------------------------------------------------------------------------
module fft1024 #(
    parameter DC_BINS = 3                   // bins below this are blanked
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              in_valid,
    input  wire signed [15:0] in_data,
    output reg               res_valid,     // one pulse per bin
    output reg        [8:0]  res_bin,       // 0..511
    output reg        [7:0]  res_log,       // log2(|X|), 4 int + 4 frac bits
    output reg               frame_done
);
    localparam N = 1024;

    // ------------------------------------------------------------------
    // helper functions
    // ------------------------------------------------------------------
    function [9:0] brev;
        input [9:0] x;
        integer b;
        begin
            for (b = 0; b < 10; b = b + 1) brev[b] = x[9-b];
        end
    endfunction

    function [7:0] log2_q4;
        input [15:0] x;
        integer b;
        reg [3:0]  p;
        reg [15:0] nrm;
        begin
            p = 4'd0;
            for (b = 0; b < 16; b = b + 1) if (x[b]) p = b[3:0];
            nrm = x << (4'd15 - p);
            log2_q4 = (x == 16'd0) ? 8'd0 : {p, nrm[14:11]};
        end
    endfunction

    function signed [15:0] sat16;
        input signed [18:0] v;
        begin
            if (v > 19'sd32767)       sat16 = 16'sd32767;
            else if (v < -19'sd32768) sat16 = -16'sd32768;
            else                      sat16 = v[15:0];
        end
    endfunction

    // ------------------------------------------------------------------
    // memories
    // ------------------------------------------------------------------
    reg signed [15:0] cap_mem [0:N-1];
    reg        [15:0] win_rom [0:N-1];
    reg        [31:0] tw_rom  [0:N/2-1];
    reg        [31:0] work    [0:N-1];
    initial begin
        $readmemh("hann.mem",    win_rom);
        $readmemh("twiddle.mem", tw_rom);
    end

    // capture RAM : simple dual port
    reg               cap_we;
    reg        [9:0]  cap_waddr;
    reg signed [15:0] cap_din;
    reg        [9:0]  cap_ra;
    reg signed [15:0] cap_q;
    reg signed [15:0] win_q;
    always @(posedge clk) begin
        if (cap_we) cap_mem[cap_waddr] <= cap_din;
        cap_q <= cap_mem[cap_ra];
        win_q <= win_rom[cap_ra];
    end

    // twiddle ROM
    reg [8:0]  tw_ra;
    reg [31:0] tw_q;
    always @(posedge clk) tw_q <= tw_rom[tw_ra];

    // work RAM : simple dual port (1 write port + 1 read port, one clock).
    // The butterfly engine has plenty of clock slack, so a and b are read
    // one after the other and x and y are written one after the other.
    // This maps cleanly onto one RAMB36 (read-first, registered output).
    reg        w_we;
    reg [9:0]  w_addr, r_addr;
    reg [31:0] w_din, r_q;
    always @(posedge clk) begin
        if (w_we) work[w_addr] <= w_din;
        r_q <= work[r_addr];
    end

    // ------------------------------------------------------------------
    // capture : continuously fills the 1024 sample frame
    // ------------------------------------------------------------------
    reg [9:0] wr_idx;
    reg       frame_pulse;
    always @(posedge clk) begin
        cap_we    <= in_valid;
        cap_din   <= in_data;
        cap_waddr <= wr_idx;
        frame_pulse <= 1'b0;
        if (rst) begin
            wr_idx <= 10'd0;
        end else if (in_valid) begin
            wr_idx <= wr_idx + 10'd1;
            if (wr_idx == N-1) frame_pulse <= 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // main FSM
    // ------------------------------------------------------------------
    localparam S_IDLE = 2'd0, S_LOAD = 2'd1, S_BFLY = 2'd2, S_POST = 2'd3;
    reg [1:0]  state;
    reg [3:0]  ph;
    reg [10:0] li;                  // load counter
    reg [9:0]  li1, li2, li3;
    reg        lv1, lv2, lv3;
    reg signed [31:0] wprod;
    reg [3:0]  stg;                 // 1..10
    reg [8:0]  n;                   // butterfly number within stage
    reg [8:0]  pk;                  // post-stage bin

    // butterfly index generation
    wire [9:0] half  = 10'd1 << (stg - 4'd1);
    wire [9:0] jj    = {1'b0, n} & (half - 10'd1);
    wire [9:0] a_idx = ((({1'b0, n}) >> (stg - 4'd1)) << stg) | jj;
    wire [9:0] b_idx = a_idx | half;
    wire [8:0] tw_ix = jj[8:0] << (4'd10 - stg);

    reg [9:0] a_r, b_r;
    reg signed [15:0] ar, ai, br, bi, wr, wi;
    reg signed [31:0] m1, m2, m3, m4;
    reg signed [17:0] tr, ti;
    reg signed [15:0] xr, xi, yr, yi;

    wire signed [18:0] sxr = ar + tr + 19'sd1;
    wire signed [18:0] sxi = ai + ti + 19'sd1;
    wire signed [18:0] syr = ar - tr + 19'sd1;
    wire signed [18:0] syi = ai - ti + 19'sd1;

    wire signed [33:0] trf = m1 - m2 + 34'sd16384;
    wire signed [33:0] tif = m3 + m4 + 34'sd16384;

    // post-processing
    reg signed [15:0] pre, pim;
    reg        [15:0] rabs, iabs, mx, mn, mag;
    wire       [17:0] magsum = {2'b0, mx} + {4'b0, mn[15:2]} + {5'b0, mn[15:3]};

    always @(posedge clk) begin
        w_we       <= 1'b0;
        res_valid  <= 1'b0;
        frame_done <= 1'b0;

        // load-stage pipeline flags free-run
        lv1 <= 1'b0;
        lv2 <= lv1;
        lv3 <= lv2;
        li2 <= li1;
        li3 <= li2;
        wprod <= cap_q * win_q;

        if (rst) begin
            state <= S_IDLE; ph <= 4'd0; li <= 11'd0; stg <= 4'd1; n <= 9'd0; pk <= 9'd0;
            lv1 <= 1'b0; lv2 <= 1'b0; lv3 <= 1'b0;
        end else begin
            case (state)
            // ---------------------------------------------------------
            S_IDLE: begin
                if (frame_pulse) begin state <= S_LOAD; li <= 11'd0; end
            end
            // ---------------------------------------------------------
            // read capture RAM linearly, window, write bit-reversed
            S_LOAD: begin
                if (li < N) begin
                    cap_ra <= li[9:0];
                    li1    <= li[9:0];
                    lv1    <= 1'b1;
                end
                li <= li + 11'd1;
                if (lv3) begin
                    w_we   <= 1'b1;
                    w_addr <= brev(li3);
                    w_din  <= {((wprod + 32'sd16384) >>> 15), 16'd0};
                end
                if (li == N + 5) begin
                    state <= S_BFLY; stg <= 4'd1; n <= 9'd0; ph <= 4'd0;
                end
            end
            // ---------------------------------------------------------
            S_BFLY: begin
                case (ph)
                4'd0: begin
                    r_addr <= a_idx;   tw_ra <= tw_ix;
                    a_r <= a_idx;      b_r <= b_idx;
                    ph <= 4'd1;
                end
                4'd1: begin r_addr <= b_r; ph <= 4'd2; end   // 2nd read: b
                4'd2: begin                             // r_q = a
                    ar <= r_q[31:16]; ai <= r_q[15:0];
                    wr <= tw_q[31:16]; wi <= tw_q[15:0];
                    ph <= 4'd3;
                end
                4'd3: begin                             // r_q = b
                    br <= r_q[31:16]; bi <= r_q[15:0];
                    ph <= 4'd4;
                end
                4'd4: begin                             // 4 real multiplies (DSP48)
                    m1 <= br * wr;  m2 <= bi * wi;
                    m3 <= br * wi;  m4 <= bi * wr;
                    ph <= 4'd5;
                end
                4'd5: begin                             // t = b * W   (Q15)
                    tr <= trf >>> 15;
                    ti <= tif >>> 15;
                    ph <= 4'd6;
                end
                4'd6: begin                             // (a +/- t) / 2, saturated
                    xr <= sat16(sxr >>> 1);  xi <= sat16(sxi >>> 1);
                    yr <= sat16(syr >>> 1);  yi <= sat16(syi >>> 1);
                    ph <= 4'd7;
                end
                4'd7: begin                             // write x -> a_r
                    w_we <= 1'b1; w_addr <= a_r; w_din <= {xr, xi};
                    ph <= 4'd8;
                end
                4'd8: begin                             // write y -> b_r, next butterfly
                    w_we <= 1'b1; w_addr <= b_r; w_din <= {yr, yi};
                    ph <= 4'd0;
                    if (n == 9'd511) begin
                        n <= 9'd0;
                        if (stg == 4'd10) begin state <= S_POST; pk <= 9'd0; end
                        else stg <= stg + 4'd1;
                    end else n <= n + 9'd1;
                end
                default: ph <= 4'd0;
                endcase
            end
            // ---------------------------------------------------------
            // magnitude + log2 for bins 0..511  (8 clocks / bin)
            S_POST: begin
                case (ph)
                4'd0: begin r_addr <= {1'b0, pk}; ph <= 4'd1; end
                4'd1: ph <= 4'd2;
                4'd2: begin pre <= r_q[31:16]; pim <= r_q[15:0]; ph <= 4'd3; end
                4'd3: begin
                    rabs <= pre[15] ? (~pre + 16'd1) : pre;
                    iabs <= pim[15] ? (~pim + 16'd1) : pim;
                    ph <= 4'd4;
                end
                4'd4: begin
                    mx <= (rabs > iabs) ? rabs : iabs;
                    mn <= (rabs > iabs) ? iabs : rabs;
                    ph <= 4'd5;
                end
                4'd5: begin
                    mag <= magsum[17:16] != 2'b00 ? 16'hFFFF : magsum[15:0];
                    ph <= 4'd6;
                end
                4'd6: begin
                    res_bin   <= pk;
                    res_log   <= (pk < DC_BINS) ? 8'd0 : log2_q4(mag);
                    res_valid <= 1'b1;
                    ph <= 4'd7;
                end
                4'd7: begin
                    ph <= 4'd0;
                    if (pk == 9'd511) begin state <= S_IDLE; frame_done <= 1'b1; end
                    else pk <= pk + 9'd1;
                end
                default: ph <= 4'd0;
                endcase
            end
            endcase
        end
    end
endmodule
