`timescale 1ns/1ps
module tb_media_catalog;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,sd_ready=1,valid=0,last=0;reg[7:0] data=0;
 wire[5:0] image_count;wire req,done;wire[31:0]lba;wire[5:0]count;wire[3:0]status;
 reg[4:0]query=0;wire[87:0]name,dname;wire[1:0]item_type,dtype;wire[4:0]ordinal;
 wire[7:0]debug_root_byte;wire[15:0]debug_root_lba;
 integer scenario=0,active=0,pos=0,requests=0;reg[31:0] address;
 fat32_media_catalog #(.WATCHDOG_BITS(12),.READY_WATCHDOG_BITS(13)) dut(clk,rst,sd_ready,req,lba,data,valid,last,done,image_count,count,status,
  query,query,name,dname,item_type,dtype,ordinal,clk,debug_root_byte,debug_root_lba);
 function[7:0] byte_at;
 input integer sec,p;integer item,k,sz,c,next,typ,local_sec;reg[31:0]value;
 begin
  byte_at=0;item=0;k=p%32;sz=921654;c=0;next=0;typ=0;value=0;
  local_sec=scenario==11 && sec>=8192 ? sec-8192 : sec;
  if(scenario==11 && sec==0)case(p)
   450:byte_at=8'h0c;455:byte_at=8'h20;510:byte_at=8'h55;511:byte_at=8'haa;
  endcase
  else if(local_sec==0)case(p)
   12:byte_at=2;13:byte_at=1;14:byte_at=1;16:byte_at=1;36:byte_at=1;44:byte_at=scenario==8 ? 127 : 2;
   510:byte_at=scenario==2 ? 0 : 8'h55;511:byte_at=8'haa;
  endcase
  else if(local_sec==1)begin
   if(p/4==2)next=scenario==5 ? 2 : scenario==4 ? 32'h0fffffff : 5;
   if(p/4==127)next=5;
   if(p/4==5)next=32'h0fffffff;
   byte_at=(next>>(8*(p%4)))&255;
  end
  else if(local_sec==2 || local_sec==5 || (scenario==8 && local_sec==127))begin
   item=(local_sec==2 ? 0 : 16)+p/32;
   if((scenario==8 && local_sec==5) || scenario==1 || (scenario==0 && item>=17) || (scenario==11 && item>=1))byte_at=0;
   else if(scenario==8 || scenario==4 || scenario==5 || (scenario==0 && (item==0 || (item>=10 && item<16))))byte_at=k==0 ? 8'he5 : 0;
   else begin
    typ=(item==6 || item==8 || item==16) ? 2 : item==5 ? 3 : 1;
    c=100+item;sz=typ==2 ? 645632 : typ==3 ? 256 : 921654;
    case(k)
     0:byte_at="F";1:byte_at="A"+item;2,3,4,5,6,7:byte_at=" ";
     8:byte_at=typ==1 ? (item==9 ? "b" : "B") : typ==2 ? "R" : typ==3 ? "W" : "T";
     9:byte_at=typ==1 ? (item==9 ? "m" : "M") : typ==2 ? "V" : typ==3 ? "A" : "X";
     10:byte_at=typ==1 ? (item==9 ? "p" : "P") : typ==2 ? " " : typ==3 ? "V" : "T";
     11:byte_at=scenario!=0 ? 8'h20 : item==1 ? 8'h0f : item==2 ? 8'h10 : item==3 ? 8'h08 : 8'h20;
     26:byte_at=c&255;27:byte_at=(c>>8)&255;
     28,29,30,31:byte_at=(sz>>(8*(k-28)))&255;
    endcase
   end
  end else if(local_sec>=100 && local_sec<132)begin
   item=local_sec-100;typ=(item==6 || item==8 || item==16) ? 2 : 1;
   if(typ==1)begin
    case(p)
     0:byte_at="B";1:byte_at="M";10:byte_at=54;14:byte_at=40;
     18:byte_at=item==7 ? 1 : 128;19:byte_at=2;22:byte_at=224;23:byte_at=1;
     26:byte_at=1;28:byte_at=24;
    endcase
   end else begin
    case(p)
     0:byte_at="R";1:byte_at="V";2:byte_at="F";3:byte_at=item==8 ? "2" : "1";
     4:byte_at=item==8 ? 2 : 1;5:byte_at=1;6:byte_at=3;
     8:byte_at=128;9:byte_at=2;10:byte_at=224;11:byte_at=1;12:byte_at=1;
     16,17,18,19:byte_at=(307200>>(8*(p-16)))&255;
     20,21,22,23:byte_at=(48000>>(8*(p-20)))&255;
     24,25,26,27:byte_at=(16000>>(8*(p-24)))&255;
     28,29,30,31:byte_at=(16384>>(8*(p-28)))&255;
     32:byte_at=1;
    endcase
   end
  end
 end endfunction
 always @(negedge clk)begin
  valid=0;last=0;
  if(rst)begin active=0;pos=0;requests=0;end
  else if(req)begin
   if(active)$fatal(1,"request before prior sector_end");
   active=1;pos=0;address=lba;requests=requests+1;
  end else if(active && scenario!=10)begin
   if(pos<512)begin data=byte_at(address,pos);valid=1;pos=pos+1;end
   else begin last=1;active=0;end
  end
 end
 integer i;reg[1:0]expected_type;
 initial begin
  for(scenario=0;scenario<12;scenario=scenario+1)begin
   rst=1;sd_ready=scenario!=7 && scenario!=9;repeat(32)@(negedge clk);#1;rst=0;
   if(scenario==9)begin repeat(5000)@(negedge clk);sd_ready=1;end
   wait(done);repeat(2)@(negedge clk);
   if(scenario==0)begin
    if(count!=7 || image_count!=2 || status!=3)$fatal(1,"mixed count=%0d status=%0d",count,status);
    for(i=0;i<7;i=i+1)begin
     query=i;repeat(32)@(negedge clk);#1;
     expected_type=(i==0 || i==5) ? 1 : i==1 ? 3 : (i==2 || i==4 || i==6) ? 2 : 0;
     if(item_type!==expected_type || dtype!==expected_type || name!==dname || name[87:80]!=="F")$fatal(1,"catalog entry %0d item_type %0d",i,item_type);
     if(i==0 && ordinal!=0 || i==5 && ordinal!=1)$fatal(1,"BMP ordinal mismatch");
    end
   end else if(scenario==1 || scenario==4)begin if(count!=0 || status!=3)$fatal(1,"empty/end chain");end
   else if(scenario==2)begin if(status!=10 || count!=0)$fatal(1,"bad boot");end
   else if(scenario==3)begin if(count!=32 || status!=3)$fatal(1,"cap setup count=%0d",count);end
   else if(scenario==5)begin if(status!=13)$fatal(1,"loop status=%0d",status);end
   else if(scenario==6)begin if(count!=32)$fatal(1,"repeat reset");end
   else if(scenario==8)begin if(count!=0 || status!=3 || requests!=4)$fatal(1,"FAT entry at byte 508 boundary");end
   else if(scenario==7)begin if(status!=14 || requests!=0)$fatal(1,"no card timeout");end
   else if(scenario==9)begin if(status!=3 || count!=32)$fatal(1,"late card readiness status=%0d count=%0d",status,count);end
   else if(scenario==10)begin if(status!=15 || requests!=1)$fatal(1,"sector timeout status=%0d requests=%0d",status,requests);end
   else if(scenario==11)begin
    if(status!=3 || count!=1 || image_count!=1 || requests!=5 || debug_root_byte!="F" || debug_root_lba!=8194)
     $fatal(1,"partitioned FAT32 scan status=%0d count=%0d requests=%0d root=%02x lba=%0d",status,count,requests,debug_root_byte,debug_root_lba);
   end
  end
  $display("PASS mixed FAT32 catalog, BMP/RV/audio classification, unsupported files, fragmented root, EOF, errors, no-card timeout, late readiness, sector timeout, reset");$finish;
 end
 initial begin #20000000;$fatal(1,"catalog timeout scenario=%0d state=%0d kind=%0d count=%0d",scenario,dut.state,dut.kind,count);end
endmodule
