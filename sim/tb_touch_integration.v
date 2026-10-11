`timescale 1ns/1ps
module tb_touch_integration;
    reg clk=0,pclk=0;always #5 clk=~clk;always #7 pclk=~pclk;
    reg reset_n=0,dreset_n=0,mode_event=0,restart_event=0,up=0,down=0;
    wire mode,short_press,run_n;
    wire [3:0] level;
    reg next_event=0,prev_event=0,auto_event=0,image_ready=1;
    wire [4:0] image_index;wire image_run_n,auto_mode;
    image_key_control #(.DEBOUNCE_CYCLES(3),.RESET_CYCLES(4),.CLOCK_HZ(1000),.EXTERNAL_AUTO(1),.EXTERNAL_STEP(1)) images
        (.clk(clk),.reset_n(run_n),.image_ready(image_ready),.key_next_n(1'b1),.key_prev_n(1'b1),
        .image_index(image_index),.run_reset_n(image_run_n),.key_auto_n(~auto_event),
        .interval_switch(2'b00),.auto_mode(auto_mode),.direction_switch(1'b0),.image_total(6'd3),
        .stable_interval(),.stable_direction(),.next_event(next_event),.prev_event(prev_event));
    reg [23:0] pcm=0;wire [23:0] scaled;
    reg [8:0] snapshot=0;wire [8:0] received;
    media_key_control #(.DEBOUNCE_CYCLES(3),.LONG_CYCLES(30),.RESET_CYCLES(4),.EXTERNAL_ACTIONS(1)) keys
        (.clk(clk),.reset_n(reset_n),.key_auto_n(1'b1),.restart_n(1'b1),
        .video_mode(mode),.short_press(short_press),.media_reset_n(run_n),
        .mode_event(mode_event),.restart_event(restart_event));
    media_volume_control volume(.clk(clk),.reset_n(reset_n),.up_event(up),.down_event(down),.level(level));
    media_volume_apply gain(.pcm_in(pcm),.level(level),.pcm_out(scaled));
    ui_state_bridge bridge(.source_clk(clk),.source_reset_n(reset_n),.source_data(snapshot),
        .destination_clk(pclk),.destination_reset_n(dreset_n),.destination_data(received));
    task tick(input integer n);begin repeat(n)@(negedge clk);end endtask
    initial begin
        tick(3);reset_n=1;dreset_n=1;tick(2);
        if(level!==8 || !run_n || mode)$fatal(1,"startup defaults");
        tick(6);next_event=1;tick(1);next_event=0;
        if(image_index!==1 || image_run_n)$fatal(1,"touch next image");
        tick(6);prev_event=1;tick(1);prev_event=0;tick(6);
        if(image_index!==0)$fatal(1,"touch previous image");
        prev_event=1;tick(1);prev_event=0;tick(6);
        if(image_index!==2)$fatal(1,"touch previous wraps");
        next_event=1;prev_event=1;tick(1);next_event=0;prev_event=0;
        if(image_index!==2)$fatal(1,"conflicting image events");
        auto_event=1;tick(1);auto_event=0;
        if(!auto_mode)$fatal(1,"touch auto play");
        pcm=24'hfedcba;#1;if(scaled!==pcm)$fatal(1,"unity must preserve negative PCM");
        down=1;tick(1);down=0;#1;
        if(level!==7 || scaled!==24'hff6e5d)$fatal(1,"signed attenuation");
        down=1;tick(12);down=0;#1;
        if(level!==0 || scaled!==0)$fatal(1,"mute/lower saturation");
        up=1;tick(12);up=0;#1;
        if(level!==8 || scaled!==pcm)$fatal(1,"upper saturation");
        up=1;down=1;tick(1);up=0;down=0;
        if(level!==8)$fatal(1,"conflicting volume events");
        mode_event=1;tick(1);mode_event=0;
        if(!mode || run_n || short_press)$fatal(1,"touch mode switch/reset");
        tick(6);if(!run_n)$fatal(1,"mode reset release");
        restart_event=1;tick(1);restart_event=0;
        if(!mode || run_n)$fatal(1,"touch video restart");
        tick(6);mode_event=1;tick(1);mode_event=0;tick(6);
        restart_event=1;tick(1);restart_event=0;
        if(mode || !run_n)$fatal(1,"image mode ignores video restart");
        snapshot=9'h1ab;tick(35);
        if(received!==snapshot)$fatal(1,"UI mailbox transfer");
        dreset_n=0;tick(4);snapshot=9'h054;dreset_n=1;tick(35);
        if(received!==snapshot)$fatal(1,"UI destination reset recovery");
        snapshot=9'h155;tick(35);
        if(received!==snapshot)$fatal(1,"UI subsequent transfer");
        $display("PASS touch integration: mode/restart, signed volume, saturation, mailbox/reset");$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
