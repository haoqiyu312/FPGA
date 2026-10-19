`timescale 1ns/1ps
module tb_audio_spectrum;
 reg clk=0;always #1 clk=~clk;
 reg rst=1,enabled=1,tick=0;
 reg signed [15:0] sample=0;
 wire [47:0] levels;
 integer n,i;
 reg [5:0] peak;
 audio_spectrum dut(.clk(clk),.rst(rst),.enabled(enabled),.sample_tick(tick),.sample(sample),.levels(levels));
 initial begin
  repeat(3)@(negedge clk);rst=0;
  // A 3 kHz tone is DFT bin 4 in the analyzer's 64-sample window.
  for(n=0;n<64;n=n+1)begin
   @(negedge clk);sample=$rtoi(12000.0*$sin(6.283185307179586*4*n/64.0));tick=1;
   @(negedge clk);tick=0;wait(dut.processing==1);wait(dut.processing==0);
  end
  #1;peak=0;
  for(i=1;i<8;i=i+1)if(levels[i*6+:6]>levels[peak*6+:6])peak=i;
  if(peak!=3 || levels[3*6+:6]<20)$fatal(1,"tone peak not detected: levels=%h peak=%0d",levels,peak);
  $display("Detected 3 kHz tone, band levels=%h",levels);
  enabled=0;@(negedge clk);if(levels!==0)$fatal(1,"disable did not clear spectrum");
  $display("PASS 8-bin Goertzel analyzer isolates 3 kHz test tone and clears on disable");$finish;
 end
endmodule
