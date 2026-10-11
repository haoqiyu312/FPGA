// Parameterized mapping; defaults match DTBO and full-screen 640x480 scaling.
// Actual display letterboxing/rotation must be checked and calibrated on board.
module touch_coordinate_map #(
    parameter integer RAW_WIDTH=720,RAW_HEIGHT=720,
    parameter integer SWAP_XY=0,INVERT_X=0,INVERT_Y=0
)(
    input wire [15:0] raw_x,raw_y,
    output wire in_range,
    output wire [9:0] display_x,display_y
);
    wire [15:0] sx=SWAP_XY ? raw_y : raw_x, sy=SWAP_XY ? raw_x : raw_y;
    function integer gcd;
        input integer a,b;
        integer rem;
        begin
            while(b!=0)begin rem=a%b;a=b;b=rem;end
            gcd=a;
        end
    endfunction
    localparam X_BITS=$clog2(RAW_WIDTH),Y_BITS=$clog2(RAW_HEIGHT);
    localparam X_GCD=gcd(640,RAW_WIDTH),Y_GCD=gcd(480,RAW_HEIGHT);
    localparam X_NUM=640/X_GCD,Y_NUM=480/Y_GCD;
    // Reduce ratios before synthesizing: default x*8/9 and y*2/3.
    // Bound the arithmetic to the actual coordinate width, avoiding a wide
    // combinational divider and unnecessary DSPs for a sparse touch stream.
    wire [X_BITS-1:0] mx=INVERT_X ? RAW_WIDTH-1-sx : sx;
    wire [Y_BITS-1:0] my=INVERT_Y ? RAW_HEIGHT-1-sy : sy;
    wire [X_BITS+$clog2(X_NUM+1)-1:0] numerator_x=mx*X_NUM;
    wire [Y_BITS+$clog2(Y_NUM+1)-1:0] numerator_y=my*Y_NUM;
    wire [9:0] scaled_x=numerator_x/(RAW_WIDTH/X_GCD);
    wire [9:0] scaled_y=numerator_y/(RAW_HEIGHT/Y_GCD);
    assign in_range=sx<RAW_WIDTH && sy<RAW_HEIGHT;
    assign display_x=scaled_x[9:0];
    assign display_y=scaled_y[9:0];
endmodule
