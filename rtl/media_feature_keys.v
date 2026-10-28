// Debounce K2/K3 as a pair. Release actions avoid an accidental image step
// before a chord is recognized. One chord action until BOTH keys are released.
module media_feature_keys #(
 parameter integer DEBOUNCE_CYCLES=1000000,
 parameter integer LONG_CYCLES=50000000
)(input wire clk,rst_n,next_n,prev_n,browser_visible,video_mode,
 output reg next_event,prev_event,
 output reg [1:0] zoom,output reg subtitles,output reg spectrum);
 reg [1:0] meta,sync,stable,candidate;
 localparam BITS=DEBOUNCE_CYCLES<=1 ? 1 : $clog2(DEBOUNCE_CYCLES);
 reg [BITS-1:0] count;
 reg [1:0] pending;
 reg chord,blocked;
 reg last_browser,last_video;
 localparam HOLD_BITS=LONG_CYCLES<=1 ? 1 : $clog2(LONG_CYCLES);
 reg [HOLD_BITS-1:0] hold_count;
 reg held_long;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   meta<=3;sync<=3;stable<=3;candidate<=3;count<=0;
   pending<=0;chord<=0;blocked<=0;next_event<=0;prev_event<=0;hold_count<=0;held_long<=0;
   zoom<=0;subtitles<=1;spectrum<=1;
  end else begin
   meta<={prev_n,next_n};sync<=meta;next_event<=0;prev_event<=0;
   if(sync==stable)begin candidate<=sync;count<=0;end
   else if(sync!=candidate && DEBOUNCE_CYCLES>1)begin candidate<=sync;count<=1;end
   else if(DEBOUNCE_CYCLES<=1 || count==DEBOUNCE_CYCLES-1)begin
    stable<=sync;count<=0;
    if(sync==0 && !chord)begin
     chord<=1;pending<=0;
     if(!browser_visible && !blocked)begin
      if(video_mode)subtitles<=~subtitles;
      else zoom<=zoom==2 ? 0 : zoom+1'b1;
     end
    end else if(sync==3)begin
     if(!chord && !blocked && !held_long)begin
      if(video_mode && !browser_visible)begin
       if(pending==1)spectrum<=~spectrum;
       if(pending==2)subtitles<=~subtitles;
      end else begin next_event<=pending==1;prev_event<=pending==2;end
     end
     pending<=0;chord<=0;blocked<=0;
    end else if(!chord)pending<=~sync;
   end else count<=count+1'b1;
   if(stable!=1 || chord || browser_visible || video_mode || blocked)begin
    hold_count<=0;
    if(stable==3)held_long<=0;
   end else if(!held_long)begin
    if(hold_count==LONG_CYCLES-1)begin subtitles<=~subtitles;held_long<=1;hold_count<=0;end
    else hold_count<=hold_count+1'b1;
   end
   // An open/menu action while a navigation key is held must not leak a release.
   if(browser_visible!=last_browser || video_mode!=last_video)begin
    pending<=0;blocked<=stable!=3;
   end
  end
 end
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin last_browser<=1;last_video<=0;end
  else begin last_browser<=browser_visible;last_video<=video_mode;end
endmodule
