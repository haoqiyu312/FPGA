// External SRT captions for video and a temporary zoom notice for images.
// Caption text is read from the SRT cache; the font ROM is shared with the UI.
module media_subtitles #(
    parameter integer WIDTH=720,HEIGHT=720,FONT_LATENCY=1,ZOOM_NOTICE_FRAMES=120
)(
    input wire clk,rst_n,frame_start,shown,video_mode,enabled,
    input wire [1:0] zoom,
    input wire [9:0] x,y,
    input wire de,
    output wire font_request,
    output wire [15:0] font_codepoint,
    output wire [3:0] font_row,
    input wire [15:0] font_pixels,
    output wire panel,output wire ink,
    input wire [15:0] external_codepoint,
    input wire external_visible
);
    reg [1:0] display_zoom;
    reg display_enabled,display_video;
    reg [7:0] zoom_notice_count;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            display_zoom<=0;
            display_enabled<=0;
            display_video<=0;
            zoom_notice_count<=0;
        end else if(frame_start) begin
            display_zoom<=zoom;
            display_enabled<=enabled && shown;
            display_video<=video_mode;
            if(video_mode || !shown) zoom_notice_count<=0;
            else if(zoom!=display_zoom) zoom_notice_count<=ZOOM_NOTICE_FRAMES;
            else if(zoom_notice_count!=0) zoom_notice_count<=zoom_notice_count-1'b1;
        end
    end

    function [15:0] image_caption_char;
        input [1:0] scale;
        input [4:0] index;
        begin
            image_caption_char=16'h0020;
            case(scale)
                0: case(index)
                    0:image_caption_char=16'h56fe; 1:image_caption_char=16'h7247;
                    2:image_caption_char=16'h7f29; 3:image_caption_char=16'h653e;
                    4:image_caption_char=16'hff1a; 5:image_caption_char=16'h0031;
                    6:image_caption_char=16'h0030; 7:image_caption_char=16'h0030;
                    8:image_caption_char=16'h0025; 9:image_caption_char=16'h0020;
                    10:image_caption_char=16'h539f; 11:image_caption_char=16'h59cb;
                    12:image_caption_char=16'h753b; 13:image_caption_char=16'h9762;
                    default:begin end
                endcase
                1: case(index)
                    0:image_caption_char=16'h56fe; 1:image_caption_char=16'h7247;
                    2:image_caption_char=16'h7f29; 3:image_caption_char=16'h653e;
                    4:image_caption_char=16'hff1a; 5:image_caption_char=16'h0035;
                    6:image_caption_char=16'h0030; 7:image_caption_char=16'h0025;
                    8:image_caption_char=16'h0020; 9:image_caption_char=16'h5c45;
                    10:image_caption_char=16'h4e2d; 11:image_caption_char=16'h7f29;
                    12:image_caption_char=16'h5c0f;
                    default:begin end
                endcase
                2: case(index)
                    0:image_caption_char=16'h56fe; 1:image_caption_char=16'h7247;
                    2:image_caption_char=16'h7f29; 3:image_caption_char=16'h653e;
                    4:image_caption_char=16'hff1a; 5:image_caption_char=16'h0032;
                    6:image_caption_char=16'h0030; 7:image_caption_char=16'h0030;
                    8:image_caption_char=16'h0025; 9:image_caption_char=16'h0020;
                    10:image_caption_char=16'h4e2d; 11:image_caption_char=16'h5fc3;
                    12:image_caption_char=16'h653e; 13:image_caption_char=16'h5927;
                    default:begin end
                endcase
                default:begin end
            endcase
        end
    endfunction

    wire caption_enabled=display_video ? (display_enabled && external_visible) : (zoom_notice_count!=0);
    wire video_region=de && x>=(WIDTH-512)/2 && x<(WIDTH+512)/2 && y>=HEIGHT-104 && y<HEIGHT-80;
    wire video_text_region=de && x>=(WIDTH-512)/2 && x<(WIDTH+512)/2 && y>=HEIGHT-100 && y<HEIGHT-84;
    wire image_region=de && x>=WIDTH-256 && x<WIDTH-16 && y>=HEIGHT-48 && y<HEIGHT-24;
    wire image_text_region=de && x>=WIDTH-240 && x<WIDTH-16 && y>=HEIGHT-44 && y<HEIGHT-28;
    wire region=display_video ? (video_region && caption_enabled) : (image_region && caption_enabled);
    wire text_region=display_video ? (video_text_region && caption_enabled) : (image_text_region && caption_enabled);
    wire [8:0] tx=display_video ? x-(WIDTH-512)/2 : x-(WIDTH-240);
    assign font_request=text_region;
    assign font_codepoint=font_request ? (display_video ? external_codepoint : image_caption_char(display_zoom,tx[8:4])) : 16'h0020;
    assign font_row=display_video ? y-(HEIGHT-100) : y-(HEIGHT-44);

    reg panel_d,ink_d;
    reg [3:0] bit_d;
    reg panel_stage2,ink_stage2;
    reg [3:0] bit_stage2;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            panel_d<=0;ink_d<=0;bit_d<=0;
            panel_stage2<=0;ink_stage2<=0;bit_stage2<=0;
        end else begin
            panel_stage2<=panel_d;ink_stage2<=ink_d;bit_stage2<=bit_d;
            panel_d<=region && caption_enabled;
            ink_d<=font_request;
            bit_d<=tx[3:0];
        end
    end
    assign panel=FONT_LATENCY==2 ? panel_stage2 : panel_d;
    assign ink=FONT_LATENCY==2 ? (ink_stage2 && font_pixels[15-bit_stage2]) : (ink_d && font_pixels[15-bit_d]);
endmodule
