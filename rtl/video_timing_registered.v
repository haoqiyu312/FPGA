// Registered 640x480 timing. Sync -> back porch -> active -> front porch.
// Every output comes from the same sampled counter value; no combinational
// multi-bit counter decode is exposed to the transmitter.
module video_timing_640x480 (
 input wire pixel_clk, input wire rst_n,
 output reg [9:0] pixel_x,pixel_y,
 output reg de,hsync,vsync
);
 reg [9:0] h_count,v_count;
 always @(posedge pixel_clk or negedge rst_n) begin
  if(!rst_n) begin
   h_count<=0;v_count<=0;pixel_x<=656;pixel_y<=490;
   de<=0;hsync<=0;vsync<=0;
  end else begin
   if(h_count==799) begin
    h_count<=0;
    if(v_count==524) v_count<=0;else v_count<=v_count+1'b1;
   end else h_count<=h_count+1'b1;
   hsync<=!(h_count<96);
   vsync<=!(v_count<2);
   de<=h_count>=144 && h_count<784 && v_count>=35 && v_count<515;
   pixel_x<=h_count>=144 ? h_count-10'd144 : h_count+10'd656;
   pixel_y<=v_count>=35 ? v_count-10'd35 : v_count+10'd490;
  end
 end
endmodule
