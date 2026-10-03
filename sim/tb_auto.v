`timescale 1ns/1ps
module tb_auto;
reg clk=0;always #10 clk=~clk;
reg rst_n=1,ready=0,n=1,p=1,a=1;reg[1:0]sw=0;
wire[4:0]index;wire run_n,mode;
image_key_control #(.DEBOUNCE_CYCLES(3),.RESET_CYCLES(8),.CLOCK_HZ(100)) dut(clk,rst_n,ready,n,p,index,run_n,a,sw,mode,1'b0,6'd4,,);
task ticks(input integer count);repeat(count)begin @(posedge clk);#1;end endtask
task toggle_auto;begin @(negedge clk);a=0;ticks(8);@(negedge clk);a=1;ticks(8);end endtask
integer i;
initial begin
 #1;rst_n=0;#10;rst_n=1;ticks(5);
 toggle_auto;if(!mode)$fatal(1,"toggle on");
 ticks(300);if(index!=0)$fatal(1,"timer during loading");
 ready=1;wait(dut.ready_sync[2]);ticks(199);
 if(index!=0)$fatal(1,"2 seconds too short");
 ticks(2);if(index!=1 || run_n)$fatal(1,"no auto step index=%d reset=%d second=%d elapsed=%d mode=%b",index,dut.reset_count,dut.second_count,dut.elapsed_seconds,mode);
 ready=0;ticks(300);if(index!=1)$fatal(1,"advanced while loading");
 ready=1;ticks(10);toggle_auto;if(mode)$fatal(1,"toggle off");
 ticks(300);if(index!=1)$fatal(1,"did not stop");
 // Verify every switch interval, restarting timing after each configuration.
 for(i=1;i<4;i=i+1)begin
  @(negedge clk);sw=i;ticks(12);toggle_auto;
  wait(index!=1);if(dut.interval_seconds!=(i==1?5:i==2?10:20))$fatal(1,"interval");
  toggle_auto;rst_n=0;#1;rst_n=1;ready=1;ticks(10);
  // Restore index 1 manually for the next case.
  @(negedge clk);n=0;ticks(8);@(negedge clk);n=1;ticks(12);
 end
 if(mode)$fatal(1,"KEY1 should stop autoplay");
 $display("PASS autoplay start/stop, loading pause, 2/5/10/20 second intervals, KEY1");$finish;
end
initial begin #1000000;$fatal(1,"timeout");end
endmodule
