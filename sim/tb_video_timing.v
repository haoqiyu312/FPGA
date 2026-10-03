`timescale 1ns/1ps
module tb_video_timing;
reg clk=0;always #20 clk=~clk;
reg rst_n=1;wire[9:0] x,y;wire de,hs,vs;
integer h=0,v=0,n=0,pixels=0;
video_timing_640x480 dut(clk,rst_n,x,y,de,hs,vs);
initial begin #1;rst_n=0;#12;rst_n=1;end
always @(negedge clk) if(rst_n) begin
 if(hs !== !(h<96) || vs !== !(v<2)) $fatal(1,"sync mismatch %0d %0d",h,v);
 if(de !== (h>=144 && h<784 && v>=35 && v<515)) $fatal(1,"DE mismatch");
 if(de) begin
  if(x!=h-144 || y!=v-35) $fatal(1,"pixel position mismatch");
  pixels=pixels+1;
 end
 n=n+1;
 if(h==799) begin h=0;if(v==524)v=0;else v=v+1;end else h=h+1;
 if(n==420000) begin
  if(pixels!=307200) $fatal(1,"active pixels %0d",pixels);
  $display("PASS 800x525 clocks; 640x480 coordinates; sync 96/2; 307200 pixels");$finish;
 end
end
endmodule
