// Use Anlogic protocol/PHY IP; video framing and PCM/ACR are project logic.
module hdmi_audio_output (
 input wire pixel_clk,serial_clk,rst,vs,de,input wire [23:0] rgb,
 output wire clk_p,d0_p,d1_p,d2_p,
 output wire ddc_scl,inout wire ddc_sda
);
 wire valid,sof,last;wire [23:0] data;
 wire sample_valid,acr_valid;wire [23:0] left_sample,right_sample;
 wire [19:0] acr_n,acr_cts;
 wire [9:0] ch0,ch1,ch2,chclk;
 reg [21:0] edid_wait;
 reg edid_trigger;
 // Read EDID once, 100 ms after the video-domain reset releases.
 always @(posedge pixel_clk or posedge rst) begin
  if(rst)begin edid_wait<=0;edid_trigger<=0;end
  else begin
   edid_trigger<=edid_wait==22'd2499999;
   if(edid_wait<22'd2500000)edid_wait<=edid_wait+1'b1;
  end
 end
 hdmi_video_stream u_stream(.clk(pixel_clk),.rst(rst),.vs(vs),.de(de),.rgb(rgb),
  .valid(valid),.sof(sof),.last(last),.data(data));
 hdmi_test_audio u_pcm(.clk(pixel_clk),.rst(rst),.sample_valid(sample_valid),
  .left_sample(left_sample),.right_sample(right_sample),.acr_valid(acr_valid),
  .acr_n(acr_n),.acr_cts(acr_cts));
 hdmi_1_4b_transmitter_core_wrapper #(
  .DEVICE("EG"),.HTOTAL(800),.HSA(96),.HFP(16),.HBP(48),.HACTIVE(640),
  .VTOTAL(525),.VSA(2),.VFP(10),.VBP(33),.VACTIVE(480),
  .VIDEO_VIC(1),.VIDEO_TPG("Disable"),.VIDEO_FORMAT("RGB"),
  .AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(125)
 ) u_core(.I_pixel_clk(pixel_clk),.I_rst(rst),.I_edid_read_trig(edid_trigger),
  .O_edid_read_valid(),.O_edid_read_data(),.I_axis_s_user(sof),
  .I_axis_s_valid(valid),.I_axis_s_last(last),.I_axis_s_data(data),.O_axis_s_ready(),
  .I_audio_valid(sample_valid),.I_audio_left_data(left_sample),
  .I_audio_right_data(right_sample),.I_acr_valid(acr_valid),.I_acr_cts(acr_cts),
  .I_acr_n(acr_n),.O_video_locked(),.O_ddc_scl(ddc_scl),.IO_ddc_sda(ddc_sda),
  .O_ch0_tmds_data(ch0),.O_ch1_tmds_data(ch1),.O_ch2_tmds_data(ch2),
  .O_clk_tmds_data(chclk));
 hdmi_phy_wrapper #(.DEVICE("EG")) u_phy(
  .I_pixel_clk(pixel_clk),.I_serial_clk(serial_clk),.I_rst(rst),
  .I_tmds_channel_0(ch0),.I_tmds_channel_1(ch1),.I_tmds_channel_2(ch2),
  .I_tmds_channel_clk(chclk),.O_tmds_ch0_p(d0_p),.O_tmds_ch1_p(d1_p),
  .O_tmds_ch2_p(d2_p),.O_tmds_clk_p(clk_p));
endmodule
