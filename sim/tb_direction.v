`timescale 1ns/1ps
module tb_direction;
reg clk=0;always #10 clk=~clk;
reg rst=1,ready=1,n=1,p=1,a=1,dir=0;
wire [4:0] index;wire run_n,mode;
image_key_control #(.DEBOUNCE_CYCLES(3),.RESET_CYCLES(8),.CLOCK_HZ(100)) dut(clk,rst,ready,n,p,index,run_n,a,2'b00,mode,dir,6'd4,,);
task ticks(input integer count);repeat(count)begin @(posedge clk);#1;end endtask
task step(input [1:0] expected);begin
 wait(!run_n);#1;if(index!=expected)$fatal(1,"index %d expected %d",index,expected);
 ready=0;ticks(20);ready=1;ticks(6);
end endtask
initial begin
 #1;rst=0;#10;rst=1;ticks(8);
 a=0;ticks(8);a=1;ticks(8);
 step(1);
 // A brief SW3 bounce must not change direction.
 dir=1;ticks(1);dir=0;ticks(8);
 if(dut.sw_stable[2])$fatal(1,"direction bounce accepted");
 dir=1;ticks(8);if(!dut.sw_stable[2])$fatal(1,"direction not sampled");
 step(0);step(3);step(2);
 a=0;ticks(8);a=1;ticks(8);if(mode)$fatal(1,"stop failed");
 n=0;ticks(8);n=1;ticks(12);if(index!=3)$fatal(1,"manual next changed by SW3");
 p=0;ticks(8);p=1;ticks(12);if(index!=2)$fatal(1,"manual previous changed by SW3");
 $display("PASS SW3 direction, debounce, reverse wrap, manual keys independent");$finish;
end
initial begin #1000000;$fatal(1,"timeout");end
endmodule
