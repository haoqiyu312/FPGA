// Reveal each newly loaded image over 32 display frames. No second image bank:
// effects reveal from black, then leave all pixels unchanged. UI stays above it.
module media_transition (
 input wire clk,rst_n,frame_start,shown,video_mode,
 input wire [9:0] x,y,input wire [23:0] rgb_in,
 output reg [23:0] rgb_out,output reg [1:0] effect
);
 reg [5:0] progress;
 reg was_shown;
 wire [9:0] edge_x={progress,4'b0}+{progress,2'b0}; // progress * 20
 wire [9:0] edge_y={progress,3'b0}+{progress,2'b0}+{progress,1'b0}+progress;
 wire [13:0] red_product=rgb_in[23:16]*progress;
 wire [13:0] green_product=rgb_in[15:8]*progress;
 wire [13:0] blue_product=rgb_in[7:0]*progress;
 wire [7:0] fade_r=red_product[12:5];
 wire [7:0] fade_g=green_product[12:5];
 wire [7:0] fade_b=blue_product[12:5];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin progress<=32;was_shown<=0;effect<=2;end
  else if(frame_start)begin
   was_shown<=shown;
   if(!shown)progress<=0;
   else if(!was_shown)begin progress<=0;effect<=effect==2 ? 0 : effect+1'b1;end
   else if(progress<32)progress<=progress+1'b1;
  end
 end
 always @* begin
  rgb_out=rgb_in;
  if(!video_mode && progress<32)begin
   case(effect)
    0:rgb_out={fade_r,fade_g,fade_b};
    1:if(x>=edge_x)rgb_out=0;
    default:if((x[5]^y[5]) ? x>=edge_x : y>=edge_y)rgb_out=0;
   endcase
  end
 end
endmodule
