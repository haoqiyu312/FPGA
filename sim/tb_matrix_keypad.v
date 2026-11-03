`timescale 1ns/1ps
module tb_matrix_keypad;
 reg clk=0;always #5 clk=~clk;reg reset_n=0;tri1[3:0] rows,columns;
 reg[15:0] held=0;reg[3:0] low_columns;integer r,c;
 always @*begin
  low_columns=0;
  for(r=0;r<4;r=r+1)for(c=0;c<4;c=c+1)if(rows[r]===1'b0 && held[r*4+c])low_columns[c]=1;
 end
 genvar g;generate for(g=0;g<4;g=g+1)assign columns[g]=low_columns[g] ? 1'b0 : 1'bz;endgenerate
 wire pressed;wire[3:0] code;
 matrix_keypad #(.ROW_CYCLES(8),.DEBOUNCE_FRAMES(2)) dut(clk,reset_n,columns,rows,pressed,code);
 integer events=0,expected=-1,k;
 always @(posedge clk)if(pressed)begin
  if(code!==expected[3:0])$fatal(1,"wrong key got=%d want=%d",code,expected);
  events=events+1;
 end
 task wait_frames;begin repeat(200)@(negedge clk);end endtask
 initial begin
  repeat(4)@(negedge clk);reset_n=1;
  // Short pulses cannot survive a full debounced scan.
  held=1;repeat(3)@(negedge clk);held=0;wait_frames;
  if(events!=0)$fatal(1,"bounce event");
  for(k=0;k<16;k=k+1)begin
   expected=k;held=16'b1<<k;wait_frames;wait_frames;
   if(events!=k+1)$fatal(1,"missing/repeated held key %d",k);
   held=0;wait_frames;
  end
  held=16'h0033;wait_frames;if(events!=16)$fatal(1,"chord accepted");
  held=1;wait_frames;if(events!=16)$fatal(1,"rollover accepted before release");
  held=0;wait_frames;expected=15;held=16'h8000;wait_frames;
  if(events!=17)$fatal(1,"failed to rearm");
  $display("PASS all 16 matrix positions, bounce, held key, ghost/chord rejection and release rearm");$finish;
 end
endmodule
