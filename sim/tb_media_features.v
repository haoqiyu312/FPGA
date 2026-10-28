`timescale 1ns/1ps
module tb_image_scale_address;
 initial begin #200000000;$fatal(1,"feature simulation timeout");end
 reg clk=0;always #5 clk=~clk;
 reg rst=1,ack=0,read_en=0,video=0;
 reg [1:0] zoom=0;
 reg [20:0] address=0;
 wire [20:0] mapped;
 image_scale_address dut(clk,rst,ack,read_en,video,zoom,address,mapped);
 integer mode,x,y,sx,sy,expected;
 initial begin
  repeat(3)@(negedge clk);rst=0;
  for(mode=0;mode<3;mode=mode+1)begin
   zoom=mode;read_en=0;repeat(4)@(negedge clk);
   ack=1;repeat(2)@(negedge clk);ack=0;
   for(y=0;y<480;y=y+1)for(x=0;x<640;x=x+1)begin
    if(mode==0)begin sx=x;sy=y;end
    else if(mode==1)begin
     sx=(x>=160 && x<480) ? (x-160)*2 : 0;
     sy=(y>=120 && y<360) ? (y-120)*2 : 0;
    end else begin sx=160+x/2;sy=120+y/2;end
    expected=sy*640+sx;
    #1;if(mapped!==expected)$fatal(1,"zoom %0d pixel %0d,%0d got %0d expected %0d",mode,x,y,mapped,expected);
    if(x%127==0)begin
     read_en=0;@(negedge clk);#1;
     if(mapped!==expected)$fatal(1,"address advanced while stalled");
    end
    read_en=1;@(negedge clk);
   end
   read_en=0;
  end
  video=1;address=21'd614399;#1;
  if(mapped!==address)$fatal(1,"video bank address corrupted");
  $display("PASS exhaustive 50/100/200 percent scaling, stalls, frame reset, video bypass");$finish;
 end
endmodule

module tb_media_transition;
 initial begin #200000000;$fatal(1,"feature simulation timeout");end
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,frame=0,shown=0,video=0;
 reg [9:0] x=320,y=240;
 reg [23:0] rgb=24'h804020;
 wire [23:0] result;wire [1:0] effect;
 media_transition dut(clk,rst_n,frame,shown,video,x,y,rgb,result,effect);
 task tick_frame;begin frame=1;@(negedge clk);frame=0;@(negedge clk);end endtask
 integer n;
 initial begin
  repeat(2)@(negedge clk);rst_n=1;tick_frame;
  shown=1;tick_frame;
  if(result!==0 || effect!==0)$fatal(1,"fade did not start from black");
  for(n=0;n<16;n=n+1)tick_frame;
  if(result!==24'h402010)$fatal(1,"fade midpoint lost RGB channel alignment: %h",result);
  for(n=0;n<16;n=n+1)tick_frame;
  if(result!==rgb)$fatal(1,"fade did not finish");
  shown=0;tick_frame;shown=1;tick_frame;
  for(n=0;n<16;n=n+1)tick_frame;
  x=319;#1;if(result!==rgb || effect!==1)$fatal(1,"wipe left edge");
  x=320;#1;if(result!==0)$fatal(1,"wipe right edge");
  video=1;#1;if(result!==rgb)$fatal(1,"video changed by photo transition");
  video=0;shown=0;tick_frame;shown=1;tick_frame;
  if(effect!==2)$fatal(1,"third effect not selected");
  for(n=0;n<32;n=n+1)tick_frame;
  x=639;y=479;#1;if(result!==rgb)$fatal(1,"third effect did not finish");
  $display("PASS fade colors, wipe boundary, effect rotation and video bypass");$finish;
 end
endmodule

module tb_media_feature_keys;
 initial begin #200000000;$fatal(1,"feature simulation timeout");end
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,next_n=1,prev_n=1,browser=0,video=0;
 wire next_event,prev_event,subtitles,spectrum;wire [1:0] zoom;
 media_feature_keys #(.DEBOUNCE_CYCLES(2),.LONG_CYCLES(20)) dut
 (clk,rst_n,next_n,prev_n,browser,video,next_event,prev_event,zoom,subtitles,spectrum);
 integer next_count=0,prev_count=0;
 always @(posedge clk)begin if(next_event)next_count=next_count+1;if(prev_event)prev_count=prev_count+1;end
 task settle;begin repeat(9)@(negedge clk);end endtask
 initial begin
  settle;rst_n=1;settle;
  next_n=0;settle;next_n=1;settle;
  if(next_count!=1 || prev_count!=0)$fatal(1,"single next action");
  next_n=0;settle;prev_n=0;settle;
  if(zoom!=1)$fatal(1,"staggered chord missed");
  next_n=1;settle;prev_n=1;settle;
  if(next_count!=1 || prev_count!=0)$fatal(1,"chord leaked navigation");
  next_n=0;prev_n=0;settle;repeat(30)@(negedge clk);
  if(zoom!=2)$fatal(1,"held chord repeated");
  next_n=1;prev_n=1;settle;
  prev_n=0;repeat(40)@(negedge clk);prev_n=1;settle;
  if(subtitles!=0 || prev_count!=0)$fatal(1,"long previous did not toggle caption exclusively");
  video=1;settle;next_n=0;settle;next_n=1;settle;
  if(spectrum!=0 || next_count!=1)$fatal(1,"video spectrum toggle");
  prev_n=0;settle;prev_n=1;settle;
  if(subtitles!=1)$fatal(1,"video subtitle toggle");
  browser=1;settle;prev_n=0;settle;prev_n=1;settle;
  if(prev_count!=1 || subtitles!=1)$fatal(1,"browser previous action");
  $display("PASS release actions, staggered/held chord, subtitle/spectrum controls, browser navigation");$finish;
 end
endmodule

module tb_media_subtitles;
 initial begin #200000000;$fatal(1,"feature simulation timeout");end
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,frame=0,started=0,shown=1,video=1,enabled=1,de=1;
 reg [7:0] fps=3;reg [1:0] zoom=0;
 reg [9:0] x=64,y=380;
 wire req,panel,ink;wire [15:0] code,pixels;wire [3:0] row;
 media_subtitles dut(clk,rst_n,frame,started,shown,video,enabled,fps,zoom,x,y,de,req,code,row,pixels,panel,ink);
 osd_font16 font(.clk(clk),.codepoint(code),.row(row),.pixels(pixels),.codepoint_b(16'd32),.row_b(4'd0),.pixels_b());
 task tick_frame;begin frame=1;@(negedge clk);frame=0;@(negedge clk);end endtask
 task present;begin started=1;@(negedge clk);started=0;@(negedge clk);end endtask
 integer n;integer lit;
 initial begin
  repeat(2)@(negedge clk);rst_n=1;tick_frame;
  if(code!==16'h4eca)$fatal(1,"first cue missing"); // 今
  repeat(20)tick_frame;
  if(code!==16'h4eca)$fatal(1,"caption advanced without a presented video frame");
  for(n=0;n<9;n=n+1)present;
  tick_frame;if(code!==16'h9999)$fatal(1,"3 second second cue missing"); // 香
  lit=0;
  for(n=0;n<256;n=n+1)begin
   x=64+n%16;y=380+n/16;@(negedge clk);#1;
   if(ink)lit=lit+1;
   if(!panel)$fatal(1,"caption panel missing");
  end
  if(lit==0)$fatal(1,"Chinese caption glyph is empty");
  enabled=0;tick_frame;repeat(2)@(negedge clk);
  if(panel || ink)$fatal(1,"subtitle disable failed");
  enabled=1;de=0;tick_frame;repeat(2)@(negedge clk);
  if(panel || ink)$fatal(1,"caption leaks into blanking");
  video=0;de=1;x=64;y=380;tick_frame;repeat(2)@(negedge clk);
  if(code!==16'h56fe)$fatal(1,"image caption missing");
  $display("PASS Chinese glyphs, media-time cues, pause, disable, blanking and image captions");$finish;
 end
endmodule

module tb_media_feature_hints;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,video=0;reg [9:0] x=0,y=0;
 wire active;wire [23:0] rgb;wire [15:0] code;wire [3:0] row;
 image_status_osd #(.FEATURE_HINTS(1)) dut(.pixel_clk(clk),.rst_n(rst_n),.x(x),.y(y),.de(1'b1),
 .image_shown(1'b1),.load_status(4'd5),.image_index(5'd0),.image_total(6'd1),
 .auto_mode(1'b0),.interval_setting(2'd1),.reverse_direction(1'b0),.video_mode(video),
 .overlay_active(active),.rgb(rgb),.image_name("PIC01   BMP"),
 .font_codepoint(code),.font_row(row),.font_pixels(16'hffff));
 initial begin
  repeat(2)@(negedge clk);rst_n=1;repeat(6)@(negedge clk);
  if(dut.controls_text!==512'h004b0032002f0033520756fe002053cc952e7f29653e0020957f6309004b00335b575e550020004b003464ad653e002000200020002000200020002000200020)$fatal(1,"image feature hints missing");
  video=1;repeat(6)@(negedge clk);
  if(dut.controls_text!==512'h004b003298918c310020004b00335b575e550020004b003464ad653e002f6682505c0020957f63098fd456de83dc535500200020002000200020002000200020)$fatal(1,"video feature hints missing");
  $display("PASS extended player controls are exposed in Chinese OSD");$finish;
 end
endmodule
