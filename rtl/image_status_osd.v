// Chinese frame-latched OSD with a built-in 16x16 synchronous glyph ROM.
// The output has one pixel-clock of latency; top-level delay accounts for it.
module image_status_osd #(
 parameter integer NOTICE_FRAMES=120
)(input wire pixel_clk,rst_n,input wire [9:0] x,y,input wire de,
 input wire image_shown,input wire [3:0] load_status,
 input wire [4:0] image_index,input wire [5:0] image_total,
 input wire auto_mode,input wire [1:0] interval_setting,input wire reverse_direction,
 output reg overlay_active,output reg [23:0] rgb,
 input wire [87:0] image_name);
 reg [18:0] meta=0,sync=0,frame=0;
 // Packed snapshot is stable long before a displayed frame begins.
 wire shown=frame[18]; wire [3:0] status=frame[17:14];
 wire [4:0] selected=frame[13:9];wire [5:0] total=frame[8:3];
 wire autoplay=frame[2];wire [1:0] interval=frame[1:0];
 // Direction is held separately so the snapshot layout stays explicit below.
 reg dir_meta=0,dir_sync=0,dir_frame=0;
 reg [87:0] name_meta={11{8'h20}},name_sync={11{8'h20}},name_frame={11{8'h20}};
 reg [7:0] notice=NOTICE_FRAMES;
 always @(posedge pixel_clk or negedge rst_n)begin
  if(!rst_n)begin meta<=0;sync<=0;frame<=0;notice<=NOTICE_FRAMES;dir_meta<=0;dir_sync<=0;dir_frame<=0;name_meta<={11{8'h20}};name_sync<={11{8'h20}};name_frame<={11{8'h20}};end
  else begin
   meta<={image_shown,load_status,image_index,image_total,auto_mode,interval_setting};sync<=meta;
   dir_meta<=reverse_direction;dir_sync<=dir_meta;name_meta<=image_name;name_sync<=name_meta;
   if(x==0 && y==0)begin
    frame<=sync;dir_frame<=dir_sync;name_frame<=name_sync;
    if(sync[18:2]!=frame[18:2] || name_sync!=name_frame ||
       (sync[2] && (sync[1:0]!=frame[1:0] || dir_sync!=dir_frame)))notice<=NOTICE_FRAMES;
    else if(notice!=0)notice<=notice-1'b1;
   end
  end
 end
 wire [5:0] number=total==0 ? 6'd0 : {1'b0,selected}+1'b1;
 wire [4:0] seconds=interval==0 ? 5'd2 : interval==1 ? 5'd5 : interval==2 ? 5'd10 : 5'd20;
 reg [511:0] line0,line1; // 32 fixed-width UTF-16 BMP codepoints per line.
 always @* begin
  line0=512'h56fe7247002000300030002f003000300020002081ea52a88f6e64adff1a517395ed002000200020002000200020002000200020002000200020002000200020; // 图片 00/00  自动轮播：关闭
  line1=512'h95f49694ff1a0030003079d20020002065b95411ff1a6b635e8f0020002000200020002000200020002000200020002000200020002000200020002000200020; // 间隔：00秒  方向：正序
  line0[511-3*16 -: 16]=16'h0030+number/10;
  line0[511-4*16 -: 16]=16'h0030+number%10;
  line0[511-6*16 -: 16]=16'h0030+total/10;
  line0[511-7*16 -: 16]=16'h0030+total%10;
  if(autoplay)begin
  line0[511-15*16 -: 16]=16'h5f00;
  line0[511-16*16 -: 16]=16'h542f;
  end
  line1[511-3*16 -: 16]=16'h0030+seconds/10;
  line1[511-4*16 -: 16]=16'h0030+seconds%10;
  if(dir_frame)begin
  line1[511-11*16 -: 16]=16'h5012;
  end
  if(!shown)begin
   case(status)
    0:line0=512'h6b635728521d59cb5316005400465361002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020; // 正在初始化TF卡
    1:line0=512'h6b6357288bfb53d6004600410054003300325206533a002000200020002000200020002000200020002000200020002000200020002000200020002000200020; // 正在读取FAT32分区
    2:line0=512'h6b635728626b63cf0042004d005056fe724700200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020; // 正在扫描BMP图片
    3:begin
  line0=512'h6b63572852a08f7d56fe7247002000300030002f0030003000200020002000200020002000200020002000200020002000200020002000200020002000200020; // 正在加载图片 00/00
  line0[511-7*16 -: 16]=16'h0030+number/10;
  line0[511-8*16 -: 16]=16'h0030+number%10;
  line0[511-10*16 -: 16]=16'h0030+total/10;
  line0[511-11*16 -: 16]=16'h0030+total%10;
    end
    4,5:line0=512'h6b63572851c65907663e793a00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020; // 正在准备显示
    10:line0=512'h95198bef00310030ff1a9700898100460041005400330032683c5f0f002000200020002000200020002000200020002000200020002000200020002000200020; // 错误10：需要FAT32格式
    11:line0=512'h95198bef00310031ff1a672a627e52307b265408683c5f0f768456fe724700200020002000200020002000200020002000200020002000200020002000200020; // 错误11：未找到符合格式的图片
    12:line0=512'h95198bef00310032ff1a56fe72476570636e5f025e38002000200020002000200020002000200020002000200020002000200020002000200020002000200020; // 错误12：图片数据异常
    13:line0=512'h95198bef00310033ff1a65874ef67c0794fe635f574f002000200020002000200020002000200020002000200020002000200020002000200020002000200020; // 错误13：文件簇链损坏
    14:line0=512'h95198bef00310034ff1a8bfb536162167f135b588d8565f600200020002000200020002000200020002000200020002000200020002000200020002000200020; // 错误14：读卡或缓存超时
    default:line0=512'h95198bef00310035ff1a8bfb53d672b660015f025e38002000200020002000200020002000200020002000200020002000200020002000200020002000200020; // 错误15：读取状态异常
   endcase
   if(status>=10)line1=512'h6309004b00450059003191cd8bd5ff0c8bf768c067e5005400465361002000200020002000200020002000200020002000200020002000200020002000200020; // 按KEY1重试，请检查TF卡
   else line1=512'h683976ee5f550042004d0050ff1a0036003400300078003400380030ff0c003200344f4d00200020002000200020002000200020002000200020002000200020; // 根目录BMP：640x480，24位
  end
 end
 // FAT short names use blank-padded eight-byte basename and three-byte suffix.
 // Display a compact basename.ext, e.g. PIC01.BMP, without the padding.
 function [511:0] filename_line;
 input [87:0] short_name;
 integer j,k;
 reg [7:0] value;
 begin
  filename_line={32{16'h0020}};k=0;
  for(j=0;j<8;j=j+1)begin
   value=short_name[87-j*8 -: 8];
   if(value!=8'h20 && value!=0)begin
    filename_line[511-k*16 -: 16]={8'h00,value};k=k+1;
   end
  end
  if(k!=0)begin
   filename_line[511-k*16 -: 16]=16'h002e;k=k+1;
   for(j=8;j<11;j=j+1)begin
    value=short_name[87-j*8 -: 8];
    if(value!=8'h20 && value!=0)begin
     filename_line[511-k*16 -: 16]={8'h00,value};k=k+1;
    end
   end
  end
 end
 endfunction
 wire [511:0] filename_text=filename_line(name_frame);
 reg [511:0] counter_text,auto_text;
 always @* begin
  counter_text={32{16'h0020}};
  counter_text[511 -: 16]=16'h0030+number/10;
  counter_text[495 -: 16]=16'h0030+number%10;
  counter_text[479 -: 16]=16'h002f;
  counter_text[463 -: 16]=16'h0030+total/10;
  counter_text[447 -: 16]=16'h0030+total%10;
  auto_text={32{16'h0020}};
  auto_text[511 -: 48]=48'h8f6e64adff1a; // 轮播：
  auto_text[463 -: 32]=autoplay ? 32'h5f00542f : 32'h517395ed; // 开启 / 关闭
 end
 reg [9:0] tx,ty;
 reg [4:0] column,column_pixel;
 reg [3:0] row_pixel;
 reg [15:0] character;
 reg in_panel,in_text;
 reg [511:0] selected_line;
 always @* begin
  tx=0;ty=0;column=0;column_pixel=0;row_pixel=0;character=16'h0020;
  in_panel=0;in_text=0;selected_line={32{16'h0020}};
  if(de && (!shown || notice!=0))begin
   if(shown)begin
    if(y>=16 && y<32 && x>=16 && x<232)begin
     in_text=1;tx=x-16;ty=y-16;selected_line=filename_text;
    end else if(y>=16 && y<32 && x>=534 && x<624)begin
     in_text=1;tx=x-534;ty=y-16;selected_line=counter_text;
    end else if(x>=16 && x<592)begin
     if(y>=(autoplay ? 424 : 452) && y<(autoplay ? 440 : 468))begin
      in_text=1;tx=x-16;ty=y-(autoplay ? 424 : 452);selected_line=auto_text;
     end else if(autoplay && y>=452 && y<468)begin
      in_text=1;tx=x-16;ty=y-452;selected_line=line1;
     end
    end
   end else if(x>=16 && x<592)begin
    if(y>=16 && y<32)begin in_text=1;tx=x-16;ty=y-16;selected_line=line0;end
    else if(y>=452 && y<468)begin in_text=1;tx=x-16;ty=y-452;selected_line=line1;end
   end
  end
  in_panel=in_text;
  if(in_text)begin
   column=tx/18;column_pixel=tx%18;row_pixel=ty[3:0];
   character=selected_line >> ((31-column)*16);
  end
 end
 wire [15:0] font_pixels;
 osd_font16 u_font(.clk(pixel_clk),.codepoint(character),.row(row_pixel),.pixels(font_pixels));
 reg panel_delayed=0,text_delayed=0,error_delayed=0;
 reg [4:0] column_delayed=0;
 always @(posedge pixel_clk or negedge rst_n)begin
  if(!rst_n)begin panel_delayed<=0;text_delayed<=0;error_delayed<=0;column_delayed<=0;end
  else begin
   panel_delayed<=in_panel;text_delayed<=in_text;
   error_delayed<=status>=10 && !shown;column_delayed<=column_pixel;
  end
 end
 always @* begin
  // Only illuminated glyph pixels replace the picture. Gaps/blank cells pass through.
  overlay_active=panel_delayed && text_delayed && column_delayed<16 && font_pixels[15-column_delayed];
  rgb=overlay_active ? (error_delayed ? 24'hff9090 : 24'he8f4ff) : 24'h000000;
 end
endmodule
