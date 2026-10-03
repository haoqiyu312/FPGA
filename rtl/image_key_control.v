module image_key_control #(
 parameter integer DEBOUNCE_CYCLES=1000000,
 parameter integer RESET_CYCLES=64,
 parameter integer CLOCK_HZ=50000000
)(input wire clk,reset_n,image_ready,key_next_n,key_prev_n,
 output reg [4:0] image_index=0,output wire run_reset_n,
 input wire key_auto_n,input wire [1:0] interval_switch,
 output reg auto_mode=0,input wire direction_switch,
 input wire [5:0] image_total,
 output wire [1:0] stable_interval, output wire stable_direction);
 reg [2:0] ready_sync=0;
 wire next_press,prev_press,auto_press;
 reg [6:0] reset_count=0;
 reg [2:0] sw_meta=0,sw_sync=0,sw_stable=0,sw_previous=0;
 reg [19:0] sw_count=0;
 reg [25:0] second_count=0;
 reg [4:0] elapsed_seconds=0;
 wire [4:0] interval_seconds=sw_stable[1:0]==0 ? 5'd2 : sw_stable[1:0]==1 ? 5'd5 : sw_stable[1:0]==2 ? 5'd10 : 5'd20;
 assign stable_interval=sw_stable[1:0];
 assign stable_direction=sw_stable[2];
 wire [4:0] last_image=image_total-1'b1;
 assign run_reset_n=reset_n && reset_count==0;
 key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_next(clk,reset_n,key_next_n,next_press);
 key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_prev(clk,reset_n,key_prev_n,prev_press);
 key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_auto(clk,reset_n,key_auto_n,auto_press);
 wire manual_step=next_press!=prev_press;
 wire auto_step=auto_mode && !auto_press && ready_sync[2] && reset_count==0 &&
                sw_stable==sw_previous && second_count==CLOCK_HZ-1 && elapsed_seconds==interval_seconds-1;
 always @(posedge clk or negedge reset_n) begin
  if(!reset_n) begin
   ready_sync<=0;image_index<=0;reset_count<=0;auto_mode<=0;
   sw_meta<=0;sw_sync<=0;sw_stable<=0;sw_previous<=0;sw_count<=0;
   second_count<=0;elapsed_seconds<=0;
  end else begin
   ready_sync<={ready_sync[1:0],image_ready};
   sw_meta<={direction_switch,interval_switch};sw_sync<=sw_meta;sw_previous<=sw_stable;
   if(sw_sync==sw_stable)sw_count<=0;
   else if(sw_count==DEBOUNCE_CYCLES-1)begin sw_stable<=sw_sync;sw_count<=0;end
   else sw_count<=sw_count+1'b1;
   if(auto_press) auto_mode<=~auto_mode;
   if(!auto_mode || auto_press || !ready_sync[2] || reset_count!=0 ||
      manual_step || auto_step || sw_stable!=sw_previous) begin
    second_count<=0;elapsed_seconds<=0;
   end else if(second_count==CLOCK_HZ-1)begin
    second_count<=0;elapsed_seconds<=elapsed_seconds+1'b1;
   end else second_count<=second_count+1'b1;
   if(reset_count!=0)reset_count<=reset_count-1'b1;
   else if(ready_sync[2] && image_total!=0 && manual_step) begin
    image_index<=next_press ? (image_index==last_image ? 5'd0 : image_index+1'b1) :
                             (image_index==0 ? last_image : image_index-1'b1);
    reset_count<=RESET_CYCLES;
   end else if(auto_step && image_total!=0)begin
    image_index<=sw_stable[2] ? (image_index==0 ? last_image : image_index-1'b1) :
                              (image_index==last_image ? 5'd0 : image_index+1'b1);
    reset_count<=RESET_CYCLES;
   end
   if(image_total!=0 && image_index>=image_total)image_index<=0;
  end
 end
endmodule
