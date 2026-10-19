`timescale 1ns/1ps
module tb_browser_render #(parameter SERIAL_METADATA=0);
 reg clk=0;always #5 clk=~clk;
 reg reset_n=0,de=0,visible=1,ready=1;reg[9:0]x=0,y=0;
 reg[5:0]count=6;reg[4:0]scroll_first=0,selected=1;
 wire[4:0]index;wire overlay_active;wire[23:0]rgb;
 wire[87:0]name;wire[1:0]kind;
 wire[15:0]cn_codepoint,cn_pixels;wire[3:0]cn_row;
 osd_font16 font(.clk(clk),.codepoint(16'h0020),.row(4'd0),.pixels(),.codepoint_b(cn_codepoint),.row_b(cn_row),.pixels_b(cn_pixels));
 function[87:0] fixture_name;input[4:0]i;begin case(i)
  0:fixture_name="PIC01   BMP";1:fixture_name="MUSIC   RV ";2:fixture_name="SONG    WAV";
  3:fixture_name="PIC02   BMP";4:fixture_name="DEMO    RV ";default:fixture_name="PIC03   BMP";
 endcase end endfunction
 function[1:0] fixture_kind;input[4:0]i;begin fixture_kind=i==2 ? 3 : (i==1 || i==4) ? 2 : 1;end endfunction
 generate if(SERIAL_METADATA)begin:serial
  fat32_media_catalog catalog(.clk(clk),.rst(1'b0),.sd_ready(1'b0),.sector_byte(8'd0),.sector_valid(1'b0),.sector_end(1'b0),
   .query_index(5'd0),.display_index(index),.display_name(name),.display_type(kind),.display_clk(clk));
  integer i,j;reg[87:0]fixture;
  initial begin
   force catalog.done=1'b1;
   for(i=0;i<6;i=i+1)begin
    fixture=fixture_name(i);
    catalog.metadata[i*16]={1'b0,fixture_kind(i),5'd0};
    for(j=0;j<11;j=j+1)catalog.metadata[i*16+j+1]=fixture[87-j*8-:8];
   end
  end
 end else begin:direct
  assign name=fixture_name(index);assign kind=fixture_kind(index);
 end endgenerate
 file_browser_overlay dut(.clk(clk),.rst_n(reset_n),.x(x),.y(y),.de(de),.visible(visible),.ready(ready),
  .count(count),.status(4'd3),.debug_root_byte(8'h50),.debug_root_lba(16'h6000),
  .scroll_first(scroll_first),.selection_valid(1'b1),.selected(selected),.display_index(index),
  .file_name(name),.file_type(kind),.overlay_active(overlay_active),.rgb(rgb),
  .cn_codepoint(cn_codepoint),.cn_font_row(cn_row),.cn_pixels(cn_pixels));
 integer f,px,py;
 task pixel(input integer a,b);begin
  @(negedge clk);x=a;y=b;de=1;@(posedge clk);#1;
 end endtask
 initial begin
  repeat(3)@(negedge clk);reset_n=1;repeat(16)@(negedge clk);
  pixel(128,16);if(dut.cn_character!==16'h5b58)$fatal(1,"Chinese title first glyph %04x label=%04x area=%b x=%0d y=%0d vis=%b",dut.cn_character,dut.cn_label[511-:16],dut.cn_text_area,x,y,visible);
  pixel(144,16);if(dut.cn_character!==16'h50a8)$fatal(1,"Chinese title second glyph %04x",dut.cn_character);
  pixel(20,70);if(!overlay_active || rgb!==24'h203440 || index!=0)$fatal(1,"list row 0");
  pixel(80,110);if(rgb!==24'h185880 || index!=1)$fatal(1,"selected list row");
  pixel(20,150);if(index!=2)$fatal(1,"list row ordering");
  repeat(16)@(negedge clk);
  pixel(17,111);if(rgb!==24'h58d8e8)$fatal(1,"selected row accent");
  pixel(33,152);if(rgb!==24'hf0f4f5)$fatal(1,"audio document tile");
  pixel(39,161);if(rgb!==24'hd99932)$fatal(1,"audio note icon");
  pixel(39,121);repeat(16)@(posedge clk);#1;if(rgb!==24'hf4fbff)$fatal(1,"video play icon rgb=%06x kind=%0d index=%0d",rgb,kind,index);
  pixel(43,199);repeat(16)@(posedge clk);#1;if(rgb!==24'hffd46a)$fatal(1,"image sun icon rgb=%06x kind=%0d index=%0d",rgb,kind,index);
  pixel(20,390);if(!overlay_active)$fatal(1,"full browser coverage");
  @(negedge clk);de=0;@(posedge clk);#1;if(overlay_active)$fatal(1,"blanking");
  count=17;scroll_first=5;visible=1;
  pixel(610,70);if(rgb!==24'h26343c)$fatal(1,"scrollbar track rgb=%06x color=%06x next=%06x cover=%b",rgb,dut.color,dut.next_color,overlay_active);
  pixel(610,160);if(rgb!==24'hb0c8d8)$fatal(1,"scrollbar thumb follows selection window");
  visible=0;pixel(580,60);if(overlay_active)$fatal(1,"hidden browser overlay");pixel(100,100);if(overlay_active)$fatal(1,"picture transparency");
  visible=1;count=6;scroll_first=0;selected=1;
  f=$fopen("browser.ppm","wb");$fwrite(f,"P6\n640 480\n255\n");
  for(py=0;py<480;py=py+1)for(px=0;px<640;px=px+1)begin
   pixel(px,py);$fwrite(f,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
  end
  $fclose(f);$display("PASS browser overlay rows/icons/scrollbar/blanking; actual RTL preview rendered");$finish;
 end
endmodule
