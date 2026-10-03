`timescale 1ns/1ps
module tb_key_beeper;
reg clk=0;always #10 clk=~clk;
reg [3:0] keys=15;wire buz;
key_beeper #(.DEBOUNCE_CYCLES(3),.BEEP_CYCLES(24),.HALF_TONE_CYCLES(3)) dut(clk,keys,buz);
integer k,j,edges;reg previous;
task ticks(input integer count);repeat(count)begin @(posedge clk);#1;end endtask
initial begin
 ticks(10);if(!buz)$fatal(1,"not silent at startup");
 keys[1]=0;ticks(1);keys[1]=1;ticks(10);
 if(dut.remaining!=0)$fatal(1,"bounce produced beep");
 for(k=0;k<4;k=k+1)begin
  @(negedge clk);keys[k]=0;wait(dut.remaining==24);#1;
  previous=buz;edges=0;
  for(j=0;j<24;j=j+1)begin ticks(1);if(buz!=previous)edges=edges+1;previous=buz;end
  if(dut.remaining!=0 || !buz || edges<6)$fatal(1,"duration/tone failed");
  ticks(30);if(dut.remaining!=0)$fatal(1,"held key repeated");
  @(negedge clk);keys[k]=1;ticks(10);
 end
 $display("PASS all four keys including KEY1, short tone, debounce, held key, idle high");$finish;
end
initial begin #100000;$fatal(1,"timeout");end
endmodule
