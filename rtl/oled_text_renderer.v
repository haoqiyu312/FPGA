// Render SSD1306 vertical bytes directly through the shared 16x16 glyph ROM.
// ASCII uses an 8x8 font doubled vertically; Chinese spans two 8-pixel cells.
module oled_text_renderer(
 input wire clk,reset_n,fetch,input wire[2:0] page,input wire[6:0] column,
 input wire[121:0] ui,input wire[87:0] file_name,
 output wire[4:0] display_index,output reg valid,output reg[7:0] pixels,
 output reg[15:0] font_code,output reg[3:0] font_row,input wire[15:0] font_pixels);
 reg[121:0] frame_ui;
 wire[87:0] playing_name;wire ready,menu;wire[5:0] count;wire[4:0] selected;
 wire[3:0] card_status,load_status;wire video,paused,slideshow,reverse,subtitles,spectrum;wire[4:0] interval_seconds;wire[1:0] zoom;
 assign {playing_name,ready,menu,count,selected,card_status,load_status,video,paused,slideshow,interval_seconds,reverse,subtitles,spectrum,zoom}=frame_ui;
 wire[1:0] line=page[2:1];wire[3:0] cell_index=column[6:3];
 wire[5:0] item={1'b0,selected}+(line==0 ? 6'd0 : {4'd0,line}-1'b1);
 assign display_index=item<count ? item[4:0] : 5'd0;
 function[7:0] namechar;input[87:0] name;input[3:0] pos;begin
  if(pos<8)namechar=name[87-pos*8-:8];
  else if(pos==8)namechar=name[23:0]==24'h202020 ? 8'h20 : 8'h2e;
  else if(pos<12)namechar=name[23-(pos-9)*8-:8];else namechar=32;
 end endfunction
 function[3:0] tens;input[5:0] n;begin tens=n>=30 ? 3 : n>=20 ? 2 : n>=10 ? 1 : 0;end endfunction
 function[7:0] init_stage_char;input[3:0] stage;input[3:0] pos;begin
  init_stage_char=8'h3f;
  case(stage)
   0:case(pos)0:init_stage_char="R";1:init_stage_char="E";2:init_stage_char="S";3:init_stage_char="E";4:init_stage_char="T";endcase
   1:case(pos)0:init_stage_char="C";1:init_stage_char="M";2:init_stage_char="D";3:init_stage_char="0";endcase
   2:case(pos)0:init_stage_char="C";1:init_stage_char="M";2:init_stage_char="D";3:init_stage_char="8";endcase
   3:case(pos)0:init_stage_char="C";1:init_stage_char="M";2:init_stage_char="D";3:init_stage_char="5";4:init_stage_char="5";endcase
   4:case(pos)0:init_stage_char="A";1:init_stage_char="C";2:init_stage_char="M";3:init_stage_char="D";4:init_stage_char="4";5:init_stage_char="1";endcase
   6:case(pos)0:init_stage_char="R";1:init_stage_char="E";2:init_stage_char="A";3:init_stage_char="D";4:init_stage_char="Y";endcase
  endcase
 end endfunction
 wire[5:0] ordinal=count==0 ? 0 : {1'b0,selected}+1'b1;
 wire[3:0] interval_tens=tens({1'b0,interval_seconds});
 reg[15:0] glyph;reg wide;reg[7:0] ascii;reg[3:0] glyph_x;
 wire[3:0] error_status=menu ? card_status : load_status;
 always @*begin
  glyph=16'h0020;wide=0;ascii=32;
  if(menu)begin
   if(line==0)begin
    if(cell_index<4)begin
     wide=1;
     if(error_status>=10)glyph=cell_index<2 ? 16'h9519 : 16'h8bef;
     else if(!ready)glyph=cell_index<2 ? 16'h8bfb : 16'h5361;
     else glyph=cell_index<2 ? 16'h6587 : 16'h4ef6;
    end
    if(error_status>=10)begin
     if(cell_index==6)ascii="0"+1;if(cell_index==7)ascii="0"+error_status-10;
    end else case(cell_index)
     6:ascii="0"+tens(ordinal);7:ascii="0"+ordinal-tens(ordinal)*10;
     8:ascii="/";9:ascii="0"+tens(count);10:ascii="0"+count-tens(count)*10;
    endcase
   end else if(error_status>=10 && line==1)begin
    if(cell_index==0)ascii="S";else if(cell_index==1)ascii="D";else if(cell_index==2)ascii=":";
    else ascii=init_stage_char(load_status,cell_index-4'd3);
   end else if(ready && item<count)begin
    if(cell_index==0)ascii=line==1 ? ">" : " ";else ascii=namechar(file_name,cell_index-1'b1);
   end
  end else case(line)
   0:begin
    if(cell_index<8)begin
     wide=1;
     case(cell_index[3:1])
      0:glyph=video ? 16'h89c6 : 16'h56fe;
      1:glyph=video ? 16'h9891 : 16'h7247;
      2:glyph=paused ? 16'h6682 : (video ? 16'h64ad : 16'h0020);
      3:glyph=paused ? 16'h505c : (video ? 16'h653e : 16'h0020);
     endcase
    end
    if(error_status>=10)begin
     if(cell_index<4)begin wide=1;glyph=cell_index<2 ? 16'h9519 : 16'h8bef;end
     else begin wide=0;if(cell_index==6)ascii="1";else if(cell_index==7)ascii="0"+error_status-10;end
    end
   end
   1:ascii=namechar(playing_name,cell_index);
   2:begin
    if(video)begin
     if(cell_index<6 || (cell_index>=8 && cell_index<14))begin
      wide=1;
      case(cell_index[3:1])
       0:glyph=16'h5b57;1:glyph=16'h5e55;2:glyph=subtitles ? 16'h5f00 : 16'h5173;
       4:glyph=16'h9891;5:glyph=16'h8c31;6:glyph=spectrum ? 16'h5f00 : 16'h5173;
      endcase
     end
    end else begin
     if(cell_index<6 || cell_index>=10)begin
      wide=1;
      case(cell_index[3:1])
       0:glyph=16'h8f6e;1:glyph=16'h64ad;2:glyph=slideshow ? 16'h5f00 : 16'h5173;
       5:glyph=16'h79d2;6:glyph=reverse ? 16'h5012 : 16'h6b63;7:glyph=16'h5e8f;
      endcase
     end
     if(cell_index==7)ascii=interval_seconds>=10 ? "0"+interval_tens : " ";
     if(cell_index==8)ascii="0"+(interval_seconds-interval_tens*10);
    end
   end
   3:begin
    if(video)begin
     if(cell_index==1)ascii="S";if(cell_index==2)ascii="1";
     if(cell_index==9)ascii="S";if(cell_index==10)ascii="3";
    end else begin
     // Picture hotkeys align below slideshow, interval and direction.
     if(cell_index==1)ascii="S";if(cell_index==2)ascii="1";
     if(cell_index==4)ascii="S";if(cell_index==5)ascii="9";if(cell_index==6)ascii="-";
     if(cell_index==7)ascii="S";if(cell_index==8)ascii="1";if(cell_index==9)ascii="1";if(cell_index==10)ascii="+";
     if(cell_index==13)ascii="S";if(cell_index==14)ascii="3";
    end
   end
  endcase
  if(!wide)glyph={8'd0,(ascii==0 ? 8'd32 : (ascii>=32 && ascii<127 ? ascii : 8'd63))};
  glyph_x=wide ? column[3:0] : {column[2:0],1'b0};
 end
 wire[7:0] ascii_pixels;reg ascii_glyph;
 browser_ascii_font u_ascii(.clk(clk),.character(font_code[6:0]),.row(font_row[3:1]),.pixels(ascii_pixels));
 reg[1:0] state;reg[2:0] bit_index;reg[1:0] wait_count;reg[3:0] x_latched;
 always @(posedge clk or negedge reset_n)begin
  if(!reset_n)begin frame_ui<=0;valid<=0;pixels<=0;font_code<=32;font_row<=0;state<=0;ascii_glyph<=0;bit_index<=0;wait_count<=0;x_latched<=0;end
  else begin
   valid<=0;
   case(state)
    0:if(fetch)begin
     if(page==0 && column==0)frame_ui<=ui;
     state<=1;pixels<=0;
    end
    1:begin ascii_glyph<=!wide;font_code<=glyph;x_latched<=glyph_x;font_row<={page[0],3'd0};bit_index<=0;wait_count<=0;state<=2;end
    2:if(wait_count==3)begin
      pixels[bit_index]<=ascii_glyph ? ascii_pixels[7-x_latched[3:1]] : font_pixels[15-x_latched];wait_count<=0;
      if(bit_index==7)begin valid<=1;state<=0;end
      else begin bit_index<=bit_index+1'b1;font_row<={page[0],bit_index+3'd1};end
     end else wait_count<=wait_count+1'b1;
   endcase
  end
 end
endmodule
