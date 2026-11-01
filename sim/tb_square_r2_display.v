`timescale 1ns/1ps
module tb_square_r2_display;
 reg clk=0;always #5 clk=~clk;
 reg rst=1;
 wire[9:0] x,y;wire de,hs,vs;
 video_timing_640x480 #(.WIDTH(720),.HEIGHT(720),.HTOTAL(940),.VTOTAL(768),
  .HSA(20),.HBP(100),.VSA(8),.VBP(20)) timing(
  .pixel_clk(clk),.rst_n(~rst),.pixel_x(x),.pixel_y(y),.de(de),.hsync(hs),.vsync(vs));
 wire valid,sof,last;wire[23:0] data;
 hdmi_video_stream #(.FRAME_WIDTH(720)) stream(.clk(clk),.rst(rst),.vs(vs),.de(de),.rgb(24'h123456),
  .valid(valid),.sof(sof),.last(last),.data(data));
 integer active=0,lines=0,markers=0,clock_count=0;
 reg started=0,complete=0;
 always @(negedge clk)if(!rst)begin
  if(de)begin
   if(x>=720 || y>=720)$fatal(1,"active coordinate outside square");
   active=active+1;
   if(x==719)lines=lines+1;
  end
  if(last)begin
   if(!valid)$fatal(1,"TLAST without VALID");markers=markers+1;
  end
  if(de && x==0 && y==0)begin
   if(started)begin
    if(clock_count!=721920)$fatal(1,"wrong frame period %0d",clock_count);
    if(active!=518401 || lines!=720 || markers!=720)$fatal(1,"wrong active/line/marker counts %0d %0d %0d",active,lines,markers);
    complete=1;
   end
   started=1;clock_count=0;
  end
  if(started)clock_count=clock_count+1;
 end
 // At 12 kHz, one second of audio occupies 12000 samples and 48000 HDMI ticks.
 reg astart=0,enabled=1,tick=0;wire busy;wire[23:0] pcm;
 video_audio_buffer #(.AUDIO_RATE(12000)) audio(.write_clk(clk),.write_valid(1'b0),
  .write_bank(1'b0),.write_address(14'd0),.write_data(8'hff),.clk(clk),.rst(rst),
  .enabled(enabled),.paused(1'b0),.start(astart),.read_bank(1'b0),.sample_tick(tick),
  .fps(8'd1),.busy(busy),.pcm_sample(pcm));
 integer ticks=0;reg audio_complete=0;
 initial begin
  repeat(4)@(negedge clk);rst=0;
  @(negedge clk);astart=1;@(negedge clk);astart=0;
  repeat(4)@(negedge clk);tick=1;
  while(busy)begin @(negedge clk);ticks=ticks+1;end
  tick=0;
  if(ticks!=48000)$fatal(1,"audio released after %0d ticks",ticks);
  audio_complete=1;
 end
 initial begin
  wait(complete && audio_complete);
  $display("PASS 720x720 timing, 720 TLAST markers and 12kHz audio duration");$finish;
 end
 initial begin #20000000;$fatal(1,"timeout");end
endmodule
