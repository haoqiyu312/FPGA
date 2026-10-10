`timescale 1ns/1ps
module tb_media_keys;
    reg clk=0;always #5 clk=~clk;
    reg reset_n=0,key_n=1,restart_n=1;
    wire mode,action,run_n;
    wire auto_mode;
    integer actions=0,changes=0;
    reg previous_mode=0;
    media_key_control #(.DEBOUNCE_CYCLES(3),.LONG_CYCLES(30),.RESET_CYCLES(8)) dut
        (.clk(clk),.reset_n(reset_n),.key_auto_n(key_n),.restart_n(restart_n),
         .video_mode(mode),.short_press(action),.media_reset_n(run_n));
    image_key_control #(.DEBOUNCE_CYCLES(3),.CLOCK_HZ(1000),.EXTERNAL_AUTO(1)) image_keys
        (.clk(clk),.reset_n(run_n),.image_ready(1'b1),.key_next_n(1'b1),.key_prev_n(1'b1),
         .image_index(),.run_reset_n(),.key_auto_n(~(action & ~mode)),
         .interval_switch(2'b00),.auto_mode(auto_mode),.direction_switch(1'b0),
         .image_total(6'd4),.stable_interval(),.stable_direction());
    always @(posedge clk)begin
        if(reset_n)begin
            if(action)actions=actions+1;
            if(mode!=previous_mode)changes=changes+1;
        end
        previous_mode=mode;
    end
    task tick(input integer n);begin repeat(n)@(negedge clk);end endtask
    initial begin
        tick(3);reset_n=1;tick(8);
        key_n=0;tick(1);key_n=1;tick(8);
        if(actions || changes)$fatal(1,"bounce accepted");
        key_n=0;tick(12);
        if(actions || changes)$fatal(1,"action before release");
        key_n=1;tick(10);
        if(actions!=1 || mode || !auto_mode)$fatal(1,"short release/slide toggle failed");
        key_n=0;tick(37);
        if(!mode || run_n!==1'b0)$fatal(1,"long hold/reset failed");
        tick(80);
        if(changes!=1 || !mode || !run_n || auto_mode)$fatal(1,"held key repeated or reset stuck");
        key_n=1;tick(10);
        if(actions!=1)$fatal(1,"long release emitted short action");
        restart_n=0;tick(8);
        if(run_n || !mode)$fatal(1,"video restart failed");
        restart_n=1;tick(20);
        key_n=0;tick(12);key_n=1;tick(10);
        if(actions!=2 || !mode)$fatal(1,"video short action failed");
        key_n=0;tick(42);key_n=1;tick(20);
        if(mode || changes!=2 || actions!=2 || auto_mode)$fatal(1,"return to image failed");
        restart_n=0;tick(10);
        if(!run_n)$fatal(1,"image navigation reset media controller");
        reset_n=0;tick(3);
        if(mode || run_n)$fatal(1,"global reset failed");
        $display("PASS media keys: bounce, short release, long hold, restart, mode return, reset");
        $finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
