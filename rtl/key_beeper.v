// Independent of KEY1 reset so its own press can produce a full short beep.
// All registers have FPGA power-up values. Board buzzer driver is active low.
module key_beeper #(
 parameter integer DEBOUNCE_CYCLES=1000000,
 parameter integer BEEP_CYCLES=3000000,
 parameter integer HALF_TONE_CYCLES=12500
)(input wire clk,input wire [3:0] keys_n,output reg buzzer_n=1);
 wire [3:0] pressed;
 genvar k;
 generate for(k=0;k<4;k=k+1)begin:buttons
  key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_key(clk,1'b1,keys_n[k],pressed[k]);
 end endgenerate
 reg [21:0] remaining=0;
 reg [13:0] tone_count=0;
 always @(posedge clk)begin
  if(|pressed)begin remaining<=BEEP_CYCLES;tone_count<=0;buzzer_n<=0;end
  else if(remaining!=0)begin
   remaining<=remaining-1'b1;
   if(remaining==1)begin buzzer_n<=1;tone_count<=0;end
   else if(tone_count==HALF_TONE_CYCLES-1)begin tone_count<=0;buzzer_n<=~buzzer_n;end
   else tone_count<=tone_count+1'b1;
  end else begin buzzer_n<=1;tone_count<=0;end
 end
endmodule
