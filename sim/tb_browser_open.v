`timescale 1ns/1ps
module tb_browser_open;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,open_event=0,open_video=0,mode_event=0;
 reg[4:0] selected=0;
 wire video_mode,short_press,media_reset_n,run_reset_n,auto_mode;
 wire[4:0] image_index;wire[1:0] interval;wire direction;
 media_key_control #(.DEBOUNCE_CYCLES(2),.LONG_CYCLES(20),.RESET_CYCLES(4),.EXTERNAL_ACTIONS(1),.EXTERNAL_OPEN(1)) mode(
 .clk(clk),.reset_n(rst_n),.key_auto_n(1'b1),.restart_n(1'b1),.video_mode(video_mode),
 .short_press(short_press),.media_reset_n(media_reset_n),.mode_event(mode_event),.restart_event(1'b0),.open_event(open_event),.open_video(open_video));
 image_key_control #(.DEBOUNCE_CYCLES(2),.EXTERNAL_SELECTION(1)) images(
 .clk(clk),.reset_n(media_reset_n),.image_ready(1'b0),.key_next_n(1'b1),.key_prev_n(1'b1),
 .image_index(image_index),.run_reset_n(run_reset_n),.key_auto_n(1'b1),.interval_switch(2'd0),
 .auto_mode(auto_mode),.direction_switch(1'b0),.image_total(6'd4),.stable_interval(interval),.stable_direction(direction),
 .next_event(1'b0),.prev_event(1'b0),.initial_index(selected));
 task launch(input reg video,input reg[4:0] index);
 begin
  @(negedge clk);selected=index;open_video=video;open_event=1;
  @(posedge clk);#1;if(media_reset_n || video_mode!=video)$fatal(1,"open must reset to requested mode");
  @(negedge clk);open_event=0;
  repeat(7)@(negedge clk);
  if(!media_reset_n || image_index!=index || auto_mode)$fatal(1,"selected image not restored after reset");
 end endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;repeat(3)@(negedge clk);
  launch(0,2);launch(1,2);launch(1,2);launch(0,3);
  @(negedge clk);mode_event=1;open_event=1;open_video=0;
  @(posedge clk);#1;if(video_mode || short_press)$fatal(1,"file open priority");
  $display("PASS exact image selection, same-mode video reload, media reset and open priority");$finish;
 end
 initial begin #10000;$fatal(1,"open test timeout");end
endmodule

module tb_browser_autoplay;
 reg clk=0;always #5 clk=~clk;
 reg reset_n=0,sw1=0,sw2=0,paused=0;
 wire[4:0] image_index;wire auto_mode,run_reset_n;wire[1:0] interval;
 image_key_control #(.DEBOUNCE_CYCLES(2),.CLOCK_HZ(4),.RESET_CYCLES(2),
  .EXTERNAL_SELECTION(1),.EXTERNAL_AUTO_LEVEL(1)) dut(
  .clk(clk),.reset_n(reset_n),.image_ready(1'b1),.key_next_n(1'b1),.key_prev_n(1'b1),
  .image_index(image_index),.run_reset_n(run_reset_n),.key_auto_n(1'b1),
  .interval_switch({sw2,sw1}),.auto_mode(auto_mode),.auto_pause(paused),
  .direction_switch(1'b0),.image_total(6'd2),.stable_interval(interval),.stable_direction(),
  .next_event(1'b0),.prev_event(1'b0),.initial_index(5'd0));
 task wait_cycles(input integer n);begin repeat(n)@(negedge clk);end endtask
 initial begin
  wait_cycles(3);reset_n=1;wait_cycles(8);
  if(auto_mode || image_index!=0)$fatal(1,"SW1 off must start in menu/manual state");
  sw1=1;wait_cycles(9);
  if(!auto_mode || interval!=1)$fatal(1,"SW1 must enable 5s picture slideshow");
  wait_cycles(28);if(image_index!=1)$fatal(1,"slideshow should advance BMP ordinal");
  paused=1;wait_cycles(5);if(auto_mode)$fatal(1,"KEY4 pause must stop slideshow");
  wait_cycles(30);if(image_index!=1)$fatal(1,"paused slideshow advanced");
  paused=0;wait_cycles(9);if(!auto_mode)$fatal(1,"KEY4 resume failed");
  sw1=0;wait_cycles(9);if(auto_mode)$fatal(1,"SW1 off failed");
  wait_cycles(30);if(image_index!=1)$fatal(1,"SW1 off advanced image");
  $display("PASS SW1 picture-only slideshow, KEY4 pause/resume, SW1 off");$finish;
 end
 initial begin #10000;$fatal(1,"autoplay timeout");end
endmodule

module tb_browser_mode_keys;
 reg clk=0;always #5 clk=~clk;
 reg reset_n=0,key_n=1;
 wire video_mode,short_press,long_press,media_reset_n;
 integer shorts=0,longs=0;
 media_key_control #(.DEBOUNCE_CYCLES(2),.LONG_CYCLES(20),.RESET_CYCLES(4),
  .BROWSER_KEYS(1),.EXTERNAL_OPEN(1)) dut(
  .clk(clk),.reset_n(reset_n),.key_auto_n(key_n),.restart_n(1'b1),
  .video_mode(video_mode),.short_press(short_press),.long_press(long_press),
  .media_reset_n(media_reset_n),.mode_event(1'b0),.restart_event(1'b0),
  .open_event(1'b0),.open_video(1'b0));
 always @(negedge clk)begin if(short_press)shorts=shorts+1;if(long_press)longs=longs+1;end
 initial begin
  repeat(3)@(negedge clk);reset_n=1;
  @(negedge clk);key_n=0;repeat(6)@(negedge clk);key_n=1;
  repeat(6)@(negedge clk);
  if(shorts!=1 || longs!=0 || video_mode)$fatal(1,"KEY4 short should pause/open once");
  key_n=0;repeat(30)@(negedge clk);key_n=1;repeat(6)@(negedge clk);
  if(shorts!=1 || longs!=1 || video_mode)$fatal(1,"KEY4 long should reopen menu without mode switch");
  $display("PASS KEY4 short/open and long/menu, no legacy mode switch");$finish;
 end
 initial begin #10000;$fatal(1,"browser key timeout");end
endmodule

module tb_browser_prefetch_guard;
 reg clk=0;always #5 clk=~clk;
 reg reset_n=0,catalog_done=0,nav_open=0;
 reg[1:0] kind=1;
 wire opened;integer count=0;
 touch_file_browser dut(.clk(clk),.reset_n(reset_n),.enable(1'b1),.catalog_done(catalog_done),
  .file_count(6'd1),.query_type(kind),.open_event(opened),.nav_open(nav_open),
  .nav_up(1'b0),.nav_down(1'b0),.nav_menu(1'b0));
 always @(negedge clk)if(opened)count=count+1;
 initial begin
  repeat(3)@(negedge clk);reset_n=1;catalog_done=1;
  kind=3;nav_open=1;@(negedge clk);nav_open=0;repeat(2)@(negedge clk);
  if(count!=0)$fatal(1,"audio file must remain list-only");
  kind=1;catalog_done=0;nav_open=1;@(negedge clk);nav_open=0;repeat(2)@(negedge clk);
  if(count!=0)$fatal(1,"file cannot open before the directory scan finishes");
  catalog_done=1;nav_open=1;@(negedge clk);nav_open=0;repeat(2)@(negedge clk);
  if(count!=1)$fatal(1,"selected image did not open after scan");
  $display("PASS browser blocks audio open and waits for catalog readiness");$finish;
 end
 initial begin #10000;$fatal(1,"prefetch guard timeout");end
endmodule
