`timescale 1ns/1ps
// Isolate actual system-clock controls; PLL/SD/HDMI are black boxes here.
module tb_oled_controls;
 reg clk=0;always #5 clk=~clk;reg rst_n=0;integer i;
 tf_media_oled_top dut(.sys_clk(clk),.sys_rst_n(rst_n),.keypad_columns(4'hf));
 task key(input[3:0] n);begin
  @(negedge clk);force dut.key_event=1;force dut.key_code=n;
  @(negedge clk);release dut.key_event;release dut.key_code;
  repeat(3)@(negedge clk);
 end endtask
 initial begin
  force dut.catalog_done_sys=3;force dut.file_count_sys=3;force dut.default_image_valid_sd=1;force dut.default_image_index_sd=2;
  force dut.query_type=1;force dut.query_bmp_index=0;force dut.query_name="A       BMP";
  repeat(4)@(negedge clk);rst_n=1;repeat(100)@(negedge clk);
  if(!dut.browser_visible || dut.requested_image!=2)$fatal(1,"boot menu/default image lookup");
  key(0);key(2);key(8);key(7);key(10);key(11);
  if(dut.interval_switch!=1 || !dut.direction_switch || !dut.spectrum_setting || !dut.subtitles_setting || dut.interval_seconds_control!=5 || dut.zoom_setting!=1)$fatal(1,"menu/image settings");
  key(9);repeat(70)@(negedge clk);if(dut.selected_file!=1)$fatal(1,"down key");
  key(1);repeat(70)@(negedge clk);if(dut.selected_file!=0)$fatal(1,"up key");
  key(5);repeat(70)@(negedge clk);
  if(dut.browser_visible || dut.video_mode || !dut.media_reset_n)$fatal(1,"open picture/reset");
  key(8);if(dut.interval_seconds_control!=4)$fatal(1,"S9 interval decrement");
  key(10);if(dut.interval_seconds_control!=5)$fatal(1,"S11 interval increment");
  for(i=0;i<4;i=i+1)key(8);
  key(8);if(dut.interval_seconds_control!=1)$fatal(1,"interval lower bound");
  for(i=0;i<19;i=i+1)key(10);
  key(10);if(dut.interval_seconds_control!=20)$fatal(1,"interval upper bound");
  for(i=0;i<15;i=i+1)key(8);
  if(dut.interval_seconds_control!=5)$fatal(1,"restore five-second interval");
  key(5);if(!dut.image_paused)$fatal(1,"picture pause");
  key(3);if(!dut.browser_visible)$fatal(1,"menu key");
  force dut.query_type=2;key(5);repeat(70)@(negedge clk);
  if(!dut.video_mode || dut.browser_visible)$fatal(1,"open video");
  key(0);if(dut.subtitles_setting)$fatal(1,"S1 video subtitle toggle");
  key(2);if(dut.spectrum_setting)$fatal(1,"S3 video spectrum toggle");
  key(5);if(!dut.video_paused_setting)$fatal(1,"video pause");
  key(12);repeat(70)@(negedge clk);if(dut.video_paused_setting || !dut.video_mode)$fatal(1,"replay");
  key(11);key(11);if(dut.zoom_setting!=0)$fatal(1,"zoom cycle");
  key(3);
  if(!dut.browser_visible || !dut.menu_background_active || dut.video_mode || dut.requested_image!=2)$fatal(1,"menu default BMP backdrop");
  key(3);
  if(dut.browser_visible || dut.menu_background_active || !dut.video_mode)$fatal(1,"restore video after closing menu");
  key(15);repeat(100)@(negedge clk);
  if(!dut.browser_visible || dut.interval_switch!=0 || dut.interval_seconds_control!=5 || dut.zoom_setting!=0 || !dut.subtitles_setting || !dut.spectrum_setting || dut.video_mode)$fatal(1,"matrix D global rescan/reset");
  $display("PASS actual OLED top system controls, all settings, navigation/open/pause/replay/menu and reset sequencing");$finish;
 end
endmodule
