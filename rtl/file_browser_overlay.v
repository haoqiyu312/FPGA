// Single-column file list with an eight-row scrolling window and scrollbar.
module file_browser_overlay #(parameter integer WIDTH=640,HEIGHT=480,FONT_LATENCY=1,PIPE_COORDS=0) (
 input wire clk,rst_n,input wire[9:0] x,y,input wire de,
 input wire visible,ready,input wire[5:0] count,input wire[3:0] status,
 input wire[7:0] debug_root_byte,input wire[15:0] debug_root_lba,
 input wire[4:0] scroll_first,input wire selection_valid,input wire[4:0] selected,
 output reg[4:0] display_index,input wire[87:0] file_name,input wire[1:0] file_type,
 output reg overlay_active,output wire[23:0] rgb,
 output wire[15:0] cn_codepoint,output wire[3:0] cn_font_row,input wire[15:0] cn_pixels,output wire[4:0] color_index
);
 wire [9:0] raw_view_x=x-(WIDTH-640)/2,raw_view_y=y-(HEIGHT-480)/2;
 wire [2:0] raw_row=raw_view_y<104 ? 0 : raw_view_y<144 ? 1 : raw_view_y<184 ? 2 : raw_view_y<224 ? 3 :
     raw_view_y<264 ? 4 : raw_view_y<304 ? 5 : raw_view_y<344 ? 6 : 7;
 reg [9:0] view_x_pipe,view_y_pipe,x_pipe,y_pipe,row_top_pipe;
 reg [2:0] row_pipe;reg de_pipe;
 reg[5:0] title_column_pipe,footer_column_pipe,page_column_pipe;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin view_x_pipe<=0;view_y_pipe<=0;x_pipe<=0;y_pipe<=0;row_top_pipe<=0;row_pipe<=0;de_pipe<=0;title_column_pipe<=0;footer_column_pipe<=0;page_column_pipe<=0;end
  else begin
   title_column_pipe<=raw_view_x[9:4]-6'd8;footer_column_pipe<=raw_view_x[9:4]-6'd1;page_column_pipe<=raw_view_x[9:4]-6'd15;
   view_x_pipe<=raw_view_x;view_y_pipe<=raw_view_y;x_pipe<=x;y_pipe<=y;de_pipe<=de;row_pipe<=raw_row;
   case(raw_row)
    0:row_top_pipe<=64;1:row_top_pipe<=104;2:row_top_pipe<=144;3:row_top_pipe<=184;
    4:row_top_pipe<=224;5:row_top_pipe<=264;6:row_top_pipe<=304;7:row_top_pipe<=344;
   endcase
  end
 end
 wire [9:0] view_x=PIPE_COORDS ? view_x_pipe : raw_view_x,view_y=PIPE_COORDS ? view_y_pipe : raw_view_y;
 wire draw_de=PIPE_COORDS ? de_pipe : de;
 wire [9:0] draw_x=PIPE_COORDS ? x_pipe : x,draw_y=PIPE_COORDS ? y_pipe : y;
 reg[4:0] color,next_color;reg[6:0] character;reg[2:0] font_row,font_column,latched_column;
 reg[511:0] cn_label;reg[15:0] cn_character;reg cn_text_area;
 reg[3:0] cn_row,cn_column,latched_cn_column;reg[5:0] cn_index;
 wire[7:0] font_pixels;
 browser_ascii_font font(.clk(clk),.character(character),.row(font_row),.pixels(font_pixels));
 assign cn_codepoint=cn_character;
 assign cn_font_row=cn_row;
 reg[3:0] row;reg[5:0] list_index;reg[9:0] tx,ty,row_top;
 reg[7:0] ascii;reg[191:0] label;
 reg text_area,icon_ink,active;reg[4:0] text_color,latched_text_color;
 integer thumb_height,thumb_top,item_number;
 function[7:0] filename_char;
 input[87:0] name;input[3:0] pos;
 begin
  if(pos<8)filename_char=name[87-pos*8-:8];
  else if(pos==8)filename_char=name[23:0]==24'h202020 ? 8'h20 : 8'h2e;
  else if(pos<12)filename_char=name[23-(pos-9)*8-:8];
  else filename_char=8'h20;
 end endfunction
 function[7:0] hex_digit;
 input[3:0] nibble;
 begin hex_digit=nibble<10 ? "0"+nibble : "A"+(nibble-10);end
 endfunction
 always @*begin
  next_color=5'd1;character=32;font_row=0;font_column=0;
  text_area=0;cn_text_area=0;cn_character=16'h0020;cn_label=0;cn_row=0;cn_column=0;cn_index=0;
  active=visible && draw_de && draw_x<WIDTH && draw_y<HEIGHT;text_color=5'd17;display_index=0;ascii=32;
  label={24{8'h20}};row=0;list_index=0;tx=0;ty=0;row_top=0;icon_ink=0;
  thumb_height=64;thumb_top=64+scroll_first*8+scroll_first*2+(scroll_first>>1);item_number=0;
  if(draw_de && view_x<640 && view_y<480)begin
   if(visible)begin
    active=1;
    if(view_y<56)next_color=5'd4;
    if(view_y>=64 && view_y<384)begin
     row=PIPE_COORDS ? row_pipe : (view_y<104 ? 0 : view_y<144 ? 1 : view_y<184 ? 2 : view_y<224 ? 3 :
         view_y<264 ? 4 : view_y<304 ? 5 : view_y<344 ? 6 : 7);
     row_top=PIPE_COORDS ? row_top_pipe : 64+row*40;
     list_index={1'b0,scroll_first}+row;
     display_index=list_index[4:0];
     if(view_x>=16 && view_x<600 && view_x<592 && view_y<row_top+36 && list_index<count && ready)begin
      next_color=selection_valid && selected==list_index[4:0] ? 5'd2 : 5'd3;
      if(selection_valid && selected==list_index[4:0] && view_x>=16 && view_x<20 && view_y>=row_top+4 && view_y<row_top+32)
       next_color=5'd8;
      if(view_x>=28 && view_x<52 && view_y>=row_top+5 && view_y<row_top+31)begin
       if(view_x<30 || view_x>=50 || view_y<row_top+7 || view_y>=row_top+29)next_color=5'd1;
       else if(view_x>=46 && view_y<row_top+12)next_color=5'd14;
       else next_color=5'd16;
       if(file_type==1)begin
        if(view_x>=33 && view_x<47 && view_y>=row_top+13 && view_y<row_top+25)next_color=5'd9;
        if(view_x>=35 && view_x<46 && view_y>=row_top+16 && view_y<row_top+25 && view_y>=row_top+24-(view_x-35)/2)next_color=5'd7;
        if(view_x>=38 && view_x<48 && view_y>=row_top+18 && view_y<row_top+25 && view_y>=row_top+24-(view_x-38)/2)next_color=5'd10;
        if(((view_x>=42 && view_x<=44 && view_y>=row_top+14 && view_y<=row_top+16) || (view_x==43 && (view_y==row_top+13 || view_y==row_top+17)) || ((view_x==41 || view_x==45) && view_y==row_top+15)))next_color=5'd19;
       end else if(file_type==2)begin
        if(view_x>=32 && view_x<48 && view_y>=row_top+12 && view_y<row_top+25)next_color=5'd6;
        if(view_x>=37 && view_x<44 && view_y>=row_top+14+(view_x>40 ? 43-view_x : view_x-37) && view_y<row_top+23-(view_x>40 ? 43-view_x : view_x-37))next_color=5'd18;
       end else if(file_type==3)begin
        if((view_x>=38 && view_x<40 && view_y>=row_top+12 && view_y<row_top+24) ||
           (view_x>=39 && view_x<45 && view_y>=row_top+12 && view_y<row_top+15) ||
           (view_x>=40 && view_x<46 && view_y>=row_top+14 && view_y<row_top+17))next_color=5'd15;
        if((view_x>=35 && view_x<40 && view_y>=row_top+21 && view_y<row_top+25 && ((view_x>=35 && view_x<=39 && view_y>=row_top+22 && view_y<=row_top+24) || (view_x>=36 && view_x<=38 && view_y>=row_top+21 && view_y<=row_top+25))) ||
           (view_x>=42 && view_x<47 && view_y>=row_top+17 && view_y<row_top+21 && ((view_x>=42 && view_x<=46 && view_y>=row_top+18 && view_y<=row_top+20) || (view_x>=43 && view_x<=45 && view_y>=row_top+17 && view_y<=row_top+21))))next_color=5'd15;
       end else begin
        if(view_x>=34 && view_x<46 && view_y>=row_top+15 && view_y<row_top+17)next_color=5'd12;
        if(view_x>=34 && view_x<44 && view_y>=row_top+20 && view_y<row_top+22)next_color=5'd12;
       end
      end
      if(view_x>=64 && view_x<256 && view_y>=row_top+10 && view_y<row_top+26)begin
       tx=view_x-64;ty=view_y-row_top-10;text_area=1;
       ascii=filename_char(file_name,tx[7:4]);
       text_color=file_type==0 ? 5'd11 : 5'd20;
      end
     end
    end
    if(view_y>=64 && view_y<384 && view_x>=600 && view_x<624)begin
     next_color=5'd5;
     if(view_y>=thumb_top && view_y<thumb_top+thumb_height)next_color=5'd13;
    end
    if(view_y>=16 && view_y<32 && view_x>=128 && view_x<512)begin
     cn_label=512'h5b5850a8536165874ef6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
     tx=view_x-128;ty=view_y-16;cn_text_area=1;cn_index=PIPE_COORDS ? title_column_pipe : view_x[9:4]-6'd8;cn_row=view_y[3:0];
    end
    if(view_y>=400 && view_y<416 && view_x>=16 && view_x<624)begin
     cn_label=512'h004b0032002f004b00334e0a4e0b79fb52a80020004b003462535f00000000000000000000000000000000000000000000000000000000000000000000000000;
     if(!ready)cn_label=512'h6b635728626b63cf5b5850a853610000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
     else if(status>=10)begin
      cn_label=512'h00540046536195198bef00200031003000206309004b00450059003191cd8bd50000000000000000000000000000000000000000000000000000000000000000;
      cn_label[511-6*16-:16]=16'h0030+((status-4'd10)/10);
      cn_label[511-7*16-:16]=16'h0030+((status-4'd10)%10);
     end else if(count==0)begin
      cn_label=512'h683976ee5f554e3a7a7a00200042003a003000300020004c003a0030003000300030000000000000000000000000000000000000000000000000000000000000;
      cn_label[511-8*16-:16]={8'h00,hex_digit(debug_root_byte[7:4])};
      cn_label[511-9*16-:16]={8'h00,hex_digit(debug_root_byte[3:0])};
      cn_label[511-13*16-:16]={8'h00,hex_digit(debug_root_lba[15:12])};
      cn_label[511-14*16-:16]={8'h00,hex_digit(debug_root_lba[11:8])};
      cn_label[511-15*16-:16]={8'h00,hex_digit(debug_root_lba[7:4])};
      cn_label[511-16*16-:16]={8'h00,hex_digit(debug_root_lba[3:0])};
     end
     tx=view_x-16;ty=view_y-400;cn_text_area=1;cn_index=PIPE_COORDS ? footer_column_pipe : view_x[9:4]-6'd1;cn_row=view_y[3:0];
    end
    if(view_y>=444 && view_y<460 && view_x>=240 && view_x<400)begin
     cn_label=512'h987976ee002000300031002f00330032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
     item_number=selected+1;
     cn_label[511-3*16-:16]=16'h0030+(item_number/10);
     cn_label[511-4*16-:16]=16'h0030+(item_number%10);
     cn_label[511-6*16-:16]=16'h0030+(count/10);
     cn_label[511-7*16-:16]=16'h0030+(count%10);
     tx=view_x-240;ty=view_y-444;cn_text_area=1;cn_index=PIPE_COORDS ? page_column_pipe : view_x[9:4]-6'd15;cn_row=view_y[3:0]-4'd12;
    end
   end
  end
  if(text_area)begin
   character=ascii>=32 && ascii<127 ? ascii[6:0] : 7'd63;
   font_row=ty[3:1];font_column=tx[3:1];
  end
  if(cn_text_area)begin
   cn_character=cn_index<32 ? cn_label[511-cn_index[4:0]*16-:16] : 16'h0020;cn_column=view_x[3:0];
  end
 end
 reg latched_text,latched_cn;
 reg active_stage1,text_stage2,cn_stage2;
 reg[4:0] color_stage2,text_color_stage2;
 reg[2:0] column_stage2;reg[3:0] cn_column_stage2;reg[7:0] ascii_stage2;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin overlay_active<=0;color<=0;latched_text<=0;latched_cn<=0;latched_column<=0;latched_cn_column<=0;latched_text_color<=0;active_stage1<=0;text_stage2<=0;cn_stage2<=0;color_stage2<=0;text_color_stage2<=0;column_stage2<=0;cn_column_stage2<=0;ascii_stage2<=0;end
  else begin
   active_stage1<=active;overlay_active<=FONT_LATENCY==2 ? active_stage1 : active;
   text_stage2<=latched_text;cn_stage2<=latched_cn;color_stage2<=color;
   text_color_stage2<=latched_text_color;column_stage2<=latched_column;
   cn_column_stage2<=latched_cn_column;ascii_stage2<=font_pixels;
   color<=next_color;latched_text<=text_area;latched_cn<=cn_text_area;latched_column<=font_column;latched_cn_column<=cn_column;latched_text_color<=text_color;end
 end
 assign color_index=FONT_LATENCY==2 ?
            (cn_stage2 && cn_pixels[15-cn_column_stage2] ? text_color_stage2 :
             text_stage2 && ascii_stage2[7-column_stage2] ? text_color_stage2 : color_stage2) :
            (latched_cn && cn_pixels[15-latched_cn_column] ? latched_text_color :
             latched_text && font_pixels[7-latched_column] ? latched_text_color : color);
 file_browser_palette u_palette(.index(color_index),.rgb(rgb));
endmodule

module file_browser_palette(input wire[4:0] index,output reg[23:0] rgb);
 always @*begin
 case(index)
 5'd0:rgb=24'h000000;
 5'd1:rgb=24'h101820;
 5'd2:rgb=24'h185880;
 5'd3:rgb=24'h203440;
 5'd4:rgb=24'h203848;
 5'd5:rgb=24'h26343c;
 5'd6:rgb=24'h28547a;
 5'd7:rgb=24'h2e9c73;
 5'd8:rgb=24'h58d8e8;
 5'd9:rgb=24'h64c8ed;
 5'd10:rgb=24'h65b96b;
 5'd11:rgb=24'h809098;
 5'd12:rgb=24'h8799a3;
 5'd13:rgb=24'hb0c8d8;
 5'd14:rgb=24'hc8d6df;
 5'd15:rgb=24'hd99932;
 5'd16:rgb=24'hf0f4f5;
 5'd17:rgb=24'hf0f4ff;
 5'd18:rgb=24'hf4fbff;
 5'd19:rgb=24'hffd46a;
 5'd20:rgb=24'hffffff;
 default:rgb=24'h000000;
 endcase
 end
endmodule
