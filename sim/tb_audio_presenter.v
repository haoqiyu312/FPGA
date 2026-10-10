`timescale 1ns/1ps
module tb_audio_presenter;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,vblank=0,start=0,paused=0,toggle=0,ack=0,audio_busy=0;
 wire consumed,bank,req,shown,audio_start;
 integer starts=0;
 video_frame_presenter #(.PIXEL_HZ(100),.AUDIO_SYNC(1)) dut
  (.clk(clk),.rst(rst),.vblank(vblank),.frame_start(start),.paused(paused),
   .frame_toggle(toggle),.fps(8'd5),.consumed_toggle(consumed),.read_bank(bank),
   .read_req(req),.read_ack(ack),.show_frame(shown),.audio_busy(audio_busy),.frame_started(audio_start));
 always @(posedge clk)if(audio_start)starts=starts+1;
 task blank;begin @(negedge clk);vblank=1;@(negedge clk);vblank=0;end endtask
 task acknowledge;begin
  wait(req);@(negedge clk);ack=1;repeat(5)@(negedge clk);ack=0;
  repeat(15)@(negedge clk);start=1;@(negedge clk);start=0;repeat(2)@(negedge clk);
  if(!shown)$fatal(1,"picture not visible");
 end endtask
 initial begin
  #30;rst=0;toggle=1;repeat(6)@(negedge clk);
  blank;wait(req);repeat(30)@(negedge clk);
  if(starts!=0)$fatal(1,"audio started before SDRAM primed");
  acknowledge;
  if(consumed!=1 || bank!=1 || starts!=1)$fatal(1,"initial picture/audio start");
  audio_busy=1;toggle=0;repeat(50)@(negedge clk);blank;acknowledge;
  if(consumed!=1 || bank!=1 || starts!=1)$fatal(1,"reused audio bank before playback completed");
  audio_busy=0;paused=1;blank;acknowledge;
  if(consumed!=1 || starts!=1)$fatal(1,"pause advanced/restarted audio");
  paused=0;repeat(25)@(negedge clk);blank;acknowledge;
  if(consumed!=0 || bank!=0 || starts!=2)$fatal(1,"next picture/audio start");
  $display("PASS audio presenter: visible-frame start, audio bank ownership, pause, no audio restart on HDMI refresh");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
