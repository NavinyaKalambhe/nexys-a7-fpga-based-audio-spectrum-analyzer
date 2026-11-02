`timescale 1ns/1ps
// Checks VGA sync timing of vga_spectrum: line = 800 px, frame = 525 lines.
module tb_vga;
    reg clk = 0; always #5 clk = ~clk;
    reg rst = 1;
    wire [8:0] addr; wire [3:0] r,g,b; wire hs, vs;
    vga_spectrum dut(.clk(clk), .rst(rst), .zoom(1'b0), .spec_addr(addr), .spec_data(8'd100),
                     .vga_r(r), .vga_g(g), .vga_b(b), .vga_hs(hs), .vga_vs(vs));
    time t_h0, t_h1, t_v0, t_v1, hlow, vlow;
    initial begin
        repeat (10) @(posedge clk); rst = 0;
        @(negedge hs); t_h0 = $time; @(posedge hs); hlow = $time - t_h0;
        @(negedge hs); t_h1 = $time;
        $display("hsync period = %0d px (expect 800), pulse = %0d px (expect 96)", (t_h1 - t_h0)/40, hlow/40);
        @(negedge vs); t_v0 = $time; @(posedge vs); vlow = $time - t_v0;
        @(negedge vs); t_v1 = $time;
        $display("vsync period = %0d lines (expect 525), pulse = %0d lines (expect 2)", (t_v1 - t_v0)/32000, vlow/32000);
        $finish;
    end
endmodule
