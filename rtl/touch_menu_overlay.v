// Combinational RGB888 overlay; caller must align x/y and rgb_in.
// Do not connect asynchronous system-clock pressed_button directly here:
// the future top-level integration must transfer UI state to pixel_clk.
module touch_menu_overlay #(parameter integer SHOW_STATUS=0)(
    input wire [9:0] x,y,
    input wire de, menu_visible, video_mode, playing,
    input wire [2:0] pressed_button,
    input wire touch_online,
    input wire [3:0] volume_level,
    input wire [23:0] rgb_in,
    output reg [23:0] rgb_out
);
    wire [2:0] button;
    touch_menu_hit u_hit (.x(x),.y(y),.button(button));
    integer cx,dx,dy;
    reg ink,disabled;
    always @* begin
        rgb_out=rgb_in;ink=0;disabled=0;cx=0;dx=0;dy=0;
        if(de && menu_visible && x<640 && y>=400 && y<480) begin
            rgb_out=24'h101820;
            if(SHOW_STATUS && y<404)rgb_out=touch_online ? 24'h208060 : 24'hA05020;
            if(SHOW_STATUS && y>=476 && x>=8 && x<632)
                rgb_out=x<8+volume_level*78 ? 24'h3098C0 : 24'h202830;
            if(button!=0) begin
                cx=48+(button-1)*88;dx=$signed({1'b0,x})-cx;dy=$signed({1'b0,y})-440;
                disabled=((button==3 || button==4) && video_mode) || (button==5 && !video_mode);
                rgb_out=disabled ? 24'h202830 :
                    (pressed_button==button ? 24'h1688B0 : 24'h304858);
                case(button)
                    1: ink=(dx>=-18 && dx<=-3 && dy>=-14 && dy<=14) ||
                           (dx>=3 && dx<=18 && dy>=-14 && dy<=14);
                    2: if(playing) ink=(dy>=-16 && dy<=16) &&
                           ((dx>=-12 && dx<=-5) || (dx>=5 && dx<=12));
                       else ink=dx>=-12 && dx<=16 && dy<=((16-dx)/2) && dy>=-((16-dx)/2);
                    3: ink=(dx>=-16 && dx<=10 && dy<=((dx+16)/2) && dy>=-((dx+16)/2)) ||
                           (dx>=-20 && dx<=-17 && dy>=-16 && dy<=16);
                    4: ink=(dx>=-10 && dx<=16 && dy<=((16-dx)/2) && dy>=-((16-dx)/2)) ||
                           (dx>=17 && dx<=20 && dy>=-16 && dy<=16);
                    5: ink=(dx>=-16 && dx<=10 && dy<=((dx+16)/2) && dy>=-((dx+16)/2)) ||
                           (dx>=-20 && dx<=-17 && dy>=-16 && dy<=16);
                    6: ink=dx>=-16 && dx<=16 && dy>=-3 && dy<=3;
                    7: ink=(dx>=-16 && dx<=16 && dy>=-3 && dy<=3) ||
                           (dx>=-3 && dx<=3 && dy>=-16 && dy<=16);
                    default: ink=0;
                endcase
                if(ink)rgb_out=disabled ? 24'h606870 : 24'hFFFFFF;
            end
        end
    end
endmodule
