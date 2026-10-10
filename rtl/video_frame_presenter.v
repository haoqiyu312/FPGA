// One outstanding frame. Toggle handshake holds the completed bank stable until
// the display has selected it in vertical blanking. The writer then owns the old bank.
module video_frame_presenter #(
    parameter integer PIXEL_HZ=25000000
)(
    input wire clk,rst,vblank,frame_start,paused,
    input wire frame_toggle, input wire [7:0] fps,
    output reg consumed_toggle,output reg read_bank,
    output reg read_req,input wire read_ack,
    output reg show_frame
);
    reg [2:0] frame_sync,ack_sync;
    reg [7:0] fps_meta,fps_sync;
    reg [24:0] elapsed;
    reg primed,waiting_ack;
    reg [2:0] guard;
    // Only five constant divisors are synthesized; no run-time divider.
    reg [24:0] period;
    always @* case(fps_sync)
      1:period=PIXEL_HZ;2:period=PIXEL_HZ/2;3:period=PIXEL_HZ/3;
      4:period=PIXEL_HZ/4;default:period=PIXEL_HZ/5;
    endcase
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            frame_sync<=0;ack_sync<=0;fps_meta<=5;fps_sync<=5;
            consumed_toggle<=0;read_bank<=0;read_req<=0;show_frame<=0;
            elapsed<=0;primed<=0;waiting_ack<=0;guard<=0;
        end else begin
            frame_sync<={frame_sync[1:0],frame_toggle};ack_sync<={ack_sync[1:0],read_ack};
            fps_meta<=fps;fps_sync<=fps_meta;
            // Saturation deliberately slows playback on a slow card; never skip frames.
            if(!paused && elapsed<period+PIXEL_HZ/10)elapsed<=elapsed+1'b1;
            if(waiting_ack)begin
                if(ack_sync[2])begin read_req<=0;waiting_ack<=0;guard<=7;end
            end else if(guard!=0)begin
                guard<=guard-1'b1;
                if(guard==1)primed<=1;
            end
            if(vblank && !waiting_ack && guard==0 && !ack_sync[2])begin
                if(frame_sync[2]!=consumed_toggle && !paused && (!show_frame || elapsed>=period))begin
                    read_bank<=~read_bank;consumed_toggle<=frame_sync[2];
                    elapsed<=show_frame && elapsed>=period ? elapsed-period : 0;
                    read_req<=1;waiting_ack<=1;primed<=0;
                end else if(show_frame)begin
                    read_req<=1;waiting_ack<=1;primed<=0;
                end
            end
            if(frame_start)show_frame<=primed;
        end
    end
endmodule
