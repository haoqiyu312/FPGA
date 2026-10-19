// Immutable root-directory catalog, built once per card/reset. First 32 regular
// files in directory order; BMP/RV headers are checked before enabling OPEN.
// Metadata RAM is only written during scanning. Readers must gate with done.
module fat32_media_catalog #(
 parameter WATCHDOG_BITS=28,
 parameter READY_WATCHDOG_BITS=30
)(
 input wire clk,rst,sd_ready,
 output reg sector_req,output reg[31:0] sector_lba,
 input wire[7:0] sector_byte,input wire sector_valid,sector_end,
 output reg done,output reg[5:0] image_count,output reg[5:0] count,output reg[3:0] status,
 input wire[4:0] query_index,display_index,
 output wire[87:0] query_name,display_name,
 output wire[1:0] query_type,display_type,
 output wire[4:0] query_image_index,input wire display_clk,
 output reg[7:0] debug_root_byte,output reg[15:0] debug_root_lba
);
 localparam WAIT=0,REQ=1,RX=2,DECIDE=3,STORE=4,RESUME=5,ADVANCE=6,FINISH=7,FAIL=8,DRAIN=9;
 localparam BOOT=0,BPB=1,DIR=2,HEADER=3,FAT=4;
 reg[3:0] state;reg[2:0] kind;
 reg[8:0] offset,resume_offset;
 reg[31:0] volume,partition,fat_base,data_base,fat_size,root,cluster,next_cluster,dir_lba;
 reg[15:0] sector_size,reserved,signature;
 reg[7:0] spc,nfats,part_type,dir_sector;reg[3:0] shift;
 reg[15:0] hops;reg resumed,ended,candidate_found;
 reg[87:0] entry_name;
 reg[31:0] entry_cluster,entry_size;
 reg[7:0] attr;reg live;
 reg[1:0] candidate_type,checked_type;
 reg[31:0] magic,dib,width,height,pixel_offset,compression,frame_count,frame_bytes;
 reg[15:0] bmp_planes,bmp_bits,rv_width,rv_height;
 reg[7:0] rv_version,rv_format,rv_fps;
 reg[31:0] rate,samples,audio_bytes,audio_format;
 reg[4:0] bmp_index;
 reg[WATCHDOG_BITS-1:0] watchdog;
 reg[READY_WATCHDOG_BITS-1:0] ready_watchdog;
 // Byte-wide true dual-port RAM fits one 9K block. Sixteen byte slots
 // per entry: type/ordinal first, then eleven FAT name bytes. Query results
 // settle in <20 SD clocks; GT911 reports are milliseconds apart. Pixel
 // prefetch starts at the card edge, before its icon and filename regions.
 (* ram_style="bram" *) reg[7:0] metadata[0:511];
 (* async_reg="true" *) reg[4:0] query_meta,query_sync;
 reg[3:0] store_byte;
 reg[3:0] query_word=0,query_response_word=0,display_word=0,display_response_word=0;
 reg[4:0] query_previous=0,query_tag=0,display_previous=0,display_tag=0;
 reg query_response_valid=0;
 (* async_reg="true" *) reg[1:0] display_done=0;
 reg[7:0] query_raw,display_raw;
 reg[94:0] query_data,display_data;
 wire[8:0] metadata_address=state==STORE ? {count[4:0],store_byte} : {query_sync,query_word};
 wire[7:0] metadata_write=store_byte==0 ? {1'b0,checked_type,bmp_index} : entry_name[87-(store_byte-1'b1)*8-:8];
 always @(posedge clk)begin
  query_meta<=query_index;query_sync<=query_meta;query_previous<=query_sync;
  if(!rst && state==STORE)metadata[metadata_address]<=metadata_write;
  query_raw<=metadata[metadata_address];query_response_word<=query_word;query_tag<=query_sync;
  query_response_valid<=done && state!=STORE;
  if(!done || query_previous!=query_sync)query_word<=0;
  else if(query_word<12)query_word<=query_word+1'b1;
  if(query_response_valid && query_tag==query_sync)begin
   if(query_response_word==0)query_data[6:0]<=query_raw[6:0];
   else if(query_response_word<=11)query_data[94:7]<={query_data[86:7],query_raw};
  end
 end
 always @(posedge display_clk)begin
  display_done<={display_done[0],done};
  display_raw<=metadata[{display_index,display_word}];
  display_response_word<=display_word;display_tag<=display_index;display_previous<=display_index;
  if(!display_done[1] || display_previous!=display_index)display_word<=0;
  else if(display_word<12)display_word<=display_word+1'b1;
  if(display_done[1] && display_tag==display_index)begin
   if(display_response_word==0)display_data[6:0]<=display_raw[6:0];
   else if(display_response_word<=11)display_data[94:7]<={display_data[86:7],display_raw};
  end
 end
 assign query_name=query_data[94:7];assign display_name=display_data[94:7];
 assign query_type=query_data[6:5];assign display_type=display_data[6:5];
 assign query_image_index=query_data[4:0];
 wire valid_spc=spc==1 || spc==2 || spc==4 || spc==8 || spc==16 || spc==32 || spc==64 || spc==128;
 wire[8:0] fat_offset={cluster[6:0],2'b00};
 wire after_resume=!resumed || offset>resume_offset;
 function[7:0] upper;input[7:0] a;begin upper=a>=97 && a<=122 ? a-32 : a;end endfunction
 wire bmp_ext=upper(entry_name[23:16])=="B" && upper(entry_name[15:8])=="M" && upper(entry_name[7:0])=="P";
 wire rv_ext=upper(entry_name[23:16])=="R" && upper(entry_name[15:8])=="V" && entry_name[7:0]==" ";
 wire wav_ext=upper(entry_name[23:16])=="W" && upper(entry_name[15:8])=="A" && upper(entry_name[7:0])=="V";
 wire mp3_ext=upper(entry_name[23:16])=="M" && upper(entry_name[15:8])=="P" && upper(entry_name[7:0])=="3";
 wire aac_ext=upper(entry_name[23:16])=="A" && upper(entry_name[15:8])=="A" && upper(entry_name[7:0])=="C";
 wire ogg_ext=upper(entry_name[23:16])=="O" && upper(entry_name[15:8])=="G" && upper(entry_name[7:0])=="G";
 wire wma_ext=upper(entry_name[23:16])=="W" && upper(entry_name[15:8])=="M" && upper(entry_name[7:0])=="A";
 wire m4a_ext=upper(entry_name[23:16])=="M" && entry_name[15:8]=="4" && upper(entry_name[7:0])=="A";
 wire audio_ext=wav_ext || mp3_ext || aac_ext || ogg_ext || wma_ext || m4a_ext;
 wire valid_bmp=magic[15:0]==16'h4d42 && dib>=40 && width==640 && height==480 &&
  bmp_planes==1 && bmp_bits==24 && compression==0 && pixel_offset>=54 &&
  pixel_offset<=entry_size && entry_size-pixel_offset>=921600;
 wire rv1=magic==32'h31465652 && rv_version==1;
 wire rv2=magic==32'h32465652 && rv_version==2 && rv_fps>=3 && rv_fps<=5 &&
  rate==48000 && audio_format==1 &&
  ((rv_fps==3 && samples==16000 && audio_bytes==16384) ||
   (rv_fps==4 && samples==12000 && audio_bytes==12288) ||
   (rv_fps==5 && samples==9600 && audio_bytes==9728));
 wire valid_rv=(rv1 || rv2) && rv_format==1 && rv_width==640 && rv_height==480 &&
  rv_fps>=1 && rv_fps<=5 && frame_count!=0 && frame_count<=13981 && frame_bytes==307200 && entry_size>=307712;
 function[31:0] address;input[31:0] c;begin address=data_base+((c-2)<<shift);end endfunction
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   store_byte<=0;state<=WAIT;kind<=BOOT;sector_req<=0;sector_lba<=0;done<=0;count<=0;status<=0;
   offset<=0;resume_offset<=0;volume<=0;partition<=0;fat_base<=0;data_base<=0;fat_size<=0;
   root<=0;cluster<=0;next_cluster<=0;dir_lba<=0;sector_size<=0;reserved<=0;signature<=0;
   spc<=0;nfats<=0;part_type<=0;dir_sector<=0;shift<=0;hops<=0;resumed<=0;ended<=0;candidate_found<=0;
   entry_name<=0;entry_cluster<=0;entry_size<=0;attr<=0;live<=0;candidate_type<=0;checked_type<=0;
   magic<=0;dib<=0;width<=0;height<=0;pixel_offset<=0;compression<=0;frame_count<=0;frame_bytes<=0;
   bmp_planes<=0;bmp_bits<=0;rv_width<=0;rv_height<=0;rv_version<=0;rv_format<=0;rv_fps<=0;
   rate<=0;samples<=0;audio_bytes<=0;audio_format<=0;bmp_index<=0;image_count<=0;watchdog<=0;ready_watchdog<=0;
   debug_root_byte<=0;debug_root_lba<=0;
  end else begin
   sector_req<=0;if(state!=STORE)store_byte<=0;
   // The transport is held in reset during the power-on settling period.
   // Give initialization its own timeout; a sector timeout starts only after
   // the card has reported ready and the first read has been requested.
   if(state==WAIT && !sd_ready)ready_watchdog<=ready_watchdog+1'b1;
   else ready_watchdog<=0;
   if(state==WAIT || sector_valid || done)watchdog<=0;
   else watchdog<=watchdog+1'b1;
   case(state)
    WAIT:if(sd_ready)begin kind<=BOOT;sector_lba<=0;status<=1;state<=REQ;end
    REQ:begin sector_req<=1;offset<=0;candidate_found<=0;state<=RX;end
    RX:begin
     if(sector_valid)begin
      offset<=offset+1'b1;
      if(kind==BOOT || kind==BPB)case(offset)
       11,12:sector_size[(offset-11)*8+:8]<=sector_byte;
       13:spc<=sector_byte;
       14,15:reserved[(offset-14)*8+:8]<=sector_byte;
       16:nfats<=sector_byte;
       36,37,38,39:fat_size[(offset-36)*8+:8]<=sector_byte;
       44,45,46,47:root[(offset-44)*8+:8]<=sector_byte;
       450:part_type<=sector_byte;
       454,455,456,457:partition[(offset-454)*8+:8]<=sector_byte;
       510,511:signature[(offset-510)*8+:8]<=sector_byte;
      endcase
      if(kind==DIR)begin
       if(offset==0 && hops==0 && dir_sector==0 && !resumed)debug_root_byte<=sector_byte;
       if(offset[4:0]<=10)entry_name[87-offset[4:0]*8-:8]<=sector_byte;
       case(offset[4:0])
        0:begin live<=sector_byte!=0 && sector_byte!=8'he5;entry_cluster<=0;entry_size<=0;
         if(sector_byte==0 && after_resume)ended<=1;end
        11:attr<=sector_byte;
        20:entry_cluster[23:16]<=sector_byte;
        21:entry_cluster[31:24]<={4'd0,sector_byte[3:0]};
        26,27:entry_cluster[(offset[4:0]-26)*8+:8]<=sector_byte;
        28,29,30:entry_size[(offset[4:0]-28)*8+:8]<=sector_byte;
        31:if(after_resume && !ended && live && (attr&8'h18)==0 && attr!=8'h0f)begin
         entry_size[31:24]<=sector_byte;resume_offset<=offset;resumed<=1;dir_lba<=sector_lba;
         candidate_type<=bmp_ext ? 1 : rv_ext ? 2 : audio_ext ? 3 : 0;
         // Ignore remaining bytes of this directory sector and reread it later.
         candidate_found<=1;state<=DRAIN;
        end
       endcase
      end
      if(kind==HEADER)begin
       case(offset)
        0,1,2,3:magic[offset*8+:8]<=sector_byte;
        4:rv_version<=sector_byte;5:rv_format<=sector_byte;6:rv_fps<=sector_byte;
        8,9:rv_width[(offset-8)*8+:8]<=sector_byte;
        10,11:begin rv_height[(offset-10)*8+:8]<=sector_byte;pixel_offset[(offset-10)*8+:8]<=sector_byte;end
        12,13:begin frame_count[(offset-12)*8+:8]<=sector_byte;pixel_offset[(offset-10)*8+:8]<=sector_byte;end
        14,15:begin frame_count[(offset-12)*8+:8]<=sector_byte;dib[(offset-14)*8+:8]<=sector_byte;end
        16,17:begin frame_bytes[(offset-16)*8+:8]<=sector_byte;dib[(offset-14)*8+:8]<=sector_byte;end
        18,19:begin frame_bytes[(offset-16)*8+:8]<=sector_byte;width[(offset-18)*8+:8]<=sector_byte;end
        20,21:begin rate[(offset-20)*8+:8]<=sector_byte;width[(offset-18)*8+:8]<=sector_byte;end
        22,23:begin rate[(offset-20)*8+:8]<=sector_byte;height[(offset-22)*8+:8]<=sector_byte;end
        24,25:begin samples[(offset-24)*8+:8]<=sector_byte;height[(offset-22)*8+:8]<=sector_byte;end
        26,27:begin samples[(offset-24)*8+:8]<=sector_byte;bmp_planes[(offset-26)*8+:8]<=sector_byte;end
        28,29:begin audio_bytes[(offset-28)*8+:8]<=sector_byte;bmp_bits[(offset-28)*8+:8]<=sector_byte;end
        30,31:begin audio_bytes[(offset-28)*8+:8]<=sector_byte;compression[(offset-30)*8+:8]<=sector_byte;end
        32,33:begin audio_format[(offset-32)*8+:8]<=sector_byte;compression[(offset-30)*8+:8]<=sector_byte;end
        34,35:audio_format[(offset-32)*8+:8]<=sector_byte;
       endcase
      end
      if(kind==FAT && offset>=fat_offset && (offset-fat_offset)<9'd4)
       next_cluster[(offset-fat_offset)*8+:8]<=sector_byte;
     end
     if(sector_end)state<=DECIDE;
    end
    DRAIN:if(sector_end)state<=DECIDE;
    DECIDE:case(kind)
     BOOT:if(signature!=16'haa55)begin status<=10;state<=FAIL;end
      else if(sector_size==512 && valid_spc && root>=2)begin kind<=BPB;end
      else if(partition!=0 && (part_type==8'h0b || part_type==8'h0c || part_type==8'h1b || part_type==8'h1c))begin
       volume<=partition;sector_lba<=partition;kind<=BPB;state<=REQ;end
      else begin status<=10;state<=FAIL;end
     BPB:if(signature!=16'haa55 || sector_size!=512 || !valid_spc || reserved==0 || fat_size==0 ||
       (nfats!=1 && nfats!=2) || root<2 || root>=32'h0ffffff0)begin status<=10;state<=FAIL;end
      else begin
       fat_base<=volume+reserved;data_base<=volume+reserved+(nfats==2 ? fat_size<<1 : fat_size);
       case(spc)1:shift<=0;2:shift<=1;4:shift<=2;8:shift<=3;16:shift<=4;32:shift<=5;64:shift<=6;128:shift<=7;endcase
       cluster<=root;dir_sector<=0;resumed<=0;kind<=DIR;state<=RESUME;status<=2;
      end
     DIR:if(ended)state<=FINISH;
      else if(candidate_found)begin
       // Wait for sector_end before another request (transport cannot be aborted).
       if(candidate_type==3 && entry_cluster>=2 && entry_cluster<32'h0ffffff0 && entry_size!=0)begin
        checked_type<=3;state<=STORE;
       end else if((candidate_type==1 || candidate_type==2) && entry_cluster>=2 && entry_cluster<32'h0ffffff0 && entry_size>=512)begin
        sector_lba<=address(entry_cluster);kind<=HEADER;state<=REQ;
       end else begin checked_type<=0;state<=STORE;end
      end else state<=ADVANCE;
     HEADER:begin checked_type<=candidate_type==1 && valid_bmp ? 1 : candidate_type==2 && valid_rv ? 2 : 0;state<=STORE;end
     FAT:if(next_cluster[27:0]>=28'hffffff8)state<=FINISH;
      else if(next_cluster[27:0]<2 || next_cluster[27:0]>=28'hffffff0 || next_cluster[27:0]==cluster || hops==65535)begin status<=13;state<=FAIL;end
      else begin cluster<={4'd0,next_cluster[27:0]};dir_sector<=0;hops<=hops+1'b1;kind<=DIR;state<=RESUME;end
    endcase
    STORE:if(store_byte!=11)store_byte<=store_byte+1'b1;else begin
     count<=count+1'b1;if(checked_type==1)begin bmp_index<=bmp_index+1'b1;image_count<=image_count+1'b1;end
     if(count==31)state<=FINISH;else begin sector_lba<=dir_lba;kind<=DIR;state<=REQ;end
    end
    RESUME:begin
     sector_lba<=address(cluster);
     if(hops==0 && dir_sector==0)debug_root_lba<=address(cluster);
     state<=REQ;
    end
    ADVANCE:begin
     resumed<=0;
     if(dir_sector+1<spc)begin dir_sector<=dir_sector+1'b1;sector_lba<=sector_lba+1'b1;kind<=DIR;state<=REQ;end
     else begin sector_lba<=fat_base+(cluster>>7);kind<=FAT;state<=REQ;end
    end
    FINISH:begin done<=1;status<=3;end
    FAIL:begin done<=1;end
   endcase
   if(state==WAIT && &ready_watchdog)begin status<=14;state<=FAIL;end
   else if(state!=WAIT && &watchdog && !done)begin status<=15;state<=FAIL;end
  end
 end
endmodule
