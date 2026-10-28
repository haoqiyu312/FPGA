`timescale 1ns/1ps
module tb_playback_osd_switch;
    reg clk=0, rst=1, hide_switch=0, vblank=0;
    wire visible;
    always #5 clk=~clk;
    playback_osd_switch #(.DEBOUNCE_CYCLES(5)) dut(
        .clk(clk),.rst(rst),.hide_switch(hide_switch),
        .vblank(vblank),.visible(visible));
    task cycles(input integer n);
        begin repeat(n) @(negedge clk); end
    endtask
    task check(input expected);
        begin
            if(visible!==expected) $fatal(1,"OSD visibility: got %b expected %b",visible,expected);
        end
    endtask
    task blank;
        begin vblank=1;cycles(1);vblank=0;end
    endtask
    integer i;
    initial begin
        cycles(2);check(1);rst=0;
        // Repeated short pulses must not hide the OSD, even in blanking.
        vblank=1;
        for(i=0;i<8;i=i+1) begin
            hide_switch=1;cycles(2);hide_switch=0;cycles(3);check(1);
        end
        vblank=0;
        hide_switch=1;cycles(12);check(1);
        blank();check(0);
        // Returning the switch has no effect inside an active frame.
        hide_switch=0;cycles(12);check(0);
        blank();check(1);
        // A short opposite pulse must not change an accepted hidden state.
        hide_switch=1;cycles(12);blank();check(0);
        hide_switch=0;cycles(2);hide_switch=1;cycles(10);
        blank();check(0);
        // Reset must recover visibility even if SW4 is still high.
        rst=1;cycles(2);check(1);rst=0;cycles(12);check(1);
        blank();check(0);
        $display("PASS playback OSD: bounce, stable levels, blanking-only update, reset");
        $finish;
    end
    initial begin #100000; $fatal(1,"timeout"); end
endmodule
