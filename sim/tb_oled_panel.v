`timescale 1ns/1ps
module tb_oled_panel;
 parameter ADDRESS_3D=0;
 reg clk=0;always #5 clk=~clk;reg reset_n=0;reg menu_view=1,video_view=0;
 tri1 scl,sda;reg ack=0;assign sda=ack ? 1'b0 : 1'bz;
 wire[2:0] page;wire[6:0] column;wire fetch,valid,online,chosen_address;wire[7:0] pixels;
 wire[4:0] query;wire[15:0] code;wire[3:0] row;wire[15:0] font_pixels;
 reg[15:0] code_pipe;reg[3:0] row_pipe;
 wire[121:0] ui={88'h4120202020202020424d50,1'b1,menu_view,6'd3,5'd0,4'd3,4'd3,video_view,1'b0,1'b0,5'd5,1'b0,1'b1,1'b1,2'd0};
 wire[87:0] name=query==0 ? "A       BMP" : query==1 ? "B       RV " : "C       WAV";
 ssd1306_i2c #(.CLOCK_HZ(16000),.I2C_HZ(1000),.POWER_CYCLES(20)) bus(
  clk,reset_n,scl,sda,page,column,fetch,valid,pixels,online,chosen_address);
 oled_text_renderer text(clk,reset_n,fetch,page,column,ui,name,query,valid,pixels,code,row,font_pixels);
 always @(posedge clk)begin code_pipe<=code;row_pipe<=row;end
 osd_font16 font(.clk(clk),.codepoint(code_pipe),.row(row_pipe),.pixels(font_pixels),.codepoint_b(16'd32),.row_b(4'd0),.pixels_b());
 reg in_packet=0,addressed=0;integer bits=0,byte_number=0,writes=0,p=0,c=0,packets=0;
 reg[7:0] rx=0,control=0;reg[7:0] expected[0:3071];
 always @(negedge sda)if(scl===1'b1)begin
  in_packet=1;bits=0;byte_number=0;rx=0;addressed=0;packets=packets+1;
 end
 always @(posedge sda)if(scl===1'b1)begin in_packet=0;ack=0;end
 always @(posedge scl)if(in_packet)begin
  if(bits<8)begin rx={rx[6:0],sda};bits=bits+1;end else if(bits==8)bits=9;
 end
 always @(negedge scl)if(in_packet)begin
  if(bits==8)begin
   if(byte_number==0)addressed=rx==(ADDRESS_3D ? 8'h7a : 8'h78);
   ack=addressed;
   if(addressed)begin
    if(byte_number==1)control=rx;
    else if(byte_number>=2)begin
     if(control==0)begin if((rx&8'hf8)==8'hb0)begin p=rx&7;c=0;end end
     else if(control==8'h40)begin
      if(rx!==expected[(writes<1024 ? 0 : writes<2048 ? 1024 : 2048)+p*128+c])$fatal(1,"OLED raster byte p=%d c=%d got=%h expected=%h",p,c,rx,expected[(writes<1024 ? 0 : writes<2048 ? 1024 : 2048)+p*128+c]);
      c=c+1;writes=writes+1;if(writes==1024)menu_view=0;if(writes==2048)video_view=1;
     end
    end
   end
  end else if(bits==9)begin ack=0;bits=0;byte_number=byte_number+1;rx=0;end
 end
 initial begin
  $readmemh("sim/fixtures/oled_menu.hex",expected,0,1023);
  $readmemh("sim/fixtures/oled_playback.hex",expected,1024,2047);
  $readmemh("sim/fixtures/oled_video.hex",expected,2048,3071);
  repeat(4)@(negedge clk);reset_n=1;
  wait(writes==3072);repeat(20)@(negedge clk);
  if(!online || chosen_address!=ADDRESS_3D)$fatal(1,"OLED init/address fallback");
  $display("PASS SSD1306 address %h, init, page commands, 3072 I2C raster bytes (menu/image/video), CJK/ASCII, shared-font latency",ADDRESS_3D ? 8'h3d : 8'h3c);$finish;
 end
 initial begin #10000000;$fatal(1,"OLED timeout state=%d busphase=%d writes=%d",bus.state,bus.u_bus.phase,writes);end
endmodule
