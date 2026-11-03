`timescale 1ns/1ps
module tb_palette_delay;
 reg clk=0;always #5 clk=~clk;
 reg rst=1;reg[4:0] code=31;
 wire[23:0] spectrum_input,browser_input,spectrum_decode,browser_decode;
 audio_spectrum_palette sp0(code,spectrum_input),sp1(spectrum_codes[18],spectrum_decode);
 file_browser_palette bp0(code,browser_input),bp1(browser_codes[16],browser_decode);
 reg[23:0] spectrum_original[0:19],browser_original[0:17];
 reg[4:0] spectrum_codes[0:18],browser_codes[0:16];
 reg[23:0] spectrum_output,browser_output;
 integer i,cycle;
 always @(posedge clk)begin
  if(rst)begin
   for(i=0;i<20;i=i+1)spectrum_original[i]<=0;
   for(i=0;i<18;i=i+1)browser_original[i]<=0;
   for(i=0;i<19;i=i+1)spectrum_codes[i]<=0;
   for(i=0;i<17;i=i+1)browser_codes[i]<=0;
   spectrum_output<=0;browser_output<=0;
  end else begin
   spectrum_original[0]<=spectrum_input;browser_original[0]<=browser_input;
   spectrum_codes[0]<=code;browser_codes[0]<=code;
   for(i=1;i<20;i=i+1)spectrum_original[i]<=spectrum_original[i-1];
   for(i=1;i<18;i=i+1)browser_original[i]<=browser_original[i-1];
   for(i=1;i<19;i=i+1)spectrum_codes[i]<=spectrum_codes[i-1];
   for(i=1;i<17;i=i+1)browser_codes[i]<=browser_codes[i-1];
   spectrum_output<=spectrum_decode;browser_output<=browser_decode;
  end
 end
 initial begin
  repeat(3)@(negedge clk);rst=0;code=0;
  for(cycle=0;cycle<256;cycle=cycle+1)begin
   @(negedge clk);code=cycle%32;
   @(posedge clk);#1;
   if(spectrum_output!==spectrum_original[19] || browser_output!==browser_original[17])$fatal(1,"palette latency cycle=%d s=%h ref=%h b=%h ref=%h",cycle,spectrum_output,spectrum_original[19],browser_output,browser_original[17]);
  end
  $display("PASS registered palette preserves spectrum 20-clock and browser 18-clock RGB latency");$finish;
 end
endmodule
