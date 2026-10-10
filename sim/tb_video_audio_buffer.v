`timescale 1ns/1ps
module tb_video_audio_buffer;
 reg clk=0,wclk=0;always #5 clk=~clk;always #7 wclk=~wclk;
 reg rst=1,enabled=1,paused=0,start=0,bank=0,tick=0;
 reg valid=0,wbank=0;reg [13:0] address=0;reg [7:0] data=0,fps=3;
 wire busy;wire [23:0] pcm;
 reg [15:0] golden[0:255];reg [1023:0] vectors;
 integer observed=0,expected_index=0,i;
 reg checking=0;
 video_audio_buffer dut(.write_clk(wclk),.write_valid(valid),.write_bank(wbank),
  .write_address(address),.write_data(data),.clk(clk),.rst(rst),.enabled(enabled),
  .paused(paused),.start(start),.read_bank(bank),.sample_tick(tick),.fps(fps),
  .busy(busy),.pcm_sample(pcm));
 always @(posedge clk)if(checking && tick)begin
  if(paused || !busy)begin
   if(pcm!==0)$fatal(1,"nonzero sample while paused/finished");
  end else begin
   expected_index=bank ? 255-(observed%256) : observed%256;
   if(pcm!=={golden[expected_index],8'd0})$fatal(1,"sample %0d bank %0d got %h expected %h",observed,bank,pcm,{golden[expected_index],8'd0});
   observed=observed+1;
  end
 end
 task samples(input integer n);integer k;begin
  for(k=0;k<n;k=k+1)begin
   @(negedge clk);tick=1;@(negedge clk);tick=0;repeat(3)@(negedge clk);
  end
 end endtask
 task begin_frame(input reg b,input [7:0] rate);begin
  checking=0;@(negedge clk);bank=b;fps=rate;start=1;observed=0;
  @(negedge clk);start=0;repeat(5)@(negedge clk);checking=1;
  if(!busy)$fatal(1,"frame did not start");
 end endtask
 initial begin
  if(!$value$plusargs("vectors=%s",vectors))$fatal(1,"missing independent decode vectors");
  $readmemh(vectors,golden);
  for(i=0;i<32768;i=i+1)begin
   @(negedge wclk);valid=1;wbank=i/16384;address=i%16384;
   data=wbank ? 255-(i%256) : i%256;
  end
  @(negedge wclk);valid=0;@(negedge clk);rst=0;
  begin_frame(0,3);samples(128);
  paused=1;samples(100);
  if(observed!=128 || !busy)$fatal(1,"pause advanced audio");
  paused=0;samples(16000-128);
  if(observed!=16000 || busy)$fatal(1,"wrong 3 fps audio length");
  samples(5);
  begin_frame(1,4);samples(12000);
  if(observed!=12000 || busy)$fatal(1,"wrong 4 fps audio length/bank");
  begin_frame(0,5);samples(9600);
  if(observed!=9600 || busy)$fatal(1,"wrong 5 fps audio length");
  begin_frame(1,3);samples(17);
  @(negedge clk);rst=1;checking=0;repeat(3)@(negedge clk);rst=0;
  if(busy || pcm!==0)$fatal(1,"reset did not mute/stop");
  begin_frame(0,3);samples(1);
  if(observed!=1)$fatal(1,"restart did not start at sample zero");
  @(negedge clk);enabled=0;repeat(3)@(negedge clk);
  if(busy || pcm!==0)$fatal(1,"legacy/image mode not silent");
  $display("PASS audio buffer: all 256 independent decode vectors, banks, sample counts, pause, silence and restart");$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
