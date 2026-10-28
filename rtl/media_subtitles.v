// Built-in coffee advertisement captions; video cues advance with presented media
// frames, so pause/loading freeze the timeline. Glyph ROM is shared with OSD.
module media_subtitles (
 input wire clk,rst_n,frame_start,frame_started,shown,video_mode,enabled,
 input wire [7:0] fps,input wire [1:0] zoom,
 input wire [9:0] x,y,input wire de,
 output wire font_request,output wire [15:0] font_codepoint,
 output wire [3:0] font_row,input wire [15:0] font_pixels,
 output wire panel,output wire ink
);
 reg [7:0] frames;
 reg [1:0] cue,display_cue;
 reg [1:0] display_zoom;
 reg display_enabled,display_video;
 wire [9:0] cue_length={2'b0,fps}+({2'b0,fps}<<1);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin frames<=0;cue<=0;display_cue<=0;display_zoom<=0;display_enabled<=0;display_video<=0;end
  else begin
   if(!shown || !video_mode)begin frames<=0;cue<=0;end
   else if(frame_started)begin
    if({2'b0,frames}+1>=cue_length)begin frames<=0;cue<=cue==2 ? 0 : cue+1'b1;end
    else frames<=frames+1'b1;
   end
   if(frame_start)begin display_cue<=cue;display_zoom<=zoom;display_enabled<=enabled && shown;display_video<=video_mode;end
  end
 end
 reg [511:0] text_line;
 always @* begin
  text_line=512'h4eca65e563a88350ff1a73b078e85496556100200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020;
  if(display_video)case(display_cue)
   0:text_line=512'h4eca65e563a88350ff1a73b078e85496556100200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020;
   1:text_line=512'h9999918773b08403ff0c6bcf4e0053e390fd662f597d65f651490020002000200020002000200020002000200020002000200020002000200020002000200020;
   2:text_line=512'h65b054c14e0a5e02ff0c6b228fce52305e9754c15c1d002000200020002000200020002000200020002000200020002000200020002000200020002000200020;
   default:text_line=512'h4eca65e563a88350ff1a73b078e85496556100200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020;
  endcase
  else begin
   text_line=512'h56fe72477f29653eff1a003500300025002000310030003000250020003200300030002500200020002000200020002000200020002000200020002000200020;
   // Highlight the actual zoom value with a second, compact fixed phrase.
   case(display_zoom)
    0:text_line=512'h56fe72477f29653eff1a00310030003000250020539f59cb753b9762002000200020002000200020002000200020002000200020002000200020002000200020;
    1:text_line=512'h56fe72477f29653eff1a00350030002500205c454e2d7f295c0f0020002000200020002000200020002000200020002000200020002000200020002000200020;
    2:text_line=512'h56fe72477f29653eff1a003200300030002500204e2d5fc3653e5927002000200020002000200020002000200020002000200020002000200020002000200020;
    default:begin end
   endcase
  end
 end
 wire region=de && x>=64 && x<576 && y>=376 && y<400;
 wire text_region=region && y>=380 && y<396;
 wire [8:0] tx=x-10'd64;
 assign font_request=text_region && display_enabled;
 assign font_codepoint=font_request ? text_line[511-tx[8:4]*16 -: 16] : 16'h0020;
 assign font_row=y-10'd380;
 reg panel_d,ink_d;
 reg [3:0] bit_d;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin panel_d<=0;ink_d<=0;bit_d<=0;end
  else begin panel_d<=region && display_enabled;ink_d<=font_request;bit_d<=tx[3:0];end
 end
 assign panel=panel_d;
 assign ink=ink_d && font_pixels[15-bit_d];
endmodule
