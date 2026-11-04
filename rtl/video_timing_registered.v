// Registered parameterized video timing. Sync -> back porch -> active -> front porch.
// Every output comes from the same sampled counter value; no combinational
// multi-bit counter decode is exposed to the transmitter.
module video_timing_registered #(
 parameter integer WIDTH=720,HEIGHT=720,HTOTAL=940,VTOTAL=768,
 HSA=20,HBP=100,VSA=8,VBP=20
) (
 input wire pixel_clk, input wire rst_n,
 output reg [9:0] pixel_x,pixel_y,
 output reg de,hsync,vsync
);
 reg [9:0] h_count,v_count;
 always @(posedge pixel_clk or negedge rst_n) begin
  if(!rst_n) begin
   h_count<=0;v_count<=0;pixel_x<=HTOTAL-HSA-HBP;pixel_y<=VTOTAL-VSA-VBP;
   de<=0;hsync<=0;vsync<=0;
  end else begin
   if(h_count==HTOTAL-1) begin
    h_count<=0;
    if(v_count==VTOTAL-1) v_count<=0;else v_count<=v_count+1'b1;
   end else h_count<=h_count+1'b1;
   hsync<=!(h_count<HSA);
   vsync<=!(v_count<VSA);
   de<=h_count>=HSA+HBP && h_count<HSA+HBP+WIDTH && v_count>=VSA+VBP && v_count<VSA+VBP+HEIGHT;
   pixel_x<=h_count>=HSA+HBP ? h_count-(HSA+HBP) : h_count+(HTOTAL-HSA-HBP);
   pixel_y<=v_count>=VSA+VBP ? v_count-(VSA+VBP) : v_count+(VTOTAL-VSA-VBP);
  end
 end
endmodule
