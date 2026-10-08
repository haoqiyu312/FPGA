`timescale 1ns/1ps
module tb_switch_debounce;
 reg clk=0;
 always #10 clk=~clk;
 reg reset_n=0;
 reg [2:0] switches=0;
 wire [1:0] interval,interval_one;
 wire direction,direction_one;
 image_key_control #(.DEBOUNCE_CYCLES(5)) dut(
  .clk(clk),.reset_n(reset_n),.image_ready(1'b1),
  .key_next_n(1'b1),.key_prev_n(1'b1),.key_auto_n(1'b1),
  .interval_switch(switches[1:0]),.direction_switch(switches[2]),
  .image_total(6'd4),.stable_interval(interval),.stable_direction(direction));
 image_key_control #(.DEBOUNCE_CYCLES(1)) dut_one(
  .clk(clk),.reset_n(reset_n),.image_ready(1'b1),
  .key_next_n(1'b1),.key_prev_n(1'b1),.key_auto_n(1'b1),
  .interval_switch(switches[1:0]),.direction_switch(switches[2]),
  .image_total(6'd4),.stable_interval(interval_one),.stable_direction(direction_one));

 // Independent reference: accept iff the last five sampled values all match.
 reg [14:0] history=0;
 reg [2:0] expected=0,one_sample=0;
 always @(posedge clk)begin
  if(!reset_n)begin history=0;expected=0;one_sample=0;end
  else begin
   history={history[11:0],dut.sw_sync};
   if(history=={5{history[2:0]}})expected=history[2:0];
   one_sample=dut_one.sw_sync;
  end
  #1;
  if({direction,interval}!==expected)
   $fatal(1,"debounce mismatch: got %b expected %b",{direction,interval},expected);
  if({direction_one,interval_one}!==one_sample)
   $fatal(1,"one-cycle debounce mismatch");
 end
 task drive(input [2:0] value,input integer cycles);
  begin @(negedge clk);switches=value;repeat(cycles)@(negedge clk);end
 endtask
 integer i;
 initial begin
  repeat(2)@(negedge clk);reset_n=1;
  // Total bouncing exceeds the threshold, but no candidate stays for five clocks.
  for(i=0;i<12;i=i+1)begin drive(3'b001,2);drive(3'b110,2);end
  drive(3'b000,8);
  if({direction,interval}!==3'b000)$fatal(1,"alternating candidates accepted");
  drive(3'b101,8);
  if({direction,interval}!==3'b101)$fatal(1,"stable new value not accepted");
  drive(3'b010,2);drive(3'b101,8);
  if({direction,interval}!==3'b101)$fatal(1,"brief bounce changed stable value");
  drive(3'b110,4);drive(3'b011,8);
  if({direction,interval}!==3'b011)$fatal(1,"changed candidate not accepted");
  @(negedge clk);reset_n=0;switches=0;
  repeat(3)@(negedge clk);
  if({direction,interval}!==0)$fatal(1,"reset did not clear switch state");
  $display("PASS switch debounce: alternating candidates, exact window, bounce, reset, one-cycle threshold");
  $finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
