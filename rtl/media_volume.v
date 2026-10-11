// Eight attenuation steps plus mute. Level 8 is bit-exact unity gain.
// Level 7 is /2, level 6 /4 ... level 1 /128. Signed shift preserves polarity.
module media_volume_control (
    input wire clk,reset_n,up_event,down_event,
    output reg [3:0] level
);
    always @(posedge clk or negedge reset_n)
        if(!reset_n)level<=8;
        else if(up_event && !down_event && level<8)level<=level+1'b1;
        else if(down_event && !up_event && level>0)level<=level-1'b1;
endmodule
module media_volume_apply (
    input wire [23:0] pcm_in,
    input wire [3:0] level,
    output wire [23:0] pcm_out
);
    wire signed [23:0] sample_value=pcm_in;
    wire [3:0] shift=level>=8 ? 4'd0 : 4'd8-level;
    wire signed [23:0] attenuated=sample_value >>> shift;
    assign pcm_out=level==0 ? 24'd0 : attenuated;
endmodule
