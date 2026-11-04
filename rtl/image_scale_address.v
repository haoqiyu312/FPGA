// Fixed-rate nearest-neighbour address mapping: 100%, centered 50%, center-crop
// 200%. The full frame stream is still consumed, so FIFO/timing stay unchanged.
// ack is in the memory domain; settings latch while the FIFO is reset.
module image_scale_address #(parameter integer WIDTH=720,HEIGHT=720) (
 input wire clk,rst,ack,read_en,video_mode,
 input wire [1:0] zoom_request,
 input wire [20:0] address,
 output wire [20:0] mapped_address
);
 reg [1:0] zoom_meta,zoom_sync,zoom;
 reg [9:0] col,row;
 reg [9:0] sx,sy;
 always @(posedge clk or posedge rst)begin
  if(rst)begin zoom_meta<=0;zoom_sync<=0;zoom<=0;col<=0;row<=0;end
  else begin
   zoom_meta<=zoom_request;zoom_sync<=zoom_meta;
   if(ack)begin zoom<=zoom_sync;col<=0;row<=0;end
   else if(read_en)begin
    if(col==WIDTH-1)begin col<=0;row<=row==HEIGHT-1 ? 0 : row+1'b1;end
    else col<=col+1'b1;
   end
  end
 end
 always @* begin
  sx=col;sy=row;
  case(zoom)
   1:begin // centered half-size image; invisible margins use a safe address
    sx=(col>=WIDTH/4 && col<WIDTH*3/4) ? ((col-(WIDTH/4))<<1) : 10'd0;
    sy=(row>=HEIGHT/4 && row<HEIGHT*3/4) ? ((row-(HEIGHT/4))<<1) : 10'd0;
   end
   2:begin sx=(WIDTH/4)+(col>>1);sy=(HEIGHT/4)+(row>>1);end
   default:begin sx=col;sy=row;end
  endcase
 end
 wire [20:0] scaled=sy*WIDTH+sx;
 assign mapped_address=video_mode ? address : scaled;
endmodule
