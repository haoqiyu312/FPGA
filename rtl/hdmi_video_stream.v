// Frame marker on first active pixel; line marker on pixel 639 (not 640).
// RGB, valid and markers share one registered pipeline stage.
module hdmi_video_stream (
 input wire clk,rst,vs,de,input wire [23:0] rgb,
 output reg valid,sof,last,output reg [23:0] data
);
 reg vs_d,frame_pending;
 reg [9:0] column;
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   vs_d<=0;frame_pending<=1;column<=0;
   valid<=0;sof<=0;last<=0;data<=0;
  end else begin
   vs_d<=vs;valid<=de;sof<=0;last<=0;data<=rgb;
   if(vs!=vs_d)frame_pending<=1;
   if(de) begin
    sof<=frame_pending;
    frame_pending<=0;
    last<=column==639;
    column<=column==639 ? 0 : column+1'b1;
   end else column<=0;
  end
 end
endmodule
