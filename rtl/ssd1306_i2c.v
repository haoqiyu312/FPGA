// SSD1306 page mode, no local frame buffer. 100 kHz open-drain I2C.
// Renderer supplies one byte at a time; display absence never stalls media.
module ssd1306_i2c #(parameter CLOCK_HZ=48000000,I2C_HZ=100000,POWER_CYCLES=CLOCK_HZ/10)(
 input wire clk,reset_n,inout wire scl,sda,
 output reg[2:0] page,output reg[6:0] column,
 output reg fetch,input wire valid,input wire[7:0] pixels,
 output reg online,output reg address_3d);
 localparam DIV=CLOCK_HZ/(I2C_HZ*4);
 localparam DB=DIV<2 ? 1 : $clog2(DIV);
 reg[DB-1:0] divider;wire tick=divider==DIV-1;
 reg[23:0] delay_count;
 reg[3:0] state;localparam POWER=0,INIT=1,HEADER=2,FETCH=3,DATA=4,WAIT_BYTE=5;
 reg[5:0] index;reg[3:0] return_state;
 reg[7:0] tx;reg send,start_byte,stop_byte;
 wire busy,completed,nack;
 wire[7:0] address=address_3d ? 8'h7a : 8'h78;
 oled_i2c_byte u_bus(clk,reset_n,tick,send,start_byte,stop_byte,tx,scl,sda,busy,completed,nack);
 function[7:0] init_command;input[5:0] n;begin case(n)
  0:init_command=8'hae;1:init_command=8'hd5;2:init_command=8'h80;
  3:init_command=8'ha8;4:init_command=8'h3f;5:init_command=8'hd3;6:init_command=0;
  7:init_command=8'h40;8:init_command=8'h8d;9:init_command=8'h14;
  10:init_command=8'h20;11:init_command=8'h02;12:init_command=8'ha1;13:init_command=8'hc8;
  14:init_command=8'hda;15:init_command=8'h12;16:init_command=8'h81;17:init_command=8'h7f;
  18:init_command=8'hd9;19:init_command=8'hf1;20:init_command=8'hdb;21:init_command=8'h40;
  22:init_command=8'ha4;23:init_command=8'ha6;default:init_command=8'haf;
 endcase end endfunction
 always @(posedge clk or negedge reset_n)begin
  if(!reset_n)begin divider<=0;delay_count<=0;state<=POWER;index<=0;page<=0;column<=0;fetch<=0;online<=0;address_3d<=0;send<=0;start_byte<=0;stop_byte<=0;tx<=0;return_state<=INIT;end
  else begin
   divider<=tick ? 0 : divider+1'b1;send<=0;fetch<=0;
   case(state)
    POWER:if(delay_count>=POWER_CYCLES)begin delay_count<=0;index<=0;state<=INIT;end else delay_count<=delay_count+1'b1;
    INIT:if(!busy)begin
     tx<=index==0 ? address : index==1 ? 8'h00 : init_command(index-2);
     start_byte<=index==0;stop_byte<=index==26;send<=1;return_state<=INIT;state<=WAIT_BYTE;
    end
    HEADER:if(!busy)begin
     case(index)
      0:tx<=address;1:tx<=0;2:tx<=8'hb0|page;3:tx<=0;default:tx<=8'h10;
     endcase
     start_byte<=index==0;stop_byte<=index==4;send<=1;return_state<=HEADER;state<=WAIT_BYTE;
    end
    FETCH:begin fetch<=1;state<=DATA;end
    DATA:if(valid && !busy)begin
     tx<=pixels;start_byte<=0;stop_byte<=column==127;send<=1;return_state<=DATA;state<=WAIT_BYTE;
    end
    WAIT_BYTE:if(completed)begin
     if(nack)begin online<=0;address_3d<=~address_3d;state<=POWER;delay_count<=0;end
     else if(return_state==INIT)begin
      if(index==26)begin index<=0;page<=0;column<=0;state<=HEADER;online<=1;end
      else begin index<=index+1'b1;state<=INIT;end
     end else if(return_state==HEADER)begin
      if(index==4)begin index<=0;state<=WAIT_BYTE;return_state<=FETCH;tx<=address;start_byte<=1;stop_byte<=0;send<=1;end
      else begin index<=index+1'b1;state<=HEADER;end
     end else if(return_state==FETCH)begin
      tx<=8'h40;start_byte<=0;stop_byte<=0;send<=1;return_state<=POWER;
     end else if(return_state==POWER)state<=FETCH;
     else if(column==127)begin column<=0;page<=page+1'b1;index<=0;state<=HEADER;end
     else begin column<=column+1'b1;state<=FETCH;end
    end
   endcase
  end
 end
endmodule

module oled_i2c_byte(
 input wire clk,reset_n,tick,send,start_byte,stop_byte,input wire[7:0] data,
 inout wire scl,sda,output reg busy,output reg completed,output reg nack);
 reg scl_low,sda_low;reg[7:0] shift;reg[2:0] bit_number;reg stop_saved;
 reg[3:0] phase;
 (* async_reg="true" *) reg[1:0] sda_sync;
 assign scl=scl_low ? 1'b0 : 1'bz;assign sda=sda_low ? 1'b0 : 1'bz;
 always @(posedge clk or negedge reset_n)begin
  if(!reset_n)begin busy<=0;completed<=0;nack<=0;scl_low<=0;sda_low<=0;shift<=0;bit_number<=7;stop_saved<=0;phase<=0;sda_sync<=3;end
  else begin
   sda_sync<={sda_sync[0],sda};completed<=0;
   if(send && !busy)begin busy<=1;shift<=data;bit_number<=7;stop_saved<=stop_byte;nack<=0;phase<=start_byte ? 0 : 2;end
   else if(busy && tick)case(phase)
    0:begin scl_low<=0;sda_low<=0;phase<=1;end
    1:begin sda_low<=1;phase<=2;end
    2:begin scl_low<=1;phase<=3;end
    3:begin sda_low<=~shift[7];phase<=4;end
    4:begin scl_low<=0;phase<=12;end
    12:phase<=5;
    5:begin scl_low<=1;shift<={shift[6:0],1'b0};
       if(bit_number==0)phase<=6;else begin bit_number<=bit_number-1'b1;phase<=3;end
      end
    6:begin sda_low<=0;phase<=7;end
    7:begin scl_low<=0;phase<=13;end
    13:phase<=8;
    8:begin nack<=sda_sync[1];scl_low<=1;phase<=9;end
    9:if(stop_saved || nack)begin sda_low<=1;phase<=10;end
      else begin busy<=0;completed<=1;end
    10:begin scl_low<=0;phase<=11;end
    11:begin sda_low<=0;busy<=0;completed<=1;end
   endcase
  end
 end
endmodule
