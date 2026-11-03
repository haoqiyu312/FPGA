`timescale 1ns/1ps
module tb_video_reader;
 parameter integer AUDIO_SUPPORT=0;
 parameter integer EXTERNAL_NAME=0;
 parameter integer SUBTITLE_SUPPORT=0;
 wire sub_valid,sub_done,sub_error;integer subtitle_bytes=0,srt_missing=0,srt_oversize=0,srt_broken=0;
 localparam [87:0] CUSTOM_NAME="MOVIE1  RV ";
 reg clk=0;always #5 clk=~clk;
 reg rst=1;wire req,wrreq,pvalid,bank,toggle;wire [31:0] lba,pdata;wire [3:0] status;wire [7:0] fps;
 reg [7:0] data=0;reg valid=0,last=0,ack=0,finish=0,consumed=0;
 integer scenario=0,active=0,index=0,address=0,delay_count=0;
 integer count=0,frames=0,hold_count=0,base,fb,db;
 reg pending=0,last_toggle=0;
 fat32_video_reader #(.WATCHDOG_BITS(22),.AUDIO_SUPPORT(AUDIO_SUPPORT),.EXTERNAL_NAME(EXTERNAL_NAME),.EXTERNAL_SUBTITLES(SUBTITLE_SUPPORT)) dut(
  .clk(clk),.rst(rst),.sd_ready(scenario!=6),.memory_ready(1'b1),
  .sector_req(req),.sector_lba(lba),.sector_byte(data),.sector_valid(valid),.sector_end(last),
  .write_req(wrreq),.write_ack(ack),.pixel_valid(pvalid),.pixel_data(pdata),
  .write_finish_toggle(finish),.frame_toggle(toggle),.consumed_toggle(consumed),
  .write_bank(bank),.status(status),.fps(fps),.selected_name(CUSTOM_NAME),.subtitle_byte_valid(sub_valid),.subtitle_done(sub_done),.subtitle_error(sub_error));
 function [7:0] cardbyte;
  input integer sec,pos;
  integer cluster,ordinal,offset,nxt,ent,value;
  begin
   cardbyte=0;
   if(sec==0 && scenario!=1)case(pos)
    450:cardbyte=12;455:cardbyte=8;510:cardbyte=8'h55;511:cardbyte=8'haa;
   endcase
   else if(sec==base)case(pos)
    12:cardbyte=2;13:cardbyte=8;14:cardbyte=32;16:cardbyte=1;
    37:cardbyte=2;44:cardbyte=2;510:cardbyte=8'h55;511:cardbyte=8'haa;
   endcase
   else if(sec==db+8 && scenario!=2 && pos<32)case(pos)
    0:cardbyte="V";1:cardbyte="I";2:cardbyte="D";3:cardbyte="E";4:cardbyte="O";
    5,6,7,10:cardbyte=" ";8:cardbyte="R";9:cardbyte="V";11:cardbyte=32;
    26:cardbyte=10;
    28,29,30,31:cardbyte=((scenario==8 ? 307712 : 614912) >> ((pos-28)*8))&255;
   endcase
   // First root cluster is full of deleted entries, forcing a directory FAT hop.
   else if(sec>=db && sec<db+8)begin
    if(pos%32==0)cardbyte=8'he5;
   end
   else if(sec>=fb && sec<fb+512)begin
    ent=(sec-fb)*128+pos/4;
    if(ent==2)nxt=3;
    else if(ent>=10 && (ent-10)%3==0 && ent<=460)
     nxt=scenario==4 ? 32'h0fffffff : ent+3;
    else nxt=32'h0fffffff;
    cardbyte=(nxt >> (8*(pos%4)))&255;
   end else if(sec>=db)begin
    cluster=(sec-db)/8+2;
    if(cluster>=10 && (cluster-10)%3==0)begin
     ordinal=(cluster-10)/3;offset=(ordinal*8+(sec-db)%8)*512+pos;
     if(offset<512)case(offset)
      0:cardbyte=scenario==3 ? "X" : "R";1:cardbyte="V";2:cardbyte="F";3:cardbyte="1";
      4,5:cardbyte=1;6:cardbyte=scenario==5 ? 6 : 5;
      8:cardbyte=8'h80;9:cardbyte=2;10:cardbyte=8'he0;11:cardbyte=1;
      12:cardbyte=scenario==9 ? 0 : 2;16,17,18,19:cardbyte=(307200 >> ((offset-16)*8))&255;
     endcase
     else begin
      value=(offset-512)/307200;
      cardbyte=value==0 ? 8'he0 : 8'h03;
     end
    end
   end
   if(SUBTITLE_SUPPORT && !srt_missing && sec==db+8 && pos>=32 && pos<64)begin
    if(pos<40)cardbyte=(EXTERNAL_NAME ? CUSTOM_NAME : "VIDEO   RV ") >> (87-(pos-32)*8-7);
    else case(pos)
     40:cardbyte="S";41:cardbyte="R";42:cardbyte="T";43:cardbyte=32;58:cardbyte=5;
     60,61,62,63:cardbyte=(srt_oversize ? 32769 : 5000) >> ((pos-60)*8);
     default:cardbyte=0;
    endcase
   end
   if(SUBTITLE_SUPPORT && sec>=fb && sec<fb+512 && (sec-fb)*128+pos/4==5)
    cardbyte=(srt_broken ? 32'h0fffffff : 8) >> (8*(pos%4));
   if(SUBTITLE_SUPPORT && sec>=db+24 && sec<db+32)cardbyte=((sec-db-24)*512+pos)%251;
   if(SUBTITLE_SUPPORT && sec>=db+48 && sec<db+56)cardbyte=(4096+(sec-db-48)*512+pos)%251;
   if(EXTERNAL_NAME && sec==db+8 && scenario!=2 && pos<11)cardbyte=CUSTOM_NAME[87-pos*8-:8];
  end
 endfunction
 always @(posedge clk)if(sub_valid)begin
  if(data!==subtitle_bytes%251)$fatal(1,"subtitle byte order %d data %d",subtitle_bytes,data);
  subtitle_bytes=subtitle_bytes+1;
 end
 always @(negedge clk)begin
  valid=0;last=0;ack=wrreq;
  if(req)begin
   if(active)$fatal(1,"overlapping request");
   address=lba;active=1;index=0;delay_count=3;
   if(pending)$fatal(1,"read ahead before bank release");
  end else if(active && scenario!=7)begin
   if(delay_count!=0)delay_count=delay_count-1;
   else if(index<512)begin data=cardbyte(address,index);valid=1;index=index+1;end
   else begin last=1;active=0;end
  end
  if(pvalid)begin
   if(pdata !== (frames%2==0 ? 32'hff000000 : 32'h0000ff00))$fatal(1,"pixel/order mismatch %0d",count);
   if(bank!==(frames%2==0))$fatal(1,"writer bank ownership");
   count=count+1;
   if(count==307200)finish=~finish;
  end
  if(toggle!=last_toggle)begin
   if(count!=307200)$fatal(1,"published incomplete frame");
   last_toggle=toggle;pending=1;hold_count=100;frames=frames+1;count=0;
  end
  if(pending)begin
   if(pvalid)$fatal(1,"write while waiting for presentation");
   if(hold_count==0)begin consumed=toggle;pending=0;end
   else hold_count=hold_count-1;
  end
 end
 initial begin
  if(!$value$plusargs("scenario=%d",scenario))scenario=0;
  if($value$plusargs("srt_missing=%d",srt_missing))begin end
  if($value$plusargs("srt_oversize=%d",srt_oversize))begin end
  if($value$plusargs("srt_broken=%d",srt_broken))begin end
  base=scenario==1 ? 0 : 2048;fb=base+32;db=fb+512;
  #40;rst=0;
  if(scenario<=1)begin
   wait(frames==3);#20;
   if(fps!=5)$fatal(1,"fps");
   if(SUBTITLE_SUPPORT)begin
    if(!sub_done || sub_error!=(srt_oversize || srt_broken))$fatal(1,"subtitle result flags");
    if(subtitle_bytes!=(srt_missing || srt_oversize ? 0 : srt_broken ? 4096 : 5000))$fatal(1,"subtitle size/reloaded during loop: %d",subtitle_bytes);
   end
   $display("PASS video scenario=%0d: 3 complete frames, fragmented directory/file, loop, banks and commit",scenario);
  end else begin
   wait(status>=10);#20;
   if(status!=(scenario==2 ? 11 : (scenario==3 || scenario==5 || scenario==8 || scenario==9) ? 12 : scenario==4 ? 13 : 14))
    $fatal(1,"wrong error %0d",status);
   if(frames!=0)$fatal(1,"published corrupt frame");
   $display("PASS video scenario=%0d: error %0d",scenario,status);
  end
  $finish;
 end
 initial begin #150000000;$fatal(1,"timeout");end
endmodule
