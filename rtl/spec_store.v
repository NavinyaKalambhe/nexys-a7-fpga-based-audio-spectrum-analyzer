`timescale 1ns/1ps
// Spectrum memory (512 x 8) with fast-attack / slow-decay smoothing.
// Port A: read-modify-write from the FFT result stream (needs >=4 clocks / bin)
// Port B: read-only for the VGA scan-out
module spec_store #(
    parameter DECAY = 4                       // log units (1/16 octave) per frame
)(
    input  wire       clk,
    input  wire       res_valid,
    input  wire [8:0] res_bin,
    input  wire [7:0] res_log,
    input  wire [8:0] rd_addr,
    output reg  [7:0] rd_data
);
    reg [7:0] mem [0:511];
    integer i;
    initial for (i = 0; i < 512; i = i + 1) mem[i] = 8'd0;

    reg [8:0] a_addr;
    reg       a_we;
    reg [7:0] a_din, a_q;
    reg [7:0] new_l;
    reg       v1, v2;

    always @(posedge clk) begin
        if (a_we) mem[a_addr] <= a_din;
        a_q <= mem[a_addr];
    end
    always @(posedge clk) rd_data <= mem[rd_addr];

    wire [7:0] decayed = (a_q > DECAY) ? (a_q - DECAY) : 8'd0;

    always @(posedge clk) begin
        a_we <= 1'b0;
        v1   <= res_valid;
        v2   <= v1;
        if (res_valid) begin a_addr <= res_bin; new_l <= res_log; end
        if (v2) begin
            a_din <= (new_l >= decayed) ? new_l : decayed;
            a_we  <= 1'b1;
        end
    end
endmodule
