// Hold the SD interface idle until card power settles; retry transient failures.
module tf_startup_control #(
 parameter integer POWER_WAIT_CYCLES=50000000,
 parameter integer SWITCH_WAIT_CYCLES=500000,
 parameter integer RETRY_WAIT_CYCLES=25000000,
 parameter integer ERROR_WAIT_CYCLES=500000,
 parameter integer MAX_RETRIES=3
)(input wire clk,reset_n,locked,load_error,
 output reg run_enable=0,input wire fast_start);
 reg [31:0] wait_count=0,error_count=0;
 reg [2:0] retry_count=0;
 always @(posedge clk or negedge reset_n) begin
  if(!reset_n) begin run_enable<=0;wait_count<=0;error_count<=0;retry_count<=0;end
  else if(!locked) begin run_enable<=0;wait_count<=0;error_count<=0;retry_count<=0;end
  else if(!run_enable) begin
   error_count<=0;
   if(wait_count==(retry_count!=0 ? RETRY_WAIT_CYCLES-1 : (fast_start ? SWITCH_WAIT_CYCLES-1 : POWER_WAIT_CYCLES-1))) begin
    run_enable<=1;wait_count<=0;
   end else wait_count<=wait_count+1'b1;
  end else if(load_error && retry_count<MAX_RETRIES) begin
   if(error_count==ERROR_WAIT_CYCLES-1) begin
    run_enable<=0;wait_count<=0;error_count<=0;retry_count<=retry_count+1'b1;
   end else error_count<=error_count+1'b1;
  end else error_count<=0;
 end
endmodule
