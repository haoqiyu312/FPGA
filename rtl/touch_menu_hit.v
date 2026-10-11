// Shared geometry for rendering and hit testing. Coordinates are DISPLAY
// pixels (640x480), not raw coordinates from an unverified touch controller.
module touch_menu_hit (
    input wire [9:0] x, y,
    output reg [2:0] button
);
    integer i;
    always @* begin
        button = 0;
        for (i=0; i<7; i=i+1)
            if (y>=408 && y<472 && x>=8+i*88 && x<88+i*88)
                button = i+1;
    end
endmodule
