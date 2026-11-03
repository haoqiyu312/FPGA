// Streaming UTF-8 SRT cache. Sixteen cues, 32 BMP codepoints/cue.
// Cache is immutable after loaded; only the done flag crosses while writing.
module srt_subtitles(
 input wire load_clk,load_rst,input wire[7:0] byte_data,input wire byte_valid,load_done,load_error,
 input wire clk,rst,frame_start,frame_started,video_mode,shown,
 input wire[7:0] fps,input wire[31:0] movie_frames,
 input wire[4:0] read_index,output wire[15:0] codepoint,output reg visible);
 (* ram_style="bram" *) reg[15:0] cache[0:1023];
 reg write_enable;reg[9:0] write_address;reg[15:0] write_data;
 reg committing,ending;reg[2:0] commit_step;reg[3:0] commit_cue;
 reg[23:0] commit_start,commit_end;reg[5:0] commit_length;
 always @(posedge load_clk)if(write_enable)cache[write_address]<=write_data;
 reg[4:0] count;reg[1:0] phase;reg[9:0] column;
 reg[14:0] seconds;reg[9:0] number;reg[23:0] start_ms,end_ms;
 reg[5:0] length;reg[1:0] continuation;reg[15:0] unicode;
 reg timing_ok,finished,done_previous;

 wire[15:0] decoded=continuation!=0 ? {unicode[9:0],byte_data[5:0]} : {8'd0,byte_data};
 wire final_char=(continuation==1 && byte_data[7:6]==2'b10) || (continuation==0 && !byte_data[7]);
 wire line_end=byte_valid && byte_data==10;
 wire eof=load_done && !done_previous;
 always @(posedge load_clk or posedge load_rst)begin
  if(load_rst)begin
   write_enable<=0;write_address<=0;write_data<=0;committing<=0;ending<=0;commit_step<=0;commit_cue<=0;commit_start<=0;commit_end<=0;commit_length<=0;
   count<=0;phase<=0;column<=0;seconds<=0;number<=0;start_ms<=0;end_ms<=0;length<=0;continuation<=0;unicode<=0;timing_ok<=0;finished<=0;done_previous<=0;end
  else begin
   done_previous<=load_done;write_enable<=0;
   if(ending && !committing && !write_enable)finished<=1;
   if(byte_valid && !finished && count<16 && byte_data!=13)begin
    if(byte_data==10)begin
     column<=0;continuation<=0;
     case(phase)
      0:if(column!=0)begin phase<=1;seconds<=0;number<=0;timing_ok<=1;end
      1:begin
       end_ms<=seconds*1000+number;
       if(column!=29)timing_ok<=0;
       phase<=2;length<=0;
      end
      2:if(column==0)begin
        if(timing_ok && end_ms>start_ms && length!=0)begin committing<=1;commit_step<=0;commit_cue<=count[3:0];commit_start<=start_ms;commit_end<=end_ms;commit_length<=length;count<=count+1'b1;end
        phase<=0;length<=0;
       end else if(length<32)begin write_enable<=1;write_address<={count[3:0],1'b0,length[4:0]};write_data<=16'h20;length<=length+1'b1;end
     endcase
    end else begin
     if(column!=1023)column<=column+1'b1;
     if(phase==1)begin
      if(column==12)begin start_ms<=seconds*1000+number;seconds<=0;number<=0;end
      else if(column<12 || (column>=17 && column<29))begin
       if(byte_data>=48 && byte_data<=57)number<=number*10+(byte_data-48);
       else if(byte_data==58 || byte_data==44 || byte_data==46)begin seconds<=seconds*60+number;number<=0;end
       else timing_ok<=0;
      end
     end
     if(phase==2 && length<32)begin
      if(continuation==0)begin
       if(byte_data[7:5]==3'b110)begin unicode<={11'd0,byte_data[4:0]};continuation<=1;end
       else if(byte_data[7:4]==4'b1110)begin unicode<={12'd0,byte_data[3:0]};continuation<=2;end
      end else if(byte_data[7:6]==2'b10)begin unicode<=decoded;continuation<=continuation-1'b1;end
      else continuation<=0;
      if(final_char)begin
       // BOM and non-BMP text are not glyphs in this fixed-font renderer.
       if(decoded!=16'hfeff)begin write_enable<=1;write_address<={count[3:0],1'b0,length[4:0]};write_data<=decoded;length<=length+1'b1;end
      end
     end
    end
   end
   if(eof)begin
    if(!load_error && phase==2 && timing_ok && end_ms>start_ms && length!=0 && count<16)begin
     committing<=1;commit_step<=0;commit_cue<=count[3:0];commit_start<=start_ms;commit_end<=end_ms;commit_length<=length;count<=count+1'b1;
    end
    ending<=1;
   end
   if(committing)begin
    write_enable<=1;write_address<={commit_cue,6'd32}+commit_step;
    case(commit_step)
     0:write_data<=commit_start[15:0];1:write_data<={8'd0,commit_start[23:16]};
     2:write_data<=commit_end[15:0];3:write_data<={8'd0,commit_end[23:16]};
     4:write_data<={10'd0,commit_length};
    endcase
    if(commit_step==4)committing<=0;else commit_step<=commit_step+1'b1;
   end
  end
 end
 (* async_reg="true" *) reg[2:0] ready_sync;
 (* async_reg="true" *) reg[4:0] count_meta,count_sync;
 reg[23:0] elapsed;reg[31:0] frames;reg[9:0] fraction;
 reg[4:0] scan;reg[3:0] selected;reg found;
 reg scanning;reg[1:0] scan_phase;reg[2:0] scan_word;
 reg[23:0] scan_start,scan_end;reg[5:0] selected_length;
 reg[15:0] raw;reg raw_valid;
 wire[9:0] read_address=scanning ? {scan[3:0],6'd32}+scan_word : {selected,1'b0,read_index};
 always @(posedge clk)begin
  raw<=cache[read_address];raw_valid<=!scanning && read_index<selected_length;
 end
 assign codepoint=raw_valid ? raw : 16'h20;
 // Cache/timing metadata is held stable after load_done and sampled only after
 // three clocks. No per-character CDC is needed during playback.
 always @(posedge clk or posedge rst)begin
  if(rst)begin ready_sync<=0;count_meta<=0;count_sync<=0;elapsed<=0;frames<=0;fraction<=0;visible<=0;scan<=0;selected<=0;found<=0;scanning<=0;scan_phase<=0;scan_word<=0;scan_start<=0;scan_end<=0;selected_length<=0;end
  else begin
   ready_sync<={ready_sync[1:0],finished && !load_error};
   count_meta<=count;count_sync<=count_meta;
   if(!video_mode || !shown)begin elapsed<=0;frames<=0;fraction<=0;visible<=0;end
   else if(frame_started)begin
    if(frames==0 || frames>=movie_frames)begin elapsed<=0;fraction<=0;frames<=1;end
    else begin
     frames<=frames+1'b1;
     // Millisecond step with a remainder for 3 fps (333,333,334).
     case(fps)
      2:elapsed<=elapsed+500;
      3:begin elapsed<=elapsed+(fraction==2 ? 334 : 333);fraction<=fraction==2 ? 0 : fraction+1'b1;end
      4:elapsed<=elapsed+250;
      5:elapsed<=elapsed+200;
      default:elapsed<=elapsed+1000;
     endcase
    end
   end
   if(frame_start)begin scan<=0;selected<=0;found<=0;scanning<=1;scan_phase<=0;scan_word<=0;selected_length<=0;end
   else if(scanning)begin
    if(scan>=count_sync || !ready_sync[2])begin visible<=found && video_mode && shown;scanning<=0;end
    else if(scan_phase<2)scan_phase<=scan_phase+1'b1;
    else begin
     scan_phase<=0;
     case(scan_word)
      0:scan_start[15:0]<=raw;1:scan_start[23:16]<=raw[7:0];
      2:scan_end[15:0]<=raw;3:scan_end[23:16]<=raw[7:0];
      4:begin
       if(elapsed>=scan_start && elapsed<scan_end)begin selected<=scan[3:0];found<=1;selected_length<=raw[5:0];end
       scan<=scan+1'b1;
      end
     endcase
     scan_word<=scan_word==4 ? 0 : scan_word+1'b1;
    end
   end
  end
 end
endmodule
