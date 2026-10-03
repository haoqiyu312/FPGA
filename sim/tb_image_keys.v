`timescale 1ns/1ps
module tb_image_keys;
reg clk=0;always #10 clk=~clk;
reg rst_n=1,ready=0,n=1,p=1;
wire ignored_mode;wire [4:0] index;wire run_n;
image_key_control #(.DEBOUNCE_CYCLES(5),.RESET_CYCLES(8)) dut(clk,rst_n,ready,n,p,index,run_n,1'b1,2'b00,ignored_mode,1'b0,6'd4,,);
task ticks(input integer count);repeat(count)begin @(posedge clk);#1;end endtask
task press_next;begin @(negedge clk);n=0;ticks(20);@(negedge clk);n=1;ticks(20);end endtask
task press_prev;begin @(negedge clk);p=0;ticks(20);@(negedge clk);p=1;ticks(20);end endtask
initial begin
 #1;rst_n=0;#10;rst_n=1;ticks(5);
 press_next;if(index!=0)$fatal(1,"accepted during loading");
 ready=1;ticks(5);
 // Short bounce should not change the index.
 @(negedge clk);n=0;ticks(2);@(negedge clk);n=1;ticks(10);
 if(index!=0)$fatal(1,"bounce accepted");
 @(negedge clk);n=0;ticks(10);
 if(index!=1 || run_n)$fatal(1,"next/reset pulse failed");
 ticks(100);if(index!=1)$fatal(1,"repeat while held");
 @(negedge clk);n=1;ticks(15);
 press_next;if(index!=2)$fatal(1,"next 2");
 press_next;if(index!=3)$fatal(1,"next 3");
 press_next;if(index!=0)$fatal(1,"next wrap");
 press_prev;if(index!=3)$fatal(1,"previous wrap");
 @(negedge clk);n=0;p=0;ticks(20);
 if(index!=3)$fatal(1,"simultaneous buttons");
 rst_n=0;#1;if(index!=0)$fatal(1,"KEY1 reset");
 $display("PASS debounce, busy guard, held key, both directions, wrap, simultaneous keys, KEY1");$finish;
end
endmodule
