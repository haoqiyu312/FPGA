// Keyboard-only mixed-media browser with a continuously scrolling 8-row view.
module touch_file_browser(
 input wire clk,reset_n,enable,catalog_done,
 input wire[5:0] file_count,input wire[1:0] query_type,
 output reg visible,output reg[4:0] scroll_first,
 output reg selection_valid,output reg[4:0] selected,
 output reg open_event,output wire open_video,
 output wire[4:0] query_index,
 input wire nav_up,nav_down,nav_open,nav_menu
);
 assign query_index=selected;
 assign open_video=query_type==2;
 wire selection_outside={1'b0,selected}>=file_count;
 wire[4:0] next_down=selected==file_count-1'b1 ? 5'd0 : selected+1'b1;
 wire[4:0] next_up=selected==0 ? file_count[4:0]-1'b1 : selected-1'b1;
 wire[5:0] next_down_ext={1'b0,next_down};
 wire[5:0] next_up_ext={1'b0,next_up};
 wire[5:0] scroll_end={1'b0,scroll_first}+6'd8;

 always @(posedge clk or negedge reset_n)begin
  if(!reset_n)begin
   visible<=1;scroll_first<=0;selection_valid<=1;selected<=0;open_event<=0;
  end else begin
   open_event<=0;
   if(!enable)begin
    open_event<=0;
   end else if(nav_menu && !visible)begin
    visible<=1;
   end else if(visible && catalog_done && file_count!=0)begin
    if(nav_down || nav_up)begin
     if(!selection_valid || selection_outside)begin
      selected<=0;scroll_first<=0;
     end else if(nav_down)begin
      selected<=next_down;selection_valid<=1;
      if(next_down_ext<{1'b0,scroll_first})scroll_first<=next_down;
      else if(next_down_ext>=scroll_end)scroll_first<=next_down-5'd7;
     end else begin
      selected<=next_up;selection_valid<=1;
      if(next_up_ext<{1'b0,scroll_first})scroll_first<=next_up;
      else if(next_up_ext>=scroll_end)scroll_first<=next_up-5'd7;
     end
    end else if(nav_open && selection_valid && !selection_outside &&
                (query_type==1 || query_type==2))begin
     open_event<=1;visible<=0;
    end
   end
  end
 end
endmodule
