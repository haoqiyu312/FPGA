`timescale 1ns/1ps
module tb_touch_menu;
    reg clk=0;always #5 clk=~clk;
    reg reset_n=0,visible=1,valid=0,down=0,multi=0,video=0;
    reg [9:0] x=0,y=0;
    wire av;wire [2:0] action,pressed;
    touch_menu_control #(.TIMEOUT_CYCLES(8)) dut (
        .clk(clk),.reset_n(reset_n),.menu_visible(visible),
        .sample_valid(valid),.contact_down(down),.multiple_contacts(multi),
        .touch_x(x),.touch_y(y),.video_mode(video),
        .action_valid(av),.action(action),.pressed_button(pressed));
    reg de=1;wire [23:0] rgb;
    touch_menu_overlay overlay (.x(x),.y(y),.de(de),.menu_visible(visible),
        .video_mode(video),.playing(1'b0),.pressed_button(pressed),
        .rgb_in(24'h123456),.rgb_out(rgb));
    task sample;
        input d;input [9:0] sx,sy;input [2:0] expected;
        begin
            @(negedge clk);valid=1;down=d;x=sx;y=sy;
            @(posedge clk);#1;
            if(av!==(expected!=0) || action!==expected)
                $fatal(1,"sample (%0d,%0d), down=%0d: got %0d/%0d expected %0d",sx,sy,d,av,action,expected);
            @(negedge clk);valid=0;
        end
    endtask
    integer i;
    initial begin
        #2;reset_n=0;repeat(2)@(negedge clk);reset_n=1;
        sample(1,48,440,0);sample(0,48,440,0);
        for(i=0;i<7;i=i+1)begin
            sample(1,48+i*88,440,0);
            sample(1,48+i*88,440,0);
            sample(0,48+i*88,440,i==4 ? 0 : i+1);
            @(posedge clk);#1;if(av || action!=0)$fatal(1,"command must last one cycle");
        end
        sample(1,0,440,0);sample(1,48,440,0);sample(0,48,440,0);
        sample(1,88,440,0);sample(0,88,440,0);
        sample(1,48,407,0);sample(0,48,407,0);
        sample(1,48,472,0);sample(0,48,472,0);
        sample(1,640,440,0);sample(0,640,440,0);
        sample(1,8,408,0);sample(0,8,408,1);
        sample(1,48,440,0);sample(1,136,440,0);sample(1,48,440,0);sample(0,48,440,0);
        sample(1,48,440,0);multi=1;sample(1,48,440,0);multi=0;
        sample(1,48,440,0);sample(0,48,440,0);
        sample(1,48,440,0);repeat(10)@(negedge clk);
        sample(1,48,440,0);sample(0,48,440,0);
        sample(1,48,440,0);visible=0;repeat(2)@(negedge clk);visible=1;
        sample(1,48,440,0);sample(0,48,440,0);
        sample(1,48,440,0);video=1;sample(0,48,440,0);
        sample(1,224,440,0);sample(0,224,440,0);
        sample(1,312,440,0);sample(0,312,440,0);
        sample(1,400,440,0);sample(0,400,440,5);
        @(negedge clk);x=48;y=399;#1;if(rgb!==24'h123456)$fatal(1,"outside overlay");
        y=440;visible=0;#1;if(rgb!==24'h123456)$fatal(1,"hidden overlay");
        visible=1;de=0;#1;if(rgb!==24'h123456)$fatal(1,"blanking overlay");
        de=1;x=224;#1;if(rgb!==24'h606870)$fatal(1,"disabled icon");
        $display("TOUCH_MENU_TESTS_PASSED");$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
