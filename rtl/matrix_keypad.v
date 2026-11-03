// Open-drain row scan: inactive rows float, columns require 3.3 V pullups.
// Reject chords/ghosts; one event per press, rearm only after full release.
module matrix_keypad #(parameter ROW_CYCLES=25000,DEBOUNCE_FRAMES=10)(
 input wire clk,reset_n,input wire[3:0] columns,output wire[3:0] rows,
 output reg pressed,output reg[3:0] code);
 localparam B=ROW_CYCLES<2 ? 1 : $clog2(ROW_CYCLES);
 localparam D=DEBOUNCE_FRAMES<2 ? 1 : $clog2(DEBOUNCE_FRAMES+1);
 reg[B-1:0] timer;reg[1:0] row;
 (* async_reg="true" *) reg[3:0] col_meta,col_sync;
 reg[15:0] frame,candidate;reg[D-1:0] debounce;reg armed;
 wire[15:0] sample={~col_sync,frame[11:0]};
 wire single_key=sample!=0 && (sample&(sample-1'b1))==0;
 genvar g;generate for(g=0;g<4;g=g+1)begin:drain
  assign rows[g]=row==g ? 1'b0 : 1'bz;
 end endgenerate
 integer i;
 always @(posedge clk or negedge reset_n)begin
  if(!reset_n)begin timer<=0;row<=0;col_meta<=15;col_sync<=15;frame<=0;candidate<=0;debounce<=0;armed<=1;pressed<=0;code<=0;end
  else begin
   col_meta<=columns;col_sync<=col_meta;pressed<=0;
   if(timer==ROW_CYCLES-1)begin
    timer<=0;row<=row+1'b1;
    frame[row*4+:4]<=~col_sync;
    if(row==3)begin
     if(sample!=candidate)begin candidate<=sample;debounce<=0;end
     else if(debounce<DEBOUNCE_FRAMES)debounce<=debounce+1'b1;
     else if(sample==0)armed<=1;
     else if(armed)begin
      armed<=0;
      if(single_key)begin
       pressed<=1;
       for(i=0;i<16;i=i+1)if(sample[i])code<=i;
      end
     end
    end
   end else timer<=timer+1'b1;
  end
 end
endmodule
