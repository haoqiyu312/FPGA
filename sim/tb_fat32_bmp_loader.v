`timescale 1ns/1ps
module tb_fat32_bmp_loader;
 reg clk=0; always #5 clk=~clk;
 reg rst=1; wire req; wire [31:0] lba; reg [7:0] data;
 reg valid=0,last=0,ack=0,finish=0;
 wire wrreq,pvalid,ready; wire [31:0] pdata; wire [3:0] status;
 integer which=0;
 integer scenario=0,active=0,index=0,delay_count=0,count=0;
 reg [31:0] address; reg [7:0] bmp[0:921653];
 integer offset,pixel,c,k,fatc,chain;
 fat32_bmp_loader #(.WATCHDOG_BITS(24),.SELECT_BY_NAME(1)) dut(clk,rst,1'b1,1'b1,
  req,lba,data,valid,last,wrreq,ack,pvalid,pdata,finish,ready,status,which[4:0],,,);
 function [7:0] cardbyte;
  input integer sec; input integer pos;
  integer base,fb,db,cluster,num,fo,ent,nxt,start_cluster,entry_num;
  begin
   base=(scenario==5)?0:2048; fb=base+32; db=base+32+1024;
   start_cluster=5+which*1024;
   cardbyte=0;
   if (sec==0 && scenario!=5) begin
    case(pos)
     450:cardbyte=8'h0c; 455:cardbyte=8'h08;
     510:cardbyte=8'h55;511:cardbyte=8'haa;
    endcase
   end else if (sec==base) begin
    case(pos)
     12:cardbyte=2;13:cardbyte=8;14:cardbyte=32;16:cardbyte=2;
     37:cardbyte=2;44:cardbyte=2;510:cardbyte=8'h55;511:cardbyte=8'haa;
    endcase
   end else if (sec==db) begin
    if(scenario!=2 && pos<128) begin
     entry_num=pos/32;
     case(pos%32)
      0:cardbyte="P";1:cardbyte="I";2:cardbyte="C";
      3:cardbyte="0";4:cardbyte="1"+entry_num;
      5,6,7:cardbyte=" ";8:cardbyte="B";9:cardbyte="M";10:cardbyte="P";
      11:cardbyte=8'h20;26:cardbyte=(5+entry_num*1024)&255;27:cardbyte=(5+entry_num*1024)>>8;
      28:cardbyte=921654 & 255;29:cardbyte=(921654>>8)&255;
      30:cardbyte=(921654>>16)&255;31:cardbyte=(921654>>24)&255;
     endcase
    end
   end else if(sec>=fb && sec<fb+512) begin
    ent=(sec-fb)*128+pos/4;
    if(ent>=start_cluster && ((ent-start_cluster)%4)==0) begin
     nxt=(ent==start_cluster+900 || scenario==4)?32'h0fffffff:ent+4;
     cardbyte=(nxt >> (8*(pos%4))) & 255;
    end
   end else if(sec>=db) begin
    cluster=((sec-db)/8)+2;
    if(cluster>=start_cluster && ((cluster-start_cluster)%4)==0) begin
     num=(cluster-start_cluster)/4;
     fo=(num*8+((sec-db)%8))*512+pos;
     if(fo<921654) cardbyte=bmp[fo];
     if(scenario==3 && fo==30) cardbyte=1;
    end
   end
  end
 endfunction
 always @(negedge clk) begin
  valid=0;last=0;ack=wrreq;
  if(req) begin
   if(active) $fatal(1,"overlapping sector request");
   address=lba;active=1;index=0;delay_count=2;
  end else if(active) begin
   if(delay_count!=0) delay_count=delay_count-1;
   else if(index<512) begin
    data=cardbyte(address,index);valid=1;index=index+1;
   end else begin last=1;active=0;end
  end
 end
 always @(posedge clk) begin
  if(pvalid) begin
   if(count>=307200) $fatal(1,"too many pixels");
   offset=54+count*3;
   if(pdata!=={bmp[offset+2],bmp[offset+1],bmp[offset],8'h00})
    $fatal(1,"RGB mismatch at pixel %0d",count);
   count=count+1;
  end
 end
 initial begin
  if(!$value$plusargs("scenario=%d",scenario)) scenario=0;
  if(!$value$plusargs("image=%d",which))which=0;
  $readmemh("bmp_bytes.hex",bmp);
  #40;rst=0;
  if(scenario==0 || scenario==5) begin
   wait(count==307200);
   repeat(5) @(negedge clk);finish=1;
   wait(ready); #20;
   if(dut.first_cluster!=5+which*1024)$fatal(1,"wrong filename selected");
   if(count!=307200 || status!=5) $fatal(1,"bad final state");
   $display("PASS scenario=%0d selected PIC0%0d fragmented FAT chain, all 307200 RGB pixels, commit handshake",scenario,which+1);
  end else begin
   wait(status>=10);#20;
   if(scenario==2 && status!=11) $fatal(1,"missing file status");
   if(scenario==3 && status!=12) $fatal(1,"invalid BMP status");
   if(scenario==4 && status!=13) $fatal(1,"broken FAT chain status");
   if(ready) $fatal(1,"bad image shown");
   $display("PASS scenario=%0d rejected invalid input, status=%0d",scenario,status);
  end
  $finish;
 end
 initial begin #100000000; $fatal(1,"simulation timeout state=%0d status=%0d count=%0d",dut.state,status,count); end
endmodule
