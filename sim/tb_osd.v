`timescale 1ns/1ps
module tb_osd;
reg clk=0;always #10 clk=~clk;
reg rst=1;reg[9:0]x=100,y=100;reg de=1,shown=0,auto_mode=0,dir=0,video_mode=0;
reg[3:0]status=0;reg[4:0]index=0;reg[5:0]total=4;reg[1:0]interval_setting=1;
reg[87:0]name="PIC01   BMP";
wire active;wire[23:0]rgb;
wire[15:0] font_code,font_pixels;wire[3:0] font_row;
osd_font16 font(.clk(clk),.codepoint(font_code),.row(font_row),.pixels(font_pixels),.codepoint_b(16'h0020),.row_b(4'd0),.pixels_b());
image_status_osd #(.NOTICE_FRAMES(2))dut(clk,rst,x,y,de,shown,status,index,total,auto_mode,interval_setting,dir,video_mode,active,rgb,name,font_code,font_row,font_pixels);
task ticks(input integer n);repeat(n)begin @(posedge clk);#1;end endtask
task frame;begin ticks(4);x=0;y=0;ticks(1);x=100;y=100;ticks(1);end endtask
task sample(input integer px,py);begin x=px;y=py;ticks(1);end endtask
integer px,py,lit;reg previous;
initial begin
 #1;rst=0;#10;rst=1;frame;
 sample(16,16);if(active)$fatal(1,"glyph whitespace is not transparent");
 shown=1;frame;
 if(dut.filename_text[511 -: 144]!==144'h00500049004300300031002e0042004d0050)$fatal(1,"filename format");
 if(dut.counter_text[511 -: 80]!==80'h00300031002f00300034)$fatal(1,"top right count");
 if(dut.auto_text[511 -: 80]!==80'h8f6e64adff1a517395ed)$fatal(1,"autoplay off label");
 if(dut.controls_text[511 -: 416]!==416'h004b00324e0b4e005f200020004b00334e0a4e005f200020004b003464ad653e002f6682505c0020957f63098fd456de83dc5355)$fatal(1,"Chinese image key hints");
 sample(16,16);if(active)$fatal(1,"filename rectangle filled");
 sample(17,18); // precise font contents are verified below, not assumed for ASCII.
 lit=0;
 for(py=16;py<32;py=py+1)for(px=16;px<32;px=px+1)begin sample(px,py);if(active)begin lit=lit+1;if(rgb!=24'he8f4ff)$fatal(1,"normal ink color");end end
 if(lit==0 || lit==256)$fatal(1,"filename glyph absent or solid block");
 sample(400,16);if(active)$fatal(1,"background between name and number covered");
 sample(16,424);if(active)$fatal(1,"disabled settings row visible");
 for(py=452;py<468;py=py+1)for(px=110;px<300;px=px+1)begin sample(px,py);if(active && rgb!=24'he8f4ff)$fatal(1,"key hints ink");end
 // The autoplay status and physical-key help are shown without a panel.
 sample(16,452);if(active)$fatal(1,"bottom glyph margin filled");
 auto_mode=1;dir=1;index=31;total=32;frame;
 if(dut.auto_text[511 -: 80]!==80'h8f6e64adff1a5f00542f)$fatal(1,"autoplay on label");
 if(dut.line1[511 -: 208]!==208'h95f49694ff1a0030003579d20020002065b95411ff1a50125e8f)$fatal(1,"interval/direction text");
 video_mode=1;frame;
 if(dut.controls_text[511 -: 272]!==272'h89c698910020004b003464ad653e002f6682505c0020957f63098fd456de83dc5355)$fatal(1,"Chinese video key hints");
 video_mode=0;frame;frame;
 lit=0;for(py=452;py<468;py=py+1)for(px=16;px<250;px=px+1)begin sample(px,py);if(active)lit=lit+1;end
 if(lit==0)$fatal(1,"key help missing");
 frame;frame;
 lit=0;for(py=16;py<32;py=py+1)for(px=16;px<232;px=px+1)begin sample(px,py);if(active)lit=lit+1;end
 if(lit==0)$fatal(1,"filename status should remain visible");
 auto_mode=0;frame;frame;frame;
 interval_setting=3;dir=0;frame;
 if(dut.notice!=0)$fatal(1,"hidden autoplay settings triggered notice while off");
 name="FLOWER  bmp";frame;
 if(dut.filename_text[511 -: 160]!==160'h0046004c004f005700450052002e0062006d0070 || dut.notice==0)$fatal(1,"filename change or lowercase suffix");
 shown=0;status=14;frame;
 if(dut.line0[511 -: 192]!==192'h95198bef00310034ff1a8bfb536162167f135b588d8565f6)$fatal(1,"error caption");
 sample(16,16);if(active)$fatal(1,"error rectangle filled");
 lit=0;for(py=16;py<32;py=py+1)for(px=16;px<32;px=px+1)begin sample(px,py);if(active)begin lit=lit+1;if(rgb!=24'hff9090)$fatal(1,"error ink color");end end
 if(lit==0)$fatal(1,"error glyph absent");
 de=0;ticks(1);if(active)$fatal(1,"glyph in blanking");
 $display("PASS transparent Chinese OSD, filename/count corners, persistent autoplay and key hints, errors, blanking");$finish;
end
endmodule
