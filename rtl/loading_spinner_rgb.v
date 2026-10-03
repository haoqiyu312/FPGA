// Compact monochrome spinner on a pure black background.
// Twelve softly edged dots; clockwise fading trail, ~20 steps/second.
module loading_spinner_rgb (
 input wire pixel_clk,rst_n,
 input wire [9:0] pixel_x,pixel_y,
 input wire de,
 output reg [23:0] rgb
);
 reg [3:0] phase=0;
 reg [1:0] frame_count=0;
 always @(posedge pixel_clk or negedge rst_n) begin
  if(!rst_n) begin phase<=0;frame_count<=0;end
  else if(pixel_x==0 && pixel_y==0) begin
   if(frame_count==2) begin
    frame_count<=0;
    phase<=phase==11 ? 4'd0 : phase+1'b1;
   end else frame_count<=frame_count+1'b1;
  end
 end
 integer i;
 reg [9:0] cx,cy;
 reg [10:0] dx,dy;
 reg [3:0] age;
 reg [7:0] brightness,shade;
 always @* begin
  rgb=24'h000000;cx=0;cy=0;dx=0;dy=0;age=0;brightness=0;shade=0;
  for(i=0;i<12;i=i+1) begin
   case(i)
    0:begin cx=320;cy=208;end
    1:begin cx=336;cy=212;end
    2:begin cx=348;cy=224;end
    3:begin cx=352;cy=240;end
    4:begin cx=348;cy=256;end
    5:begin cx=336;cy=268;end
    6:begin cx=320;cy=272;end
    7:begin cx=304;cy=268;end
    8:begin cx=292;cy=256;end
    9:begin cx=288;cy=240;end
    10:begin cx=292;cy=224;end
    11:begin cx=304;cy=212;end
   endcase
   age=phase>=i ? phase-i : phase+12-i;
   case(age)
    0:brightness=255;
    1:brightness=220;
    2:brightness=176;
    3:brightness=128;
    4:brightness=88;
    5:brightness=48;
    6:brightness=32;
    7:brightness=20;
    8:brightness=12;
    default:brightness=8;
   endcase
   dx=pixel_x>=cx ? pixel_x-cx : cx-pixel_x;
   dy=pixel_y>=cy ? pixel_y-cy : cy-pixel_y;
   shade=0;
   if(dx<=3 && dy<=3 && dx+dy<=5)shade=brightness;
   else if(dx<=4 && dy<=4 && dx+dy<=6)shade=brightness>>1;
   else if(dx<=5 && dy<=5 && dx+dy<=8)shade=brightness>>3;
   if(shade!=0)rgb={shade,shade,shade};
  end
  if(!de)rgb=0;
 end
endmodule
