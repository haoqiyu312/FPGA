// Driver-independent single-contact menu. All inputs are synchronous to clk.
// sample_valid publishes a complete coherent sample; contact_down=0 is UP.
// A tap must start/end in the same button. Leaving it cancels the gesture.
// Reset, lost samples and multi-touch require a fresh UP before accepting DOWN.
module touch_menu_control #(
    parameter integer TIMEOUT_CYCLES=12500000
)(
    input wire clk, reset_n, menu_visible,
    input wire sample_valid, contact_down, multiple_contacts,
    input wire [9:0] touch_x, touch_y,
    input wire video_mode,
    output reg action_valid,
    // 1=mode, 2=play/auto, 3=previous image, 4=next image,
    // 5=restart video, 6=volume down, 7=volume up.
    output reg [2:0] action,
    output wire [2:0] pressed_button
);
    localparam TIMER_BITS=TIMEOUT_CYCLES<2 ? 1 : $clog2(TIMEOUT_CYCLES);
    reg [TIMER_BITS-1:0] timer;
    reg armed, held, gesture_video;
    reg [2:0] candidate;
    wire [2:0] hit;
    touch_menu_hit u_hit (.x(touch_x),.y(touch_y),.button(hit));
    assign pressed_button=held ? candidate : 3'd0;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            timer<=0;armed<=0;held<=0;candidate<=0;gesture_video<=0;
            action_valid<=0;action<=0;
        end else begin
            action_valid<=0;action<=0;
            if(!menu_visible) begin
                timer<=0;armed<=0;held<=0;candidate<=0;
            end else if(sample_valid) begin
                timer<=0;
                if(multiple_contacts) begin
                    armed<=0;held<=0;candidate<=0;
                end else if(!contact_down) begin
                    if(held && candidate!=0 && gesture_video==video_mode) begin
                        // PREV/NEXT only in image mode; HOME only in video.
                        if(!((candidate==3 || candidate==4) && video_mode) &&
                           !(candidate==5 && !video_mode)) begin
                            action_valid<=1;action<=candidate;
                        end
                    end
                    armed<=1;held<=0;candidate<=0;
                end else if(armed && !held) begin
                    held<=1;candidate<=hit;gesture_video<=video_mode;
                end else if(held && (hit!=candidate || gesture_video!=video_mode))
                    candidate<=0;
            end else if(timer==TIMEOUT_CYCLES-1) begin
                armed<=0;held<=0;candidate<=0;
            end else timer<=timer+1'b1;
        end
    end
endmodule
