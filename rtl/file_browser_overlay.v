// Single-column file list with an eight-row scrolling window and scrollbar.
module file_browser_overlay(
 input wire clk,rst_n,input wire[9:0] x,y,input wire de,
 input wire visible,ready,input wire[5:0] count,input wire[3:0] status,
 input wire[7:0] debug_root_byte,input wire[15:0] debug_root_lba,
 input wire[4:0] scroll_first,input wire selection_valid,input wire[4:0] selected,
 output reg[4:0] display_index,input wire[87:0] file_name,input wire[1:0] file_type,
 output reg overlay_active,output wire[23:0] rgb,
 output wire[15:0] cn_codepoint,output wire[3:0] cn_font_row,input wire[15:0] cn_pixels
);
 reg[23:0] color,next_color;reg[6:0] character;reg[2:0] font_row,font_column,latched_column;
 reg[511:0] cn_label;reg[15:0] cn_character;reg cn_text_area;
 reg[3:0] cn_row,cn_column,latched_cn_column;
 wire[7:0] font_pixels;
 browser_ascii_font font(.clk(clk),.character(character),.row(font_row),.pixels(font_pixels));
 assign cn_codepoint=cn_character;
 assign cn_font_row=cn_row;
 reg[3:0] row;reg[5:0] list_index;reg[9:0] tx,ty,row_top;
 reg[7:0] ascii;reg[191:0] label;
 reg text_area,icon_ink,active;reg[23:0] text_color,latched_text_color;
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
  next_color=24'h101820;character=32;font_row=0;font_column=0;
  text_area=0;cn_text_area=0;cn_character=16'h0020;cn_label=0;cn_row=0;cn_column=0;
  active=0;text_color=24'hf0f4ff;display_index=0;ascii=32;
  label={24{8'h20}};row=0;list_index=0;tx=0;ty=0;row_top=0;icon_ink=0;
  thumb_height=64;thumb_top=64+scroll_first*8+scroll_first*2+(scroll_first>>1);item_number=0;
  if(de && x<640 && y<480)begin
   if(visible)begin
    active=1;
    if(y<56)next_color=24'h203848;
    if(y>=64 && y<384)begin
     row=y<104 ? 0 : y<144 ? 1 : y<184 ? 2 : y<224 ? 3 :
         y<264 ? 4 : y<304 ? 5 : y<344 ? 6 : 7;
     row_top=64+row*40;
     list_index={1'b0,scroll_first}+row;
     display_index=list_index[4:0];
     if(x>=16 && x<600 && x<592 && y<row_top+36 && list_index<count && ready)begin
      next_color=selection_valid && selected==list_index[4:0] ? 24'h185880 : 24'h203440;
      if(selection_valid && selected==list_index[4:0] && x>=16 && x<20 && y>=row_top+4 && y<row_top+32)
       next_color=24'h58d8e8;
      if(x>=28 && x<52 && y>=row_top+5 && y<row_top+31)begin
       if(x<30 || x>=50 || y<row_top+7 || y>=row_top+29)next_color=24'h101820;
       else if(x>=46 && y<row_top+12)next_color=24'hc8d6df;
       else next_color=24'hf0f4f5;
       if(file_type==1)begin
        if(x>=33 && x<47 && y>=row_top+13 && y<row_top+25)next_color=24'h64c8ed;
        if(x>=35 && x<46 && y>=row_top+16 && y<row_top+25 && y>=row_top+24-(x-35)/2)next_color=24'h2e9c73;
        if(x>=38 && x<48 && y>=row_top+18 && y<row_top+25 && y>=row_top+24-(x-38)/2)next_color=24'h65b96b;
        if((x-43)*(x-43)+(y-row_top-15)*(y-row_top-15)<=4)next_color=24'hffd46a;
       end else if(file_type==2)begin
        if(x>=32 && x<48 && y>=row_top+12 && y<row_top+25)next_color=24'h28547a;
        if(x>=37 && x<44 && y>=row_top+14+(x>40 ? 43-x : x-37) && y<row_top+23-(x>40 ? 43-x : x-37))next_color=24'hf4fbff;
       end else if(file_type==3)begin
        if((x>=38 && x<40 && y>=row_top+12 && y<row_top+24) ||
           (x>=39 && x<45 && y>=row_top+12 && y<row_top+15) ||
           (x>=40 && x<46 && y>=row_top+14 && y<row_top+17))next_color=24'hd99932;
        if((x>=35 && x<40 && y>=row_top+21 && y<row_top+25 && (x-37)*(x-37)+(y-row_top-23)*(y-row_top-23)<=5) ||
           (x>=42 && x<47 && y>=row_top+17 && y<row_top+21 && (x-44)*(x-44)+(y-row_top-19)*(y-row_top-19)<=5))next_color=24'hd99932;
       end else begin
        if(x>=34 && x<46 && y>=row_top+15 && y<row_top+17)next_color=24'h8799a3;
        if(x>=34 && x<44 && y>=row_top+20 && y<row_top+22)next_color=24'h8799a3;
       end
      end
      if(x>=64 && x<256 && y>=row_top+10 && y<row_top+26)begin
       tx=x-64;ty=y-row_top-10;text_area=1;
       ascii=filename_char(file_name,tx[7:4]);
       text_color=file_type==0 ? 24'h809098 : 24'hffffff;
      end
     end
    end
    if(y>=64 && y<384 && x>=600 && x<624)begin
     next_color=24'h26343c;
     if(y>=thumb_top && y<thumb_top+thumb_height)next_color=24'hb0c8d8;
    end
    if(y>=16 && y<32 && x>=128 && x<512)begin
     cn_label=512'h5b5850a8536165874ef6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
     tx=x-128;ty=y-16;cn_text_area=1;
    end
    if(y>=400 && y<416 && x>=16 && x<624)begin
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
     tx=x-16;ty=y-400;cn_text_area=1;
    end
    if(y>=444 && y<460 && x>=240 && x<400)begin
     cn_label=512'h987976ee002000300031002f00330032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
     item_number=selected+1;
     cn_label[511-3*16-:16]=16'h0030+(item_number/10);
     cn_label[511-4*16-:16]=16'h0030+(item_number%10);
     cn_label[511-6*16-:16]=16'h0030+(count/10);
     cn_label[511-7*16-:16]=16'h0030+(count%10);
     tx=x-240;ty=y-444;cn_text_area=1;
    end
   end
  end
  if(text_area)begin
   character=ascii>=32 && ascii<127 ? ascii[6:0] : 7'd63;
   font_row=ty[3:1];font_column=tx[3:1];
  end
  if(cn_text_area)begin
   cn_character=cn_label[511-(tx/16)*16-:16];cn_row=ty[3:0];cn_column=tx[3:0];
  end
 end
 reg latched_text,latched_cn;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin overlay_active<=0;color<=0;latched_text<=0;latched_cn<=0;latched_column<=0;latched_cn_column<=0;latched_text_color<=0;end
  else begin overlay_active<=active;color<=next_color;latched_text<=text_area;latched_cn<=cn_text_area;latched_column<=font_column;latched_cn_column<=cn_column;latched_text_color<=text_color;end
 end
 assign rgb=latched_cn && cn_pixels[15-latched_cn_column] ? latched_text_color :
            latched_text && font_pixels[7-latched_column] ? latched_text_color : color;
endmodule
