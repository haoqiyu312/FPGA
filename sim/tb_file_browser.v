`timescale 1ns/1ps
module tb_file_browser;
 reg clk=0;always #5 clk=~clk;
 reg reset_n=0,enable=1,catalog_done=1;
 reg nav_up=0,nav_down=0,nav_open=0,nav_menu=0;
 reg[5:0] count=17;
 wire visible,selected_valid,open_event,open_video;wire[4:0]scroll_first,selected,query;
 wire[1:0]kind=query==1 ? 2 : query==2 ? 3 : 1;
 touch_file_browser dut(.clk(clk),.reset_n(reset_n),.enable(enable),.catalog_done(catalog_done),
  .file_count(count),.query_type(kind),.visible(visible),.scroll_first(scroll_first),
  .selection_valid(selected_valid),.selected(selected),.open_event(open_event),.open_video(open_video),
  .query_index(query),.nav_up(nav_up),.nav_down(nav_down),.nav_open(nav_open),.nav_menu(nav_menu));
 integer opens=0;reg last_video;
 always @(negedge clk)if(open_event)begin opens=opens+1;last_video=open_video;end
 task tick(input integer n);begin repeat(n)@(negedge clk);#1;end endtask
 task down;begin nav_down=1;tick(1);nav_down=0;tick(1);end endtask
 task up;begin nav_up=1;tick(1);nav_up=0;tick(1);end endtask
 task open_selected;begin nav_open=1;tick(1);nav_open=0;tick(1);end endtask
 task back_to_list;begin nav_menu=1;tick(1);nav_menu=0;tick(1);end endtask
 integer i;
 initial begin
  tick(3);reset_n=1;tick(2);
  if(!visible || !selected_valid || selected!=0 || scroll_first!=0)$fatal(1,"initial browser state");
  down();if(selected!=1 || scroll_first!=0)$fatal(1,"next selection");
  open_selected();if(visible || opens!=1 || !last_video)$fatal(1,"open video");
  back_to_list();if(!visible)$fatal(1,"KEY4 long returns to list");
  down();open_selected();if(!visible || opens!=1 || selected!=2)$fatal(1,"audio is listed but not opened");
  down();open_selected();if(visible || opens!=2 || last_video)$fatal(1,"open image");
  back_to_list();
  for(i=0;i<9;i=i+1)down();
  if(selected!=12 || scroll_first!=5)$fatal(1,"continuous scroll at item 13: selected=%0d first=%0d",selected,scroll_first);
  for(i=0;i<10;i=i+1)up();
  if(selected!=2 || scroll_first!=2)$fatal(1,"scroll follows selection backward: selected=%0d first=%0d",selected,scroll_first);
  for(i=0;i<2;i=i+1)up();
  if(selected!=0 || scroll_first!=0)$fatal(1,"scroll reaches first item");
  for(i=0;i<16;i=i+1)up();
  if(selected!=1 || scroll_first!=1)$fatal(1,"scroll window follows reverse navigation");
  for(i=0;i<16;i=i+1)up();
  if(selected!=2 || scroll_first!=2)$fatal(1,"selection wraps at file count: selected=%0d first=%0d",selected,scroll_first);
  catalog_done=0;open_selected();if(opens!=2 || !visible)$fatal(1,"ignore open while scan is incomplete");
  enable=0;down();if(selected!=2)$fatal(1,"ignore navigation while media reset is active");
  enable=1;catalog_done=1;back_to_list();
  nav_menu=1;tick(1);nav_menu=0;tick(1);if(!visible)$fatal(1,"menu remains visible");
  $display("PASS keyboard selection, continuous scrolling, wrap, image/video open, audio list-only, return-to-list and scan gating");$finish;
 end
 initial begin #100000;$fatal(1,"browser timeout");end
endmodule
