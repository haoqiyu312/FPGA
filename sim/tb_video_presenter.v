`timescale 1ns/1ps
module tb_video_presenter;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,vblank=0,start=0,paused=0,toggle=0,ack=0;
 wire consumed,bank,req,shown;
 integer swaps=0;
 video_frame_presenter #(.PIXEL_HZ(100)) dut(clk,rst,vblank,start,paused,toggle,8'd5,consumed,bank,req,ack,shown);
 task blank;
  begin @(negedge clk);vblank=1;@(negedge clk);vblank=0;end
 endtask
 task acknowledge;
  begin
   wait(req);@(negedge clk);ack=1;repeat(5)@(negedge clk);ack=0;
   repeat(15)@(negedge clk);start=1;@(negedge clk);start=0;
   if(!shown)$fatal(1,"frame not primed");
  end
 endtask
 initial begin
  #30;rst=0;toggle=1;repeat(6)@(negedge clk);
  if(consumed!=0)$fatal(1,"swap outside blank");
  blank;acknowledge;
  if(consumed!=1 || bank!=1)$fatal(1,"first bank");
  paused=1;toggle=0;repeat(40)@(negedge clk);blank;acknowledge;
  if(consumed!=1 || bank!=1)$fatal(1,"pause swapped");
  paused=0;repeat(25)@(negedge clk);blank;acknowledge;
  if(consumed!=0 || bank!=0)$fatal(1,"resume bank");
  // A stalled acknowledgement prevents additional switches/refills.
  toggle=1;repeat(25)@(negedge clk);blank;wait(req);
  toggle=0;blank;
  if(consumed!=1 || bank!=1)$fatal(1,"swapped during outstanding request");
  $display("PASS presenter: blank-only swaps, pause/resume, priming and stalled ack");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
