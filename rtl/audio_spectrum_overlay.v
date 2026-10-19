// Transparent eight-band spectrum bars over the top-right of video playback.
module audio_spectrum_overlay (
    input wire clk, rst_n,
    input wire [9:0] x, y,
    input wire de, visible,
    input wire [47:0] levels,
    output reg active,
    output reg [23:0] rgb
);
    reg pixel_active;
    reg [23:0] pixel_color;
    reg [2:0] index;
    reg [9:0] local_x;
    reg [5:0] height;
    reg [9:0] bar_top;
    always @* begin
        index=0;local_x=0;height=0;bar_top=0;
        pixel_active=0;pixel_color=24'h000000;
        if(de && visible && x>=420 && x<622 && y>=54 && y<=132)begin
            if(y==130)begin pixel_active=1;pixel_color=24'h40515e;end
            if(x>=425 && x<618 && y>=58 && y<130)begin
                index=(x-425)/25;
                local_x=(x-425)%25;
                height=levels[index*6 +: 6];
                bar_top=10'd129-height;
                if(local_x<18 && height!=0 && y>=bar_top && y<129)begin
                    pixel_active=1;
                    case(index)
                        0:pixel_color=(y==bar_top) ? 24'hb4ffe0 : 24'h32df9d;
                        1:pixel_color=(y==bar_top) ? 24'hb0fff3 : 24'h24d8c4;
                        2:pixel_color=(y==bar_top) ? 24'hb8efff : 24'h32bde8;
                        3:pixel_color=(y==bar_top) ? 24'hd5e2ff : 24'h568cff;
                        4:pixel_color=(y==bar_top) ? 24'he6ddff : 24'h9474f2;
                        5:pixel_color=(y==bar_top) ? 24'hffd9fa : 24'hd85ed0;
                        6:pixel_color=(y==bar_top) ? 24'hffe0eb : 24'he65b91;
                        default:pixel_color=(y==bar_top) ? 24'hfff0cc : 24'he9ae4d;
                    endcase
                end else if(local_x==18 && height!=0 && y>=bar_top && y<129)begin
                    pixel_active=1;pixel_color=24'h101820;
                end
            end
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin active<=0;rgb<=0;end
        else begin active<=pixel_active;rgb<=pixel_color;end
    end
endmodule
