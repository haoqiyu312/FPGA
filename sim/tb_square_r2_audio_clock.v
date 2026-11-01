`timescale 1ns/1ps
module tb_square_r2_audio_clock;
 reg clk=0;always #5 clk=~clk;
 reg rst=1;wire tick,acr;wire[23:0] l,r;wire[19:0] n,cts;
 hdmi_test_audio #(.PIXEL_HZ(48000000)) audio(.clk(clk),.rst(rst),.sample_valid(tick),
 .left_sample(l),.right_sample(r),.acr_valid(acr),.acr_n(n),.acr_cts(cts));
 integer cycles=0,ticks=0,last_tick=0;
 always @(negedge clk)if(!rst)begin
  cycles=cycles+1;
  if(tick)begin
   if(last_tick!=0 && cycles-last_tick!=1000)$fatal(1,"48 MHz audio tick spacing changed");
   last_tick=cycles;ticks=ticks+1;
  end
 end
 initial begin
  repeat(4)@(negedge clk);rst=0;
  wait(ticks==480);@(posedge clk);
  if(n!=6144 || cts!=48000)$fatal(1,"wrong HDMI audio clock regeneration");
  $display("PASS 48 MHz pixel clock produces 48 kHz samples and correct CTS/N");$finish;
 end
 initial begin #6000000;$fatal(1,"timeout");end
endmodule
