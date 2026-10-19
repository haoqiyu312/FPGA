// Standalone frontend ready for future connection to the shared player.
// Does not use INT/RESET; poll the panel's retained power-on configuration.
module touch_player_frontend (
    input wire clk,reset_n,menu_visible,video_mode,
    inout wire touch_scl,touch_sda,
    output wire online,fault,
    output wire action_valid,
    output wire [2:0] action,pressed_button,
    output wire [9:0] touch_x,touch_y,
    output wire report_valid,report_down,report_multiple
);
    wire sample_valid,down,multi,in_range;
    wire[9:0] mapped_x,mapped_y;
    reg[9:0] sampled_x,sampled_y;
    reg sampled_valid,sampled_down,sampled_multi,sampled_range;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            sampled_x<=0;sampled_y<=0;sampled_valid<=0;
            sampled_down<=0;sampled_multi<=0;sampled_range<=0;
        end else begin
            sampled_x<=mapped_x;sampled_y<=mapped_y;sampled_valid<=sample_valid;
            sampled_down<=down;sampled_multi<=multi;sampled_range<=in_range;
        end
    end
    assign touch_x=sampled_x;assign touch_y=sampled_y;
    assign report_valid=sampled_valid;assign report_down=sampled_down;
    assign report_multiple=sampled_multi | (sampled_down & ~sampled_range);
    wire [15:0] raw_x,raw_y;
    wire [6:0] active_address;
    wire scl_low,sda_low;
    // Tristates belong at the physical top level, never inside the protocol.
    assign touch_scl=scl_low ? 1'b0 : 1'bz;
    assign touch_sda=sda_low ? 1'b0 : 1'bz;
    gt911_touch_reader u_reader (.clk(clk),.reset_n(reset_n),
        .scl_in(touch_scl),.sda_in(touch_sda),.scl_drive_low(scl_low),.sda_drive_low(sda_low),
        .online(online),.fault(fault),
        .sample_valid(sample_valid),.contact_down(down),.multiple_contacts(multi),
        .raw_x(raw_x),.raw_y(raw_y),.active_address(active_address));
    touch_coordinate_map u_map (.raw_x(raw_x),.raw_y(raw_y),.in_range(in_range),
        .display_x(mapped_x),.display_y(mapped_y));
    touch_menu_control u_menu (.clk(clk),.reset_n(reset_n),
        .menu_visible(menu_visible & online),.sample_valid(sampled_valid),
        .contact_down(sampled_down),.multiple_contacts(sampled_multi | (sampled_down & ~sampled_range)),
        .touch_x(touch_x),.touch_y(touch_y),.video_mode(video_mode),
        .action_valid(action_valid),.action(action),.pressed_button(pressed_button));
endmodule
