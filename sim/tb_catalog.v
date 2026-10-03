`timescale 1ns/1ps
module tb_catalog;
 reg clk=0;always #5 clk=~clk;
 reg rst=1;wire req;wire [31:0]lba;reg[7:0]data;
 reg valid=0,last=0,ack=0,finish=0;
 wire wrreq,pvalid,ready,catalog_valid;wire[31:0]pdata;wire[3:0]status;wire[5:0]total;wire[87:0]file_name;
 integer selected=0,scenario=0,active=0,index=0,delay_count=0,count=0;
 reg[31:0]address;reg[7:0]bmp[0:921653];
 fat32_bmp_loader #(.AUTO_SCAN(1),.WATCHDOG_BITS(24)) dut(
 .clk(clk),.rst(rst),.sd_ready(1'b1),.memory_ready(1'b1),.sector_req(req),.sector_lba(lba),
 .sector_byte(data),.sector_valid(valid),.sector_end(last),.write_req(wrreq),.write_ack(ack),
 .pixel_valid(pvalid),.pixel_data(pdata),.write_finish_toggle(finish),.image_ready(ready),
 .status(status),.image_index(selected[4:0]),.image_total(total),.catalog_valid(catalog_valid),.image_name(file_name));
 function integer start_cluster;
 input integer item;
 begin start_cluster=16+item*4096;end
 endfunction
 function[7:0] cardbyte;
 input integer sec,pos;
 integer fb,db,ent,item,fo,nxt,cluster,slot,entrykind,start;
 begin
  fb=2080;db=3104;cardbyte=0;item=0;entrykind=0;
  if(sec==0)case(pos)450:cardbyte=8'h0c;455:cardbyte=8'h08;510:cardbyte=8'h55;511:cardbyte=8'haa;endcase
  else if(sec==2048)case(pos)
   12:cardbyte=2;13:cardbyte=1;14:cardbyte=32;16:cardbyte=2;37:cardbyte=2;
   44:cardbyte=2;510:cardbyte=8'h55;511:cardbyte=8'haa;
  endcase
  else if(sec==db || sec==db+2)begin
   slot=pos/32;
   // Every unused entry before end is deleted; never prematurely terminate a sector.
   entrykind=1;
   if(sec==db)case(slot)
    0:entrykind=1;1:entrykind=2;2:entrykind=3;3:entrykind=4;4:entrykind=5;5:entrykind=6;
    6:begin entrykind=7;item=0;end
    7:begin entrykind=7;item=1;end
    8:begin entrykind=8;item=2;end
   endcase
   else case(slot)
    0:begin entrykind=7;item=3;end
    1:begin entrykind=7;item=4;end
    2:begin entrykind=7;item=5;end
    default:if(scenario!=2)entrykind=0;
   endcase
   if(scenario==3)begin entrykind=7;item=1;end
   case(pos%32)
    0:cardbyte=entrykind==0 ? 0 : entrykind==1 ? 8'he5 : "A"+slot;
    1,2,3,4,5,6,7:cardbyte=" ";
    8:cardbyte=entrykind==8 ? "b" : entrykind==5 ? "J" : "B";
    9:cardbyte=entrykind==8 ? "m" : entrykind==5 ? "P" : "M";
    10:cardbyte=entrykind==8 ? "p" : entrykind==5 ? "G" : "P";
    11:cardbyte=entrykind==2 ? 8'h0f : entrykind==3 ? 8'h10 : entrykind==4 ? 8'h08 : 8'h20;
    26:cardbyte=start_cluster(item)&255;27:cardbyte=(start_cluster(item)>>8)&255;
    28:cardbyte=entrykind==6 ? 54 : 921654&255;
    29:cardbyte=entrykind==6 ? 0 : (921654>>8)&255;
    30:cardbyte=entrykind==6 ? 0 : (921654>>16)&255;
    31:cardbyte=0;
   endcase
  end else if(sec>=fb && sec<fb+512)begin
   ent=(sec-fb)*128+pos/4;nxt=0;
   if(ent==2)nxt=4;
   else if(ent==4)nxt=32'h0fffffff;
   else if(ent>=16)begin
    item=(ent-16)/4096;start=start_cluster(item);
    if(item<=5 && ent>=start && ent<=start+3600 && (ent-start)%2==0)
      nxt=ent==start+3600 ? 32'h0fffffff : ent+2;
   end
   cardbyte=(nxt>>(8*(pos%4)))&255;
  end else if(sec>=db)begin
   cluster=sec-db+2;
   if(cluster>=16)begin
    item=(cluster-16)/4096;start=start_cluster(item);
    if(item<=5 && cluster>=start && cluster<=start+3600 && (cluster-start)%2==0)begin
     fo=((cluster-start)/2)*512+pos;
     if(fo<921654)cardbyte=bmp[fo];
     // Wrong dimensions and compression are skipped during catalog enumeration.
     if((item==0 || scenario==1) && fo==18)cardbyte=1;
     if(item==4 && fo==30)cardbyte=1;
    end
   end
  end
 end
 endfunction
 always @(negedge clk)begin
  valid=0;last=0;ack=wrreq;
  if(req)begin
   if(active)$fatal(1,"overlapping requests");
   address=lba;active=1;index=0;delay_count=2;
  end else if(active)begin
   if(delay_count!=0)delay_count=delay_count-1;
   else if(index<512)begin data=cardbyte(address,index);valid=1;index=index+1;end
   else begin last=1;active=0;end
  end
 end
 integer offset,expected_item;reg[87:0]expected_name;
 always @(posedge clk)if(pvalid)begin
  if(!catalog_valid)$fatal(1,"pixels before full catalog");
  offset=54+count*3;
  if(pdata!=={bmp[offset+2],bmp[offset+1],bmp[offset],8'h00})$fatal(1,"pixel mismatch %d",count);
  count=count+1;
 end
 initial begin
  if(!$value$plusargs("image=%d",selected))selected=0;
  if(!$value$plusargs("scenario=%d",scenario))scenario=0;
  $readmemh("bmp_bytes.hex",bmp);#40;rst=0;
  if(scenario==1)begin
   wait(status>=10);#20;
   if(status!=11 || total!=0 || !catalog_valid || count!=0 || ready || wrreq)$fatal(1,"empty catalog handling");
   $display("PASS unsupported BMPs skipped, no valid images, error 11, no writes");
  end else begin
   wait(count==307200);repeat(5)@(negedge clk);finish=1;wait(ready);#20;
   expected_item=selected==0 ? 1 : selected==1 ? 2 : selected==2 ? 3 : selected==3 ? 5 : 1;
   if(total!=(scenario==3 ? 32 : 4) || dut.first_cluster!=start_cluster(scenario==3 ? 1 : expected_item) || status!=5)$fatal(1,"catalog selection/count total=%d selectedcluster=%d",total,dut.first_cluster);
   expected_name=selected==1 ? "I       bmp" : selected==2 ? "A       BMP" : selected==3 ? "C       BMP" : "H       BMP";
   if(scenario==3)expected_name="P       BMP";
   if(file_name!==expected_name)$fatal(1,"wrong selected filename %s expected %s",file_name,expected_name);
   $display("PASS auto scan image=%d arbitrary names, lowercase BMP, header filtering, fragmented root/files, directory termination=%d",selected,scenario);
  end
  $finish;
 end
 initial begin #100000000;$fatal(1,"timeout state=%d kind=%d count=%d",dut.state,dut.kind,count);end
endmodule
