`timescale 1ns/1ps
// Capture actual transparent OSD RTL over the first sample photo, off and on.
module tb_osd_render;
reg clk=0;always #10 clk=~clk;
reg rst=1;reg[9:0]x=100,y=100;reg auto_mode=0;
wire active;wire[23:0]rgb;reg[7:0]bmp[0:921653];
image_status_osd dut(clk,rst,x,y,1'b1,1'b1,4'd5,5'd0,6'd4,auto_mode,2'b01,1'b0,active,rgb,"PIC01   BMP");
integer fd,px,py,scene,offset;reg[23:0]color;
task tick;begin @(posedge clk);#1;end endtask
task snapshot;begin repeat(4)tick;x=0;y=0;tick;x=100;y=100;tick;end endtask
initial begin
 $readmemh("bmp_bytes.hex",bmp);
 #1;rst=0;#10;rst=1;
 for(scene=0;scene<2;scene=scene+1)begin
  fd=$fopen($sformatf("osd_%0d.ppm",scene),"w");
  if(fd==0)$fatal(1,"cannot open preview");
  $fwrite(fd,"P3\n640 480\n255\n");
  auto_mode=scene==1;snapshot;
  for(py=0;py<480;py=py+1)begin
   for(px=0;px<640;px=px+1)begin
    x=px;y=py;tick;offset=54+((479-py)*640+px)*3;
    color=active ? rgb : {bmp[offset+2],bmp[offset+1],bmp[offset]};
    $fwrite(fd,"%0d %0d %0d\n",color[23:16],color[15:8],color[7:0]);
   end
  end
  $fclose(fd);
 end
 $display("Wrote transparent OSD off/on captures from RTL over sample photo");$finish;
end
endmodule
