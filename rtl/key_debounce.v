// Synchronize active-low KEY input; one pulse per press, no repeat while held.
module key_debounce #(parameter integer DEBOUNCE_CYCLES=1000000)(
 input wire clk,reset_n,key_n,output reg pressed=0
);
 reg [1:0] key_sync=2'b11;
 reg stable=1;
 reg [19:0] count=0;
 always @(posedge clk or negedge reset_n) begin
  if(!reset_n) begin key_sync<=3;stable<=1;count<=0;pressed<=0;end
  else begin
   key_sync<={key_sync[0],key_n};pressed<=0;
   if(key_sync[1]==stable)count<=0;
   else if(count==DEBOUNCE_CYCLES-1) begin
    stable<=key_sync[1];count<=0;
    if(!key_sync[1]) pressed<=1;
   end else count<=count+1'b1;
  end
 end
endmodule
