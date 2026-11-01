// Chinese frame-latched OSD with a built-in 16x16 synchronous glyph ROM.
// The output has one pixel-clock of latency; top-level delay accounts for it.
module image_status_osd #(
 parameter integer WIDTH=640,HEIGHT=480,FONT_LATENCY=1,
 parameter integer NOTICE_FRAMES=120,
 parameter integer SPECTRUM_HINT=1,
 parameter integer FEATURE_HINTS=0
)(input wire pixel_clk,rst_n,input wire [9:0] x,y,input wire de,
 input wire image_shown,input wire [3:0] load_status,
 input wire [4:0] image_index,input wire [5:0] image_total,
 input wire auto_mode,input wire [1:0] interval_setting,input wire reverse_direction,input wire video_mode,
 output reg overlay_active,output reg [23:0] rgb,
 input wire [87:0] image_name,
 output wire [15:0] font_codepoint,output wire [3:0] font_row,input wire [15:0] font_pixels);
 (* dont_touch="true" *) reg [18:0] meta=0,sync=0;
 reg [18:0] frame=0;
 // Packed snapshot is stable long before a displayed frame begins.
 wire shown=frame[18]; wire [3:0] status=frame[17:14];
 wire [4:0] selected=frame[13:9];wire [5:0] total=frame[8:3];
 wire autoplay=frame[2];wire [1:0] interval=frame[1:0];
 // Direction is held separately so the snapshot layout stays explicit below.
 reg dir_meta=0,dir_sync=0,dir_frame=0;
 reg video_meta=0,video_sync=0,video_frame=0;
 (* dont_touch="true" *) reg [87:0] name_meta={11{8'h20}},name_sync={11{8'h20}};
 reg [87:0] name_frame={11{8'h20}};
 reg [7:0] notice=NOTICE_FRAMES;
 always @(posedge pixel_clk or negedge rst_n)begin
  if(!rst_n)begin meta<=0;sync<=0;frame<=0;notice<=NOTICE_FRAMES;dir_meta<=0;dir_sync<=0;dir_frame<=0;video_meta<=0;video_sync<=0;video_frame<=0;name_meta<={11{8'h20}};name_sync<={11{8'h20}};name_frame<={11{8'h20}};end
  else begin
   meta<={image_shown,load_status,image_index,image_total,auto_mode,interval_setting};sync<=meta;
   dir_meta<=reverse_direction;dir_sync<=dir_meta;video_meta<=video_mode;video_sync<=video_meta;name_meta<=image_name;name_sync<=name_meta;
   if(x==0 && y==0)begin
    frame<=sync;dir_frame<=dir_sync;video_frame<=video_sync;name_frame<=name_sync;
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
   else line1=512'h683976ee5f550042004d0050ff1a0036003400300078003400380030ff0c003200344f4d00200020002000200020002000200020002000200020002000200020; // Root BMP format; dimensions below come from the build parameters.
  end
  if(!shown && status<10)begin
   line1[511-7*16 -: 16]=16'h0030+WIDTH/100;
   line1[511-8*16 -: 16]=16'h0030+(WIDTH/10)%10;
   line1[511-9*16 -: 16]=16'h0030+WIDTH%10;
   line1[511-11*16 -: 16]=16'h0030+HEIGHT/100;
   line1[511-12*16 -: 16]=16'h0030+(HEIGHT/10)%10;
   line1[511-13*16 -: 16]=16'h0030+HEIGHT%10;
  end
 end
 // FAT short names use blank-padded eight-byte basename and three-byte suffix.
 // Display a compact basename.ext, e.g. PIC01.BMP, without the padding.
 function [511:0] filename_line;
 input [87:0] short_name;
 integer j;
 reg [3:0] length;
 reg [7:0] value;
 begin
  // Trim only trailing FAT basename padding. Fixed output slices avoid an
  // eight-step variable-position 512-bit update chain.
  length=0;
  for(j=0;j<8;j=j+1)
   if(short_name[87-j*8 -: 8]!=8'h20 && short_name[87-j*8 -: 8]!=0)length=j+1;
  filename_line={32{16'h0020}};
  for(j=0;j<12;j=j+1)begin
   value=8'h20;
   if(j<length)case(j)
    0:value=short_name[87:80];1:value=short_name[79:72];
    2:value=short_name[71:64];3:value=short_name[63:56];
    4:value=short_name[55:48];5:value=short_name[47:40];
    6:value=short_name[39:32];7:value=short_name[31:24];
    default:value=8'h20;
   endcase
   else if(length!=0 && j==length)value=8'h2e;
   else if(length!=0)case(j-length)
    1:value=short_name[23:16];2:value=short_name[15:8];3:value=short_name[7:0];
    default:value=8'h20;
   endcase
   filename_line[511-j*16 -: 16]={8'h00,value};
  end
 end
 endfunction
 wire [511:0] filename_text=filename_line(name_frame);
 reg [511:0] counter_text,auto_text,controls_text;
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
  auto_text[415 -: 32]=32'h95f49694; // 间隔
  auto_text[383 -: 16]=16'hff1a;
  auto_text[367 -: 16]=16'h0030+seconds/10;
  auto_text[351 -: 16]=16'h0030+seconds%10;
  auto_text[335 -: 16]=16'h79d2;
  auto_text[303 -: 32]=32'h65b95411; // 方向
  auto_text[271 -: 16]=16'hff1a;
  auto_text[255 -: 32]=dir_frame ? 32'h50126b63 : 32'h6b636b63; // 倒序 / 正序
  controls_text={32{16'h0020}};
  controls_text=video_frame ?
    512'h89c698910020004b003464ad653e002f6682505c0020957f63098fd456de83dc5355000000000000000000000000000000000000000000000000000000000000 :
    512'h004b00324e0b4e005f200020004b00334e0a4e005f200020004b003464ad653e002f6682505c0020957f63098fd456de83dc5355000000000000000000000000;
  if(FEATURE_HINTS)begin
  controls_text=video_frame ?
    512'h004b003298918c310020004b00335b575e550020004b003464ad653e002f6682505c0020957f63098fd456de83dc535500200020002000200020002000200020 :
    512'h004b0032002f0033520756fe002053cc952e7f29653e0020957f6309004b00335b575e550020004b003464ad653e002000200020002000200020002000200020;
   if(video_frame && !SPECTRUM_HINT)controls_text=512'h004b00335b575e5500200020004b003464ad653e002f6682505c00200020957f63098fd456de83dc535500200020002000200020002000200020002000200020;
  end
 end
 // These words depend only on frame-latched state. Register their
 // construction separately; the first text row starts at y=16, long after
 // frame-state updates at (0,0), so this adds no visible content delay.
 reg [511:0] line0_ready,line1_ready,filename_ready,counter_ready,auto_ready,controls_ready;
 always @(posedge pixel_clk)begin
  line0_ready<=line0;line1_ready<=line1;filename_ready<=filename_text;
  counter_ready<=counter_text;auto_ready<=auto_text;controls_ready<=controls_text;
 end
 reg [9:0] tx,ty;
 reg [4:0] column,column_pixel;
 integer glyph_cell;
 reg [3:0] row_pixel;
 reg [15:0] character;
 reg in_panel,in_text;
 reg [511:0] selected_line;
 always @* begin
  tx=0;ty=0;column=0;column_pixel=0;row_pixel=0;character=16'h0020;
  in_panel=0;in_text=0;selected_line={32{16'h0020}};
  if(de)begin
   if(shown)begin
    if(y>=16 && y<32 && x>=16 && x<232)begin
     in_text=1;tx=x-16;ty=y-16;selected_line=FONT_LATENCY==2 ? filename_ready : filename_text;
    end else if(y>=16 && y<32 && x>=WIDTH-106 && x<WIDTH-16)begin
     in_text=1;tx=x-(WIDTH-106);ty=y-16;selected_line=FONT_LATENCY==2 ? counter_ready : counter_text;
    end else if(x>=16 && x<592)begin
     if(y>=HEIGHT-56 && y<HEIGHT-40)begin
      in_text=1;tx=x-16;ty=y-(HEIGHT-56);selected_line=FONT_LATENCY==2 ? auto_ready : auto_text;
     end else if(y>=HEIGHT-28 && y<HEIGHT-12)begin
      in_text=1;tx=x-16;ty=y-(HEIGHT-28);selected_line=FONT_LATENCY==2 ? controls_ready : controls_text;
     end
    end
   end else if(x>=16 && x<592)begin
    if(y>=16 && y<32)begin in_text=1;tx=x-16;ty=y-16;selected_line=FONT_LATENCY==2 ? line0_ready : line0;end
    else if(y>=HEIGHT-28 && y<HEIGHT-12)begin in_text=1;tx=x-16;ty=y-(HEIGHT-28);selected_line=FONT_LATENCY==2 ? line1_ready : line1;end
   end
  end
  in_panel=in_text;
  if(in_text)begin
   row_pixel=ty[3:0];
   // Decode fixed 18-pixel cells in parallel, avoiding divide/modulo followed
   // by a variable 512-bit text-word mux in the same pixel clock.
   for(glyph_cell=0;glyph_cell<32;glyph_cell=glyph_cell+1)begin
    if(tx>=glyph_cell*18 && tx<(glyph_cell+1)*18)begin
     column=glyph_cell;column_pixel=tx-glyph_cell*18;
     character=selected_line[511-glyph_cell*16 -: 16];
    end
   end
  end
 end
 assign font_codepoint=character;
 assign font_row=row_pixel;
 reg panel_delayed=0,text_delayed=0,error_delayed=0;
 reg [4:0] column_delayed=0;
 reg panel_stage2=0,text_stage2=0,error_stage2=0;
 reg [4:0] column_stage2=0;
 wire glyph_panel=FONT_LATENCY==2 ? panel_stage2 : panel_delayed;
 wire glyph_text=FONT_LATENCY==2 ? text_stage2 : text_delayed;
 wire glyph_error=FONT_LATENCY==2 ? error_stage2 : error_delayed;
 wire [4:0] glyph_column=FONT_LATENCY==2 ? column_stage2 : column_delayed;
 always @(posedge pixel_clk or negedge rst_n)begin
  if(!rst_n)begin panel_delayed<=0;text_delayed<=0;error_delayed<=0;column_delayed<=0;panel_stage2<=0;text_stage2<=0;error_stage2<=0;column_stage2<=0;end
  else begin
   panel_stage2<=panel_delayed;text_stage2<=text_delayed;
   error_stage2<=error_delayed;column_stage2<=column_delayed;
   panel_delayed<=in_panel;text_delayed<=in_text;
   error_delayed<=status>=10 && !shown;column_delayed<=column_pixel;
  end
 end
 always @* begin
  // Only illuminated glyph pixels replace the picture. Gaps/blank cells pass through.
  overlay_active=glyph_panel && glyph_text && glyph_column<16 && font_pixels[15-glyph_column];
  rgb=overlay_active ? (glyph_error ? 24'hff9090 : 24'he8f4ff) : 24'h000000;
 end
endmodule
