`timescale 1ns/1ps
// Compare the original one-stage renderers with the native-clock two-stage
// renderers: pixel content must match exactly after one extra output clock.
module tb_square_r2_font_pipeline;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,de=0;reg[9:0] x=0,y=0;
 wire[15:0] code0,code1,pixels0,pixels1;
 wire[3:0] row0,row1;reg[15:0] code1_pipe;reg[3:0] row1_pipe;
 wire cover0,cover1;wire[23:0] rgb0,rgb1;
 osd_font16 font(.clk(clk),.codepoint(code0),.row(row0),.pixels(pixels0),
  .codepoint_b(code1_pipe),.row_b(row1_pipe),.pixels_b(pixels1));
 always @(posedge clk)begin code1_pipe<=code1;row1_pipe<=row1;end
 image_status_osd #(.WIDTH(720),.HEIGHT(720),.FONT_LATENCY(1)) slow(
  .pixel_clk(clk),.rst_n(rst_n),.x(x),.y(y),.de(de),.image_shown(1'b1),.load_status(4'd3),
  .image_index(5'd1),.image_total(6'd2),.auto_mode(1'b1),.interval_setting(2'd1),
  .reverse_direction(1'b0),.video_mode(1'b0),.overlay_active(cover0),.rgb(rgb0),
  .image_name("AD720   BMP"),.font_codepoint(code0),.font_row(row0),.font_pixels(pixels0));
 image_status_osd #(.WIDTH(720),.HEIGHT(720),.FONT_LATENCY(2)) fast(
  .pixel_clk(clk),.rst_n(rst_n),.x(x),.y(y),.de(de),.image_shown(1'b1),.load_status(4'd3),
  .image_index(5'd1),.image_total(6'd2),.auto_mode(1'b1),.interval_setting(2'd1),
  .reverse_direction(1'b0),.video_mode(1'b0),.overlay_active(cover1),.rgb(rgb1),
  .image_name("AD720   BMP"),.font_codepoint(code1),.font_row(row1),.font_pixels(pixels1));
 wire[15:0] bc0,bc1,bp0,bp1;wire[3:0] br0,br1;
 reg[15:0] bc_pipe;reg[3:0] br_pipe;
 wire bcover0,bcover1;wire[23:0] brgb0,brgb1;
 osd_font16 browser_font(.clk(clk),.codepoint(bc0),.row(br0),.pixels(bp0),
  .codepoint_b(bc_pipe),.row_b(br_pipe),.pixels_b(bp1));
 always @(posedge clk)begin bc_pipe<=bc1;br_pipe<=br1;end
 file_browser_overlay #(.WIDTH(720),.HEIGHT(720),.FONT_LATENCY(1)) browser_slow(
  .clk(clk),.rst_n(rst_n),.x(x),.y(y),.de(de),.visible(1'b1),.ready(1'b1),.count(6'd6),
  .status(4'd0),.debug_root_byte(8'd0),.debug_root_lba(16'd0),.scroll_first(5'd0),
  .selection_valid(1'b1),.selected(5'd2),.display_index(),.file_name("AD720   BMP"),.file_type(2'd1),
  .overlay_active(bcover0),.rgb(brgb0),.cn_codepoint(bc0),.cn_font_row(br0),.cn_pixels(bp0));
 file_browser_overlay #(.WIDTH(720),.HEIGHT(720),.FONT_LATENCY(2),.PIPE_COORDS(1)) browser_fast(
  .clk(clk),.rst_n(rst_n),.x(x),.y(y),.de(de),.visible(1'b1),.ready(1'b1),.count(6'd6),
  .status(4'd0),.debug_root_byte(8'd0),.debug_root_lba(16'd0),.scroll_first(5'd0),
  .selection_valid(1'b1),.selected(5'd2),.display_index(),.file_name("AD720   BMP"),.file_type(2'd1),
  .overlay_active(bcover1),.rgb(brgb1),.cn_codepoint(bc1),.cn_font_row(br1),.cn_pixels(bp1));
 reg last_cover,last_bcover,last_bcover2;reg[23:0] last_rgb,last_brgb,last_brgb2;
 integer warmup=0,checked=0;
 always @(posedge clk)begin
  #1;
  if(!rst_n)warmup=0;
  else begin
   if(warmup>4)begin
    if(cover1!==last_cover || rgb1!==last_rgb)$fatal(1,"status font/position mismatch");
    if(bcover1!==last_bcover2 || brgb1!==last_brgb2)$fatal(1,"browser ASCII/CJK/background mismatch");
    checked=checked+1;
   end
   warmup=warmup+1;
   last_bcover2=last_bcover;last_brgb2=last_brgb;
   last_cover=cover0;last_rgb=rgb0;last_bcover=bcover0;last_brgb=brgb0;
  end
 end
 integer px,py;
 initial begin
  repeat(5)@(negedge clk);rst_n=1;de=1;
  for(py=0;py<720;py=py+1)begin
   for(px=0;px<720;px=px+1)begin @(negedge clk);x=px;y=py;end
  end
  repeat(5)@(negedge clk);
  $display("PASS two-stage fonts preserve all CJK, ASCII, backgrounds and coordinates: %0d pixels",checked);
  $finish;
 end
 initial begin #6000000;$fatal(1,"timeout");end
endmodule
