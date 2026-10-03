`timescale 1ns/1ps
module tb_loader_timeout;
reg clk=0;always #5 clk=~clk;reg rst=1;
wire req,wrreq,pvalid,ready,cv;wire[31:0]lba,pdata;wire[3:0]status;wire[5:0]total;
fat32_bmp_loader #(.AUTO_SCAN(1),.WATCHDOG_BITS(8))dut(
.clk(clk),.rst(rst),.sd_ready(1'b0),.memory_ready(1'b1),.sector_req(req),.sector_lba(lba),
.sector_byte(8'd0),.sector_valid(1'b0),.sector_end(1'b0),.write_req(wrreq),.write_ack(1'b0),
.pixel_valid(pvalid),.pixel_data(pdata),.write_finish_toggle(1'b0),.image_ready(ready),.status(status),
.image_index(5'd0),.image_total(total),.catalog_valid(cv));
initial begin
 #40;rst=0;wait(status>=10);#20;
 if(status!=14 || ready || req || wrreq || pvalid || total!=0)$fatal(1,"initialization timeout handling");
 $display("PASS missing/uninitialized card reports error 14 without sector/pixel writes");$finish;
end
initial begin #10000;$fatal(1,"timeout missing card never reported");end
endmodule
