`timescale 1ns/1ps
module tb_audio_video_reader;
 reg clk=0;always #5 clk=~clk;
 reg rst=1;wire req,wrreq,pvalid,bank,toggle,aenabled,avalid;
 wire [31:0] lba,pdata;wire [3:0] status;wire [7:0] fps,adata;wire [13:0] aaddress;
 reg [7:0] data=0;reg valid=0,last=0,ack=0,finish=0,consumed=0;
 integer scenario=0,active=0,index=0,address=0,delay_count=0;
 integer pixels=0,audio_bytes=0,frames=0,hold_count=0;
 reg pending=0,last_toggle=0;
 fat32_video_reader #(.WATCHDOG_BITS(20),.FRAME_PIXELS(512),.AUDIO_SUPPORT(1)) dut(
  .clk(clk),.rst(rst),.sd_ready(1'b1),.memory_ready(1'b1),
  .sector_req(req),.sector_lba(lba),.sector_byte(data),.sector_valid(valid),.sector_end(last),
  .write_req(wrreq),.write_ack(ack),.pixel_valid(pvalid),.pixel_data(pdata),
  .write_finish_toggle(finish),.frame_toggle(toggle),.consumed_toggle(consumed),
  .write_bank(bank),.status(status),.fps(fps),.audio_enabled(aenabled),
  .audio_valid(avalid),.audio_address(aaddress),.audio_data(adata));
 function [7:0] cardbyte;
  input integer sec,pos;
  integer ent,nxt,cluster,offset,frame,within_frame,value;
  begin
   cardbyte=0;
   if(sec==0)case(pos)
    12:cardbyte=2;13:cardbyte=1;14:cardbyte=32;16:cardbyte=1;
    36:cardbyte=4;44:cardbyte=2;510:cardbyte=8'h55;511:cardbyte=8'haa;
   endcase
   else if(sec==36 && pos<32)case(pos)
    0:cardbyte="V";1:cardbyte="I";2:cardbyte="D";3:cardbyte="E";4:cardbyte="O";
    5,6,7,10:cardbyte=" ";8:cardbyte="R";9:cardbyte="V";11:cardbyte=32;26:cardbyte=10;
    28,29,30,31:cardbyte=((scenario==3 ? 51199 : 51200) >> ((pos-28)*8))&255;
   endcase
   else if(sec>=32 && sec<36)begin
    ent=(sec-32)*128+pos/4;
    nxt=ent>=10 && (ent-10)%3==0 && ent<307 ? ent+3 : 32'h0fffffff;
    if(scenario==4 && ent==40)nxt=32'h0fffffff;
    cardbyte=(nxt >> (8*(pos%4)))&255;
   end else if(sec>=44)begin
    cluster=sec-36+2;
    if((cluster-10)%3==0)begin
     offset=((cluster-10)/3)*512+pos;
     if(offset<512)case(offset)
      0:cardbyte="R";1:cardbyte="V";2:cardbyte="F";3:cardbyte="2";
      4:cardbyte=2;5:cardbyte=1;6:cardbyte=scenario==1 ? 2 : 3;
      8:cardbyte=8'h80;9:cardbyte=2;10:cardbyte=8'he0;11:cardbyte=1;
      12:cardbyte=3;17:cardbyte=2;
      20,21,22,23:cardbyte=((scenario==2 ? 44100 : 48000) >> ((offset-20)*8))&255;
      24,25,26,27:cardbyte=(16000 >> ((offset-24)*8))&255;
      28,29,30,31:cardbyte=(16384 >> ((offset-28)*8))&255;
      32:cardbyte=scenario==6 ? 99 : 1;
     endcase
     else begin
      frame=(offset-512)/16896;within_frame=(offset-512)%16896;
      if(within_frame<512)cardbyte=frame==1 ? 8'h03 : 8'he0;
      else cardbyte=within_frame-512<16000 ? (frame*17+within_frame-512)%256 : 255;
     end
    end
   end
  end
 endfunction
 always @(posedge clk)if(!rst && avalid)begin
  if(!aenabled || aaddress!==audio_bytes[13:0])$fatal(1,"audio address/enable mismatch");
  if(adata!==(audio_bytes<16000 ? ((frames%3)*17+audio_bytes)%256 : 255))
   $fatal(1,"audio order/padding mismatch at %0d",audio_bytes);
  audio_bytes=audio_bytes+1;
 end
 always @(negedge clk)begin
  valid=0;last=0;ack=wrreq;
  if(req)begin
   if(active || pending)$fatal(1,"overlapping request or reused bank before release");
   address=lba;active=1;index=0;delay_count=3;
  end else if(active)begin
   if(delay_count!=0)delay_count=delay_count-1;
   else if(index<512)begin data=cardbyte(address,index);valid=1;index=index+1;end
   else begin last=1;active=0;end
  end
  if(pvalid)begin
   if(pdata !== (frames%3==1 ? 32'h0000ff00 : 32'hff000000))$fatal(1,"pixel order");
   if(bank!==(frames%2==0))$fatal(1,"writer bank");
   pixels=pixels+1;
   if(pixels==512 && scenario!=5)finish=~finish;
  end
  if(toggle!=last_toggle)begin
   if(pixels!=512 || audio_bytes!=16384)$fatal(1,"published incomplete picture/audio");
   last_toggle=toggle;pending=1;hold_count=50;frames=frames+1;pixels=0;audio_bytes=0;
  end
  if(pending)begin
   if(pvalid || avalid)$fatal(1,"bank written while awaiting release");
   if(hold_count==0)begin consumed=toggle;pending=0;end
   else hold_count=hold_count-1;
  end
 end
 initial begin
  if(!$value$plusargs("scenario=%d",scenario))scenario=0;
  #40;rst=0;
  if(scenario==0)begin
   wait(frames==4);#20;
   if(fps!=3 || !aenabled)$fatal(1,"audio metadata");
   $display("PASS RVF2: fragmented file, audio pixels/padding, commit, banks and loop");
  end else begin
   wait(status>=10);#20;
   if(status!=(scenario==4 ? 13 : scenario==5 ? 14 : 12))$fatal(1,"wrong RVF2 error %0d",status);
   if(frames!=0)$fatal(1,"published corrupt RVF2 frame");
   $display("PASS RVF2 scenario=%0d error=%0d",scenario,status);
  end
  $finish;
 end
 initial begin #60000000;$fatal(1,"timeout");end
endmodule
