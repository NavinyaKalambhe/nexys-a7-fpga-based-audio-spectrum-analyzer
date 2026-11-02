`timescale 1ns/1ps
// ---------------------------------------------------------------------------
// 640x480@60 VGA spectrum renderer.  Single 100 MHz clock domain:
// the 25 MHz pixel rate is a clock-ENABLE (every 4th clock) -> no MMCM, no CDC.
// (25.000 MHz instead of 25.175 MHz gives 59.5 Hz refresh; monitors accept it.)
//
// Plot area: x = 64..575 (512 px), baseline y = 450, 24 px = 1 octave (6 dB).
// zoom = 0 : 1 px / bin (0..19.5 kHz)      zoom = 1 : 2 px / bin (0..9.8 kHz)
// ---------------------------------------------------------------------------
module vga_spectrum (
    input  wire       clk,
    input  wire       rst,
    input  wire       zoom,
    output wire [8:0] spec_addr,
    input  wire [7:0] spec_data,
    output reg  [3:0] vga_r, vga_g, vga_b,
    output reg        vga_hs, vga_vs
);
    reg [1:0] pcnt;
    wire      pce = (pcnt == 2'd3);
    reg [9:0] hc, vc;

    always @(posedge clk) begin
        if (rst) begin pcnt <= 2'd0; hc <= 10'd0; vc <= 10'd0; end
        else begin
            pcnt <= pcnt + 2'd1;
            if (pce) begin
                if (hc == 10'd799) begin
                    hc <= 10'd0;
                    vc <= (vc == 10'd524) ? 10'd0 : vc + 10'd1;
                end else hc <= hc + 10'd1;
            end
        end
    end

    wire [9:0] xo  = hc - 10'd64;
    assign spec_addr = zoom ? xo[9:1] : xo[8:0];

    wire active = (hc < 10'd640) && (vc < 10'd480);
    wire in_x   = (hc >= 10'd64) && (hc < 10'd576);
    wire in_y   = (vc >= 10'd60) && (vc < 10'd450);
    wire [9:0] d   = 10'd450 - vc;                          // height above baseline
    wire [9:0] hgt = {2'b00, spec_data} + {3'b000, spec_data[7:1]};   // L*1.5 px
    wire bar   = in_x && in_y && (d <= hgt);
    wire hgrid = in_x && in_y && ((d % 24) == 0);
    wire vgrid = in_x && in_y && (xo[5:0] == 6'd0);
    wire axis  = in_x && (vc == 10'd450);

    always @(posedge clk) begin
        if (pce) begin
            vga_hs <= ~((hc >= 10'd656) && (hc < 10'd752));
            vga_vs <= ~((vc >= 10'd490) && (vc < 10'd492));
            if (!active)      {vga_r, vga_g, vga_b} <= 12'h000;
            else if (axis)    {vga_r, vga_g, vga_b} <= 12'hFFF;
            else if (bar)     {vga_r, vga_g, vga_b} <= (d < 10'd130) ? 12'h0F0 :
                                                      (d < 10'd260) ? 12'hFF0 : 12'hF00;
            else if (hgrid || vgrid) {vga_r, vga_g, vga_b} <= 12'h333;
            else              {vga_r, vga_g, vga_b} <= 12'h000;
        end
    end
endmodule
