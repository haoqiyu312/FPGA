`timescale 1ns/1ps
module tb_startup;
reg clk=0;always #10 clk=~clk;
reg reset_n=1,locked=0,error=0,fast=0;
wire run_enable;
tf_startup_control #(.POWER_WAIT_CYCLES(10),.SWITCH_WAIT_CYCLES(2),.RETRY_WAIT_CYCLES(5),.ERROR_WAIT_CYCLES(3),.MAX_RETRIES(3)) dut(clk,reset_n,locked,error,run_enable,fast);
integer i;
task tick;begin @(posedge clk);#1;end endtask
task power_wait;begin
 for(i=0;i<9;i=i+1) begin tick;if(run_enable)$fatal(1,"released too soon");end
 tick;if(!run_enable)$fatal(1,"did not release");
end endtask
initial begin
 // No key press: rely on FPGA power-up register values.
 tick;if(run_enable)$fatal(1,"running without lock");
 @(negedge clk);locked=1;power_wait;
 @(negedge clk);error=1;
 repeat(3) begin
 repeat(3) tick;
 if(run_enable)$fatal(1,"missing automatic reset");
 @(negedge clk);error=0;
 repeat(4)begin tick;if(run_enable)$fatal(1,"retry delay too short");end
 tick;if(!run_enable)$fatal(1,"retry did not start");
 @(negedge clk);error=1;
 end
 repeat(10)begin tick;if(!run_enable)$fatal(1,"retry limit failed");end
 @(negedge clk);reset_n=0;#1;if(run_enable)$fatal(1,"key reset failed");
 @(negedge clk);reset_n=1;error=0;power_wait;
 @(negedge clk);reset_n=0;fast=1;
 @(negedge clk);reset_n=1;
 tick;if(run_enable)$fatal(1,"fast start too early");
 tick;if(!run_enable)$fatal(1,"fast start missing");
 @(negedge clk);locked=0;tick;if(run_enable)$fatal(1,"lock loss failed");
 $display("PASS cold start without KEY1, settling delay, 3 retries, KEY1, fast switch, lock loss");$finish;
end
endmodule
