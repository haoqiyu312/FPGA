`timescale 1ns/1ps
module tb_dynamic_keys;
reg clk=0;always #10 clk=~clk;
reg rst=1,ready=1,n=1,p=1,a=1,dir=0;reg[5:0]total=0;
wire[4:0]index;wire run_n,mode;wire[1:0]sw;wire sd;
image_key_control #(.DEBOUNCE_CYCLES(3),.RESET_CYCLES(8),.CLOCK_HZ(20)) dut(
clk,rst,ready,n,p,index,run_n,a,2'b00,mode,dir,total,sw,sd);
task ticks(input integer count);repeat(count)begin @(posedge clk);#1;end endtask
task next_key;begin n=0;ticks(8);n=1;ticks(12);end endtask
task prev_key;begin p=0;ticks(8);p=1;ticks(12);end endtask
integer i;
initial begin
 #1;rst=0;#10;rst=1;ticks(10);
 next_key;if(index!=0 || !run_n)$fatal(1,"empty catalog stepped");
 total=1;ticks(5);next_key;prev_key;if(index!=0)$fatal(1,"one image wrap");
 total=5;ticks(5);prev_key;if(index!=4)$fatal(1,"5 image reverse wrap");
 next_key;if(index!=0)$fatal(1,"5 image next wrap");
 total=32;ticks(5);prev_key;if(index!=31)$fatal(1,"32 image reverse wrap");
 next_key;if(index!=0)$fatal(1,"32 image forward wrap");
 for(i=0;i<12;i=i+1)next_key;
 if(index!=12)$fatal(1,"wide index");
 total=3;ticks(10);if(index!=0)$fatal(1,"removed images not clamped");
 dir=1;ticks(8);a=0;ticks(8);a=1;
 wait(!run_n);#1;if(index!=2 || !sd)$fatal(1,"dynamic reverse autoplay");
 $display("PASS zero/one/5/32 image catalogs, both wraps, catalog shrink, reverse autoplay");$finish;
end
initial begin #1000000;$fatal(1,"timeout");end
endmodule
