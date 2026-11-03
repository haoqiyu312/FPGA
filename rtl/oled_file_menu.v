// Selection remains in the system clock; catalog query settles before OPEN.
module oled_file_menu #(parameter PREFETCH_CYCLES=64)(
 input wire clk,reset_n,enable,catalog_done,input wire[5:0] file_count,
 input wire[1:0] query_type,input wire up,down,confirm,back,
 output reg visible,output wire valid,output reg[4:0] selected,
 output reg open_event,output wire open_video,output wire[4:0] query_index);
 reg opened;reg[6:0] settle;
 assign valid=catalog_done && file_count!=0 && {1'b0,selected}<file_count;
 assign open_video=query_type==2;assign query_index=selected;
 always @(posedge clk or negedge reset_n)begin
  if(!reset_n)begin visible<=1;selected<=0;open_event<=0;opened<=0;settle<=0;end
  else begin
   open_event<=0;
   if(!catalog_done)settle<=0;else if(settle<PREFETCH_CYCLES)settle<=settle+1'b1;
   if(enable)begin
    if(back && opened)visible<=~visible;
    else if(visible && valid)begin
     if(up || down)begin
      selected<=down ? (selected==file_count-1'b1 ? 5'd0 : selected+1'b1) : (selected==0 ? file_count-1'b1 : selected-1'b1);
      settle<=0;
     end else if(confirm && settle==PREFETCH_CYCLES && (query_type==1 || query_type==2))begin
      visible<=0;open_event<=1;opened<=1;
     end
    end
   end
  end
 end
endmodule
