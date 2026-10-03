`timescale 1ns/1ps
module tb_image_number;
reg clk=0;always #10 clk=~clk;
reg rst=1;reg[4:0]index=0;reg[5:0]total=0;
wire[7:0]seg,en;wire[7:0]active=~en;
image_number_display #(.SLOT_CYCLES(12),.BLANK_CYCLES(4)) dut(clk,rst,index,total,seg,en);
reg[7:0]expected,seen=0;integer number=0,amount=0;
function[7:0] numeral;
 input integer n;
 begin case(n)0:numeral=8'hc0;1:numeral=8'hf9;2:numeral=8'ha4;3:numeral=8'hb0;
 4:numeral=8'h99;5:numeral=8'h92;6:numeral=8'h82;7:numeral=8'hf8;8:numeral=8'h80;9:numeral=8'h90;
 default:numeral=8'hff;endcase end
endfunction
always @(negedge clk)if(rst && active!=0)begin
 if((active&(active-1))!=0)$fatal(1,"multiple digits enabled");
 case(active)
 1:expected=numeral(dut.image_latched/10);2:expected=numeral(dut.image_latched%10);
 8:expected=8'hc0;16:expected=8'h8e;
 64:expected=numeral(dut.total_latched/10);128:expected=numeral(dut.total_latched%10);
 default:expected=255;
 endcase
 if(seg!==expected || !seg[7])$fatal(1,"bad displayed glyph/DP active=%h seg=%h expected=%h digit=%d image=%d total=%d symbol=%d",active,seg,expected,dut.digit,dut.image_latched,dut.total_latched,dut.symbol);
 seen=seen|active;
end
task check(input[4:0]idx,input[5:0]size);
 begin index=idx;total=size;seen=0;repeat(220)@(posedge clk);#1;
 if(seen!=255 || dut.image_latched!=(size==0?0:idx+1) || dut.total_latched!=size)$fatal(1,"bad full scan");end
endtask
initial begin
 #1;rst=0;#10;rst=1;
 check(0,0);check(0,1);check(3,4);check(9,10);check(31,32);
 rst=0;#1;if(en!=255 || seg!=255)$fatal(1,"reset not blank");
 $display("PASS low-active PNP scan 00 OF 00 / 01 OF 01 / 04 OF 04 / 10 OF 10 / 32 OF 32");$finish;
end
endmodule
