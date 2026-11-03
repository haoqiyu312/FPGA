`timescale 1ns/1ps
// Primitive behavior for comparing the unchanged old/new serializers.
module EG_LOGIC_ODDR(input wire clk,rst,d0,d1,output reg q);
 always @(posedge clk or negedge clk or posedge rst)if(rst)q<=0;else q<=clk ? d1 : d0;
endmodule
module tb_oled_serial_reset;
 reg pixel=0,serial=0,rst=1;
 always #10 pixel=~pixel;always #2 serial=~serial;
 wire new_lane,old_lane;
 hdmi_audio_oled_output #(.PIXEL_HZ(48000000)) dut(.pixel_clk(pixel),.serial_clk(serial),.rst(rst),
  .vs(1'b0),.de(1'b0),.rgb(24'd0),.d0_p(new_lane),.pcm_left(24'd0),.pcm_right(24'd0));
 // The PHY reverses the ten-bit TMDS word before passing it to the lane.
 localparam[9:0] DATA=10'h295;
 wire[9:0] reversed={DATA[0],DATA[1],DATA[2],DATA[3],DATA[4],DATA[5],DATA[6],DATA[7],DATA[8],DATA[9]};
 lane_lvds_10_1 #(.DEVICE("EG")) ref_lane(.I_pixel_clk(pixel),.I_serial_clk(serial),.I_rst(rst),.I_data_in(reversed),.O_serial_out(old_lane));
 integer trial,k;
 initial begin
  force dut.ch0=DATA;
  #11;
  for(trial=0;trial<4;trial=trial+1)begin
   rst=1;#1;
   if(dut.serial_reset_pipe!==3'b111)$fatal(1,"serial reset must assert asynchronously");
   #19;rst=0;
   repeat(2)begin @(posedge serial);#0.1;if(!dut.serial_reset_pipe[2])$fatal(1,"serial reset released too early");end
   @(posedge serial);#0.1;if(dut.serial_reset_pipe[2])$fatal(1,"serial reset did not release on third edge");
   repeat(30)@(posedge serial);
   for(k=0;k<100;k=k+1)begin
    @(serial);#0.1;if(new_lane!==old_lane)$fatal(1,"TMDS ordering/serializer differs after reset");
   end
   #1;
  end
  $display("PASS asynchronous assertion, three-serial-clock release, repeated resets and unchanged TMDS bitstream");$finish;
 end
endmodule
