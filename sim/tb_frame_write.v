`timescale 1ns/1ps
module tb_frame_write;
parameter integer BURST=128;
reg clk=0; always #12.5 clk=~clk;
reg rst=1,req=0;
wire ack,finish,en,busy,clear;
wire [20:0] addr;
integer n=0,in_burst=0,expected,previous=-1,bursts=0;
frame_fifo_write #(.BURST_SIZE(BURST),.WRITE_V_FLIP(1),.FRAME_WIDTH(640),.FRAME_HEIGHT(480)) dut(
.rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
.App_rd_busy(1'b0),.O_wr_busy(busy),.App_wr_en(en),.App_wr_addr(addr),
.write_req(req),.write_req_ack(ack),.write_finish(finish),
.write_addr_0(21'd0),.write_addr_1(21'd0),.write_addr_2(21'd0),.write_addr_3(21'd0),
.write_addr_index(2'd0),.write_len(21'd307200),.fifo_aclr(clear),.rdusedw(10'd384));
always @(posedge clk) if(!rst) begin
 if(en) begin
  expected=(479-n/640)*640+n%640;
  if(addr!==expected) $fatal(1,"pixel %0d address %0d expected %0d",n,addr,expected);
  if(in_burst!=0 && addr!=previous+1) $fatal(1,"non-contiguous write inside burst: pixel %0d (%0d -> %0d)",n,previous,addr);
  previous=addr;in_burst=in_burst+1;n=n+1;
 end else if(in_burst!=0) begin
  if(in_burst!=BURST) $fatal(1,"short burst %0d",in_burst);
  bursts=bursts+1;in_burst=0;
 end
 if(finish) begin
  if(n!=307200) $fatal(1,"count %0d",n);
  $display("PASS all %0d addresses; %0d bursts; no address jump inside a burst",n,bursts);$finish;
 end
end
initial begin #101;rst=0;#100;req=1;wait(ack);@(negedge clk);req=0;end
initial begin #20000000;$fatal(1,"timeout");end
endmodule
