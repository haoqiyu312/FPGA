// RVF2: two 16 KiB banks of 48 kHz mono mu-law samples. The video reader
// publishes a bank only after both picture and audio are complete. The
// presenter returns the old bank only after its audio has finished.
module video_audio_buffer (
    input wire write_clk,write_valid,write_bank,
    input wire [13:0] write_address,input wire [7:0] write_data,
    input wire clk,rst,enabled,paused,start,read_bank,sample_tick,
    input wire [7:0] fps,
    output reg busy,output wire [23:0] pcm_sample
);
    reg [7:0] samples [0:32767];
    reg [14:0] read_address;
    reg [7:0] sample_byte;
    reg [14:0] remaining;
    reg [1:0] guard;
    reg [14:0] samples_per_frame;
    always @* case(fps)
        3:samples_per_frame=16000;
        4:samples_per_frame=12000;
        5:samples_per_frame=9600;
        default:samples_per_frame=0;
    endcase
    // No reset on the RAM or read register: infer true dual-clock block RAM.
    always @(posedge write_clk)
        if(write_valid)samples[{write_bank,write_address}]<=write_data;
    always @(posedge clk)sample_byte<=samples[read_address];
    wire [7:0] code=~sample_byte;
    wire [15:0] magnitude=((16'd132+{9'd0,code[3:0],3'b0})<<code[6:4])-16'd132;
    wire [15:0] linear_sample=code[7] ? (~magnitude+16'd1) : magnitude;
    assign pcm_sample=busy && guard==0 && enabled && !paused ? {linear_sample,8'd0} : 24'd0;
    always @(posedge clk or posedge rst)begin
        if(rst)begin busy<=0;read_address<=0;remaining<=0;guard<=0;end
        else if(!enabled)begin busy<=0;remaining<=0;guard<=0;end
        else if(start)begin
            read_address<={read_bank,14'd0};remaining<=samples_per_frame;
            busy<=samples_per_frame!=0;guard<=2;
        end else begin
            if(guard!=0)guard<=guard-1'b1;
            if(busy && guard==0 && !paused && sample_tick)begin
                if(remaining==1)begin remaining<=0;busy<=0;end
                else begin remaining<=remaining-1'b1;read_address<=read_address+1'b1;end
            end
        end
    end
endmodule
