`timescale 1ns/1ps
module tb_hdmi_video_stream;
 reg clk=0,rst=1,vs=0,de=0;reg [23:0] rgb=0;
 always #5 clk=~clk;
 wire valid,sof,last;wire [23:0] data;
 hdmi_video_stream dut(clk,rst,vs,de,rgb,valid,sof,last,data);
 integer f,y,x,sofs=0,lasts=0,pixels=0;
 task send;
 input d,v;input[23:0] value;input expected_sof,expected_last;
 begin
  @(negedge clk);de=d;vs=v;rgb=value;
  @(posedge clk);#1;
  if(valid!==d || data!==value || sof!==expected_sof || last!==expected_last)
   $fatal(1,"stream mismatch f/y/x=%0d/%0d/%0d",f,y,x);
  if(valid)pixels=pixels+1;if(sof)sofs=sofs+1;if(last)lasts=lasts+1;
 end
 endtask
 initial begin
  repeat(3)@(negedge clk);rst=0;
  for(f=0;f<3;f=f+1)begin
   send(0,1,0,0,0);send(0,0,0,0,0);
   for(y=0;y<480;y=y+1)begin
    for(x=0;x<640;x=x+1)send(1,0,{f[3:0],y[9:0],x[9:0]},y==0 && x==0,x==639);
    for(x=0;x<160;x=x+1)send(0,0,0,0,0);
   end
  end
  if(sofs!=3 || lasts!=1440 || pixels!=921600)$fatal(1,"marker counts");
  $display("PASS three full 640x480 frames, first-pixel SOF, exact 640th-pixel TLAST, RGB/valid alignment and blanking");$finish;
 end
endmodule
