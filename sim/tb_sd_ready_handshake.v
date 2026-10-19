`timescale 1ns/1ps
module tb_sd_ready_handshake;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,cmd_ack=0,cmd_error=0,read_req=0;
 wire ready,cmd_req,read_valid,read_end;
 wire[47:0] cmd;
 wire[7:0] cmd_r1,read_data;
 wire[15:0] cmd_data_len,spi_div;
 wire[31:0] read_addr;
 sd_card_sec_read_write dut(
  .clk(clk),.rst(rst),.sd_init_done(ready),
  .sd_sec_read(read_req),.sd_sec_read_addr(32'd123),
  .sd_sec_read_data(read_data),.sd_sec_read_data_valid(read_valid),.sd_sec_read_end(read_end),
  .sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),
  .sd_sec_write_data_req(),.sd_sec_write_end(),.spi_clk_div(spi_div),
  .cmd_req(cmd_req),.cmd_req_ack(cmd_ack),.cmd_req_error(cmd_error),
  .cmd(cmd),.cmd_r1(cmd_r1),.cmd_data_len(cmd_data_len),
  .block_read_req(),.block_read_valid(1'b0),.block_read_data(8'd0),.block_read_req_ack(1'b0),
  .block_write_req(),.block_write_data(),.block_write_data_rd(1'b0),.block_write_req_ack(1'b0)
 );
 task finish_command(input[7:0] number);
  integer cycles;
  begin
   cycles=0;
   while(!(cmd_req && cmd[47:40]==number) && cycles<100)begin
    @(negedge clk);cycles=cycles+1;
   end
   if(cycles==100)$fatal(1,"CMD%0d was not requested",number);
   cmd_ack=1;
   @(negedge clk);cmd_ack=0;
  end
 endtask
 initial begin
  repeat(3)@(negedge clk);rst=0;
  finish_command(0);
  finish_command(8);
  finish_command(55);
  finish_command(41);
  if(ready || dut.state!=18)$fatal(1,"CMD41 advertised ready before CMD16: ready=%b state=%0d",ready,dut.state);
  repeat(30)@(negedge clk);
  if(ready)$fatal(1,"readiness must stay low while CMD16 is pending");
  finish_command(16);
  if(!ready || dut.state!=17)$fatal(1,"CMD16 completion did not enable reads");
  read_req=1;
  @(negedge clk);read_req=0;
  if(dut.state!=5 || dut.sec_addr!=123)$fatal(1,"first sector request was lost");
  $display("PASS SD ready stays low until CMD16 completes; first read request accepted");
  $finish;
 end
 initial begin #10000;$fatal(1,"SD handshake timeout state=%0d",dut.state);end
endmodule
