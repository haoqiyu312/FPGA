// HX4S20C: common-anode segments (active low), PNP digit selects active low.
// Eight positions, left to right: "01 OF 32". No valid images: "00 OF 00".
module image_number_display #(
 parameter integer SLOT_CYCLES=50000,
 parameter integer BLANK_CYCLES=100
)(input wire clk,reset_n,input wire [4:0] image_index,
 input wire [5:0] total_count,
 output reg [7:0] seg_n=8'hff,output reg [7:0] digit_en=8'hff);
 reg [15:0] count=0;
 reg [2:0] digit=0;
 reg [5:0] image_latched=0,total_latched=0;
 wire [3:0] symbol=pick_symbol(digit,image_latched,total_latched);
 function [7:0] encode;
  input [3:0] value;
  begin case(value)
   0:encode=8'hc0;1:encode=8'hf9;2:encode=8'ha4;
   3:encode=8'hb0;4:encode=8'h99;5:encode=8'h92;
   6:encode=8'h82;7:encode=8'hf8;8:encode=8'h80;9:encode=8'h90;
   10:encode=8'hc0; // O
   11:encode=8'h8e; // F
   default:encode=8'hff;
  endcase end
 endfunction
 function [3:0] pick_symbol;
  input [2:0] position;
  input [5:0] image_number,total_number;
  begin case(position)
   0:pick_symbol=image_number/10;
   1:pick_symbol=image_number%10;
   3:pick_symbol=10;
   4:pick_symbol=11;
   6:pick_symbol=total_number/10;
   7:pick_symbol=total_number%10;
   default:pick_symbol=15;
  endcase end
 endfunction
 always @(posedge clk or negedge reset_n) begin
  if(!reset_n) begin count<=0;digit<=0;seg_n<=8'hff;digit_en<=8'hff;image_latched<=0;total_latched<=0;end
  else begin
   if(count==SLOT_CYCLES-1) begin count<=0;digit<=digit+1'b1;end
   else count<=count+1'b1;
   if(count==0)begin
    digit_en<=8'hff;
    if(digit==0)begin image_latched<=total_count==0 ? 6'd0 : {1'b0,image_index}+1'b1;total_latched<=total_count;end
   end
   // Break before make: disable old digit, change segments, enable next digit.
   if(count==BLANK_CYCLES/2)seg_n<=encode(symbol);
   if(count==BLANK_CYCLES)digit_en<=~(8'b1<<digit);
  end
 end
endmodule
