`timescale 1ns/1ps
module tb_srt;
reg clk=0;always #5 clk=~clk;
reg rst=1,valid=0,done=0,frame=0,started=0;reg[7:0] data;
wire[15:0] text;wire visible;
reg[9:0] x=0;wire[9:0] prefetch=x+1-104;
wire request;wire[15:0] code;wire[3:0] row;wire panel,ink;
media_subtitles #(.WIDTH(720),.HEIGHT(720),.FONT_LATENCY(2)) renderer(
 .clk(clk),.rst_n(~rst),.frame_start(frame),.shown(1'b1),.video_mode(1'b1),.enabled(1'b1),
 .zoom(2'd0),.x(x),.y(10'd620),.de(1'b1),.font_request(request),.font_codepoint(code),.font_row(row),
 .font_pixels(16'd0),.panel(panel),.ink(ink),.external_codepoint(text),.external_visible(visible));
integer pixel;reg[15:0] expected;
srt_subtitles dut(clk,rst,data,valid,done,1'b0,clk,rst,frame,started,1'b1,1'b1,8'd1,32'd4,prefetch[8:4],text,visible);
task feed(input[7:0] b);begin @(negedge clk);data=b;valid=1;@(negedge clk);valid=0;end endtask
task show;begin x=104; @(negedge clk);frame=1;@(negedge clk);frame=0;started=1;@(negedge clk);started=0;repeat(100)@(negedge clk);end endtask
initial begin #30;rst=0;
feed(8'h31);
feed(8'h0d);
feed(8'h0a);
feed(8'h30);
feed(8'h30);
feed(8'h3a);
feed(8'h30);
feed(8'h30);
feed(8'h3a);
feed(8'h30);
feed(8'h30);
feed(8'h2c);
feed(8'h30);
feed(8'h30);
feed(8'h30);
feed(8'h20);
feed(8'h2d);
feed(8'h2d);
feed(8'h3e);
feed(8'h20);
feed(8'h30);
feed(8'h30);
feed(8'h3a);
feed(8'h30);
feed(8'h30);
feed(8'h3a);
feed(8'h30);
feed(8'h31);
feed(8'h2c);
feed(8'h30);
feed(8'h30);
feed(8'h30);
feed(8'h0d);
feed(8'h0a);
feed(8'h41);
feed(8'h42);
feed(8'h43);
feed(8'h0d);
feed(8'h0a);
feed(8'h0d);
feed(8'h0a);
feed(8'h32);
feed(8'h0d);
feed(8'h0a);
feed(8'h30);
feed(8'h30);
feed(8'h3a);
feed(8'h30);
feed(8'h30);
feed(8'h3a);
feed(8'h30);
feed(8'h32);
feed(8'h2c);
feed(8'h30);
feed(8'h30);
feed(8'h30);
feed(8'h20);
feed(8'h2d);
feed(8'h2d);
feed(8'h3e);
feed(8'h20);
feed(8'h30);
feed(8'h30);
feed(8'h3a);
feed(8'h30);
feed(8'h30);
feed(8'h3a);
feed(8'h30);
feed(8'h34);
feed(8'h2c);
feed(8'h30);
feed(8'h30);
feed(8'h30);
feed(8'h0d);
feed(8'h0a);
feed(8'he4);
feed(8'hbb);
feed(8'h8a);
feed(8'he6);
feed(8'h97);
feed(8'ha5);
feed(8'h0d);
feed(8'h0a);
@(negedge clk);done=1;repeat(10)@(negedge clk);
if(dut.count!=2)$fatal(1,"cue count %d",dut.count);
show;if(!visible || text!=16'h0041)$fatal(1,"first cue %h",text);
show;if(visible)$fatal(1,"gap must be empty");
show;if(!visible || text!=16'h4eca)$fatal(1,"UTF8 cue %h",text);
repeat(200)@(negedge clk);if(!visible)$fatal(1,"pause advanced cue");
show;if(!visible)$fatal(1,"end-exclusive bound");
show;if(!visible || text!=16'h41)$fatal(1,"loop did not reset");
for(pixel=0;pixel<720;pixel=pixel+1)begin
 @(negedge clk);x=pixel;
 @(posedge clk);
 if(request)begin
  expected=pixel<120 ? 16'h41 : pixel<136 ? 16'h42 : pixel<152 ? 16'h43 : 16'h20;
  if(code!==expected)$fatal(1,"subtitle prefetch alignment x=%d code=%h expected=%h",pixel,code,expected);
 end
end
$display("PASS SRT UTF8, CRLF, EOF without blank, cue gaps, pause and loop");$finish;
end
endmodule
