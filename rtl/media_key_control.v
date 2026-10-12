// KEY4: short release emits one action; a one-second hold toggles mode once.
// Optional KEY4+KEY2 chord toggles once, then waits for both keys to release.
// Controller survives media resets so a held key cannot toggle repeatedly.
module media_key_control #(
    parameter integer DEBOUNCE_CYCLES=1000000,
    parameter integer LONG_CYCLES=50000000,
    parameter integer RESET_CYCLES=64,
    parameter integer EXTERNAL_ACTIONS=0,
    parameter integer CHORD_MODE=0
)(input wire clk,reset_n,key_auto_n,restart_n,
  output reg video_mode=0, output reg short_press=0,
  output wire media_reset_n,
  input wire mode_event,restart_event);
    localparam DB_BITS=DEBOUNCE_CYCLES<2 ? 1 : $clog2(DEBOUNCE_CYCLES);
    localparam HOLD_BITS=LONG_CYCLES<2 ? 1 : $clog2(LONG_CYCLES);
    localparam RESET_BITS=RESET_CYCLES<2 ? 1 : $clog2(RESET_CYCLES+1);
    reg [1:0] sync_key=3;
    reg [1:0] sync_restart=3;
    reg chord_latched=0;
    reg [DB_BITS-1:0] chord_count=0;
    wire chord_down=!sync_key[1] && !sync_restart[1];
    wire chord_up=sync_key[1] && sync_restart[1];
    wire chord_trigger=CHORD_MODE && !chord_latched && !held_long && chord_down &&
                       chord_count==DEBOUNCE_CYCLES-1;
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
            sync_key<=3;sync_restart<=3;chord_latched<=0;chord_count<=0;
            stable<=1;held_long<=0;debounce<=0;
            hold_count<=0;reset_count<=0;video_mode<=0;short_press<=0;
        end else begin
            sync_key<={sync_key[0],key_auto_n};short_press<=0;
            sync_restart<={sync_restart[0],restart_n};
            // Debounce the complete chord, including release of both keys.
            if(CHORD_MODE && (chord_latched ? chord_up : chord_down))begin
                if(chord_count==DEBOUNCE_CYCLES-1)begin
                    chord_latched<=~chord_latched;chord_count<=0;
                end else chord_count<=chord_count+1'b1;
            end else chord_count<=0;
            if(reset_count!=0)reset_count<=reset_count-1'b1;
            if(video_mode && ((restart_press && (!CHORD_MODE || (sync_key[1] && !chord_latched))) ||
               (EXTERNAL_ACTIONS && restart_event)))reset_count<=RESET_CYCLES;
            if(sync_key[1]==stable)debounce<=0;
            else if(debounce==DEBOUNCE_CYCLES-1) begin
                debounce<=0;stable<=sync_key[1];
                if(sync_key[1])begin
                    if(!held_long && !chord_latched && !chord_trigger)short_press<=1;
                    hold_count<=0;held_long<=0;
                end
            end else debounce<=debounce+1'b1;
            if(!stable && !held_long && !chord_latched && !chord_trigger &&
               !(sync_key[1] && debounce==DEBOUNCE_CYCLES-1))begin
                if(hold_count==LONG_CYCLES-1)begin
                    video_mode<=~video_mode;reset_count<=RESET_CYCLES;
                    held_long<=1;hold_count<=0;
                end else hold_count<=hold_count+1'b1;
            end
            if(chord_trigger)begin
                video_mode<=~video_mode;reset_count<=RESET_CYCLES;
                held_long<=1;hold_count<=0;short_press<=0;
            end
            // Touch mode switch has priority over a simultaneous physical key.
            if(EXTERNAL_ACTIONS && mode_event && reset_count==0)begin
                video_mode<=~video_mode;reset_count<=RESET_CYCLES;short_press<=0;
                if(!stable)begin held_long<=1;hold_count<=0;end
            end
        end
    end
endmodule
