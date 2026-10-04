// Pixel-clock-domain PCM: exact average 48 kHz from the 25 MHz video clock.
// N=6144, CTS=25000: Fs = Fpixel*N/(128*CTS) = 48000 Hz.
module hdmi_test_audio (
 input wire clk, input wire rst,
 output reg sample_valid,
 output reg signed [23:0] left_sample,right_sample,
 output reg acr_valid, output wire [19:0] acr_n,acr_cts
);
 reg [24:0] sample_phase;
 wire [25:0] phase_sum={1'b0,sample_phase}+26'd48000;
 reg [5:0] tone_phase,acr_count;
 reg [15:0] gate_count;
 reg signed [23:0] tone_sample;
 assign acr_n=20'd6144;
 assign acr_cts=20'd25000;
 always @* begin
  case(tone_phase)
            6'd0: tone_sample = 24'sd0;
            6'd1: tone_sample = 24'sd68433;
            6'd2: tone_sample = 24'sd135696;
            6'd3: tone_sample = 24'sd200636;
            6'd4: tone_sample = 24'sd262144;
            6'd5: tone_sample = 24'sd319166;
            6'd6: tone_sample = 24'sd370728;
            6'd7: tone_sample = 24'sd415946;
            6'd8: tone_sample = 24'sd454047;
            6'd9: tone_sample = 24'sd484379;
            6'd10: tone_sample = 24'sd506423;
            6'd11: tone_sample = 24'sd519803;
            6'd12: tone_sample = 24'sd524288;
            6'd13: tone_sample = 24'sd519803;
            6'd14: tone_sample = 24'sd506423;
            6'd15: tone_sample = 24'sd484379;
            6'd16: tone_sample = 24'sd454047;
            6'd17: tone_sample = 24'sd415946;
            6'd18: tone_sample = 24'sd370728;
            6'd19: tone_sample = 24'sd319166;
            6'd20: tone_sample = 24'sd262144;
            6'd21: tone_sample = 24'sd200636;
            6'd22: tone_sample = 24'sd135696;
            6'd23: tone_sample = 24'sd68433;
            6'd24: tone_sample = 24'sd0;
            6'd25: tone_sample = -24'sd68433;
            6'd26: tone_sample = -24'sd135696;
            6'd27: tone_sample = -24'sd200636;
            6'd28: tone_sample = -24'sd262144;
            6'd29: tone_sample = -24'sd319166;
            6'd30: tone_sample = -24'sd370728;
            6'd31: tone_sample = -24'sd415946;
            6'd32: tone_sample = -24'sd454047;
            6'd33: tone_sample = -24'sd484379;
            6'd34: tone_sample = -24'sd506423;
            6'd35: tone_sample = -24'sd519803;
            6'd36: tone_sample = -24'sd524288;
            6'd37: tone_sample = -24'sd519803;
            6'd38: tone_sample = -24'sd506423;
            6'd39: tone_sample = -24'sd484379;
            6'd40: tone_sample = -24'sd454047;
            6'd41: tone_sample = -24'sd415946;
            6'd42: tone_sample = -24'sd370728;
            6'd43: tone_sample = -24'sd319166;
            6'd44: tone_sample = -24'sd262144;
            6'd45: tone_sample = -24'sd200636;
            6'd46: tone_sample = -24'sd135696;
            6'd47: tone_sample = -24'sd68433;
            default: tone_sample = 24'sd0;
  endcase
 end
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   sample_phase<=0;tone_phase<=0;acr_count<=0;gate_count<=0;
   sample_valid<=0;acr_valid<=0;left_sample<=0;right_sample<=0;
  end else begin
   sample_valid<=0;acr_valid<=0;
   if(phase_sum>=26'd25000000) begin
    sample_phase<=phase_sum-26'd25000000;
    sample_valid<=1;
    left_sample<=gate_count<16'd24000 ? tone_sample : 24'sd0;
    right_sample<=gate_count<16'd24000 ? tone_sample : 24'sd0;
    tone_phase<=tone_phase==47 ? 0 : tone_phase+1'b1;
    gate_count<=gate_count==47999 ? 0 : gate_count+1'b1;
    if(acr_count==47) begin acr_count<=0;acr_valid<=1;end
    else acr_count<=acr_count+1'b1;
   end else sample_phase<=phase_sum[24:0];
  end
 end
endmodule
