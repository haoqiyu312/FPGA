`timescale 1ns/1ps
module tb_hdmi_audio;
 reg clk=0,rst=1;
 always #5 clk=~clk;
 wire valid,acr_valid;wire signed [23:0] left_sample,right_sample;
 wire [19:0] n,cts;
 hdmi_test_audio dut(clk,rst,valid,left_sample,right_sample,acr_valid,n,cts);
 integer cycle,samples=0,acrs=0,last_cycle=0,interval;
 initial begin
  repeat(3)@(negedge clk);rst=0;
  for(cycle=1;cycle<=25000000;cycle=cycle+1)begin
   @(posedge clk);#1;
   if(valid)begin
    interval=cycle-last_cycle;
    if(interval!=520 && interval!=521)$fatal(1,"sample interval %0d",interval);
    last_cycle=cycle;
    if(left_sample!==right_sample)$fatal(1,"stereo mismatch");
    if(samples>=24000 && left_sample!==0)$fatal(1,"silence half");
    if(samples<24000)begin
     if(samples%48==0 && left_sample!==0)$fatal(1,"zero crossing");
     if(samples%48==12 && left_sample!==524288)$fatal(1,"positive peak");
     if(samples%48==36 && left_sample!==-524288)$fatal(1,"negative peak");
    end
    samples=samples+1;
   end
   if(acr_valid)begin
    if(!valid || samples%48!=0 || n!=6144 || cts!=25000)$fatal(1,"ACR timing/data");
    acrs=acrs+1;
   end
  end
  if(samples!=48000 || acrs!=1000)$fatal(1,"sample/ACR count %0d/%0d",samples,acrs);
  @(negedge clk);rst=1;@(posedge clk);#1;
  if(valid || acr_valid || left_sample!=0 || right_sample!=0)$fatal(1,"reset outputs");
  $display("PASS exact 48000 samples/second, 520/521 intervals, 1kHz sine, stereo, 0.5s silence, N/CTS and reset");
  $finish;
 end
endmodule
