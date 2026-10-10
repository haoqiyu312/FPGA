// KEY4: short release emits one action; a long hold toggles mode once.
// Controller survives media resets so a held key cannot toggle repeatedly.
module media_key_control #(
    parameter integer DEBOUNCE_CYCLES=1000000,
    parameter integer LONG_CYCLES=100000000,
    parameter integer RESET_CYCLES=64
)(input wire clk,reset_n,key_auto_n,restart_n,
  output reg video_mode=0, output reg short_press=0,
  output wire media_reset_n);
    localparam DB_BITS=DEBOUNCE_CYCLES<2 ? 1 : $clog2(DEBOUNCE_CYCLES);
    localparam HOLD_BITS=LONG_CYCLES<2 ? 1 : $clog2(LONG_CYCLES);
    localparam RESET_BITS=RESET_CYCLES<2 ? 1 : $clog2(RESET_CYCLES+1);
    reg [1:0] sync_key=3;
    reg stable=1,held_long=0;
    reg [DB_BITS-1:0] debounce=0;
    reg [HOLD_BITS-1:0] hold_count=0;
    reg [RESET_BITS-1:0] reset_count=0;
    wire restart_press;
    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_restart
        (.clk(clk),.reset_n(reset_n),.key_n(restart_n),.pressed(restart_press));
    assign media_reset_n=reset_n && reset_count==0;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            sync_key<=3;stable<=1;held_long<=0;debounce<=0;
            hold_count<=0;reset_count<=0;video_mode<=0;short_press<=0;
        end else begin
            sync_key<={sync_key[0],key_auto_n};short_press<=0;
            if(reset_count!=0)reset_count<=reset_count-1'b1;
            if(video_mode && restart_press)reset_count<=RESET_CYCLES;
            if(sync_key[1]==stable)debounce<=0;
            else if(debounce==DEBOUNCE_CYCLES-1) begin
                debounce<=0;stable<=sync_key[1];
                if(sync_key[1])begin
                    if(!held_long)short_press<=1;
                    hold_count<=0;held_long<=0;
                end
            end else debounce<=debounce+1'b1;
            if(!stable && !held_long &&
               !(sync_key[1] && debounce==DEBOUNCE_CYCLES-1))begin
                if(hold_count==LONG_CYCLES-1)begin
                    video_mode<=~video_mode;reset_count<=RESET_CYCLES;
                    held_long<=1;hold_count<=0;
                end else hold_count<=hold_count+1'b1;
            end
        end
    end
endmodule
