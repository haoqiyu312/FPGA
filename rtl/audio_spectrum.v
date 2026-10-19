// Eight-bin Goertzel analyzer for the 48 kHz mono RVF2 soundtrack.
// One shared constant-coefficient multiplier processes the bins between samples.
module audio_spectrum (
    input wire clk, rst,
    input wire enabled, sample_tick,
    input wire signed [15:0] sample,
    output reg [47:0] levels
);
    reg signed [15:0] sample_latched;
    reg [5:0] sample_count;
    reg [2:0] band;
    reg processing;
    reg signed [31:0] q1 [0:7];
    reg signed [31:0] q2 [0:7];
    integer i;

    function signed [15:0] coefficient;
        input [2:0] index;
        begin
            case (index)
                0: coefficient=16'sd32610;
                1: coefficient=16'sd32138;
                2: coefficient=16'sd31357;
                3: coefficient=16'sd30274;
                4: coefficient=16'sd27246;
                5: coefficient=16'sd23170;
                6: coefficient=16'sd12540;
                default: coefficient=16'sd0;
            endcase
        end
    endfunction

    wire signed [47:0] product = $signed(coefficient(band)) * $signed(q1[band]);
    wire signed [31:0] next_q = $signed(sample_latched) + (product >>> 14) - $signed(q2[band]);
    wire [31:0] magnitude = next_q[31] ? -next_q : next_q;
    wire [5:0] measured_level = (|magnitude[31:19]) ? 6'd63 : magnitude[18:13];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sample_latched <= 0;
            sample_count <= 0;
            band <= 0;
            processing <= 0;
            levels <= 0;
            for (i=0;i<8;i=i+1) begin q1[i]<=0; q2[i]<=0; end
        end else if (!enabled) begin
            sample_count <= 0;
            band <= 0;
            processing <= 0;
            levels <= 0;
            for (i=0;i<8;i=i+1) begin q1[i]<=0; q2[i]<=0; end
        end else if (!processing && sample_tick) begin
            sample_latched <= sample;
            band <= 0;
            processing <= 1;
        end else if (processing) begin
            if (sample_count == 6'd63) begin
                q1[band] <= 0;
                q2[band] <= 0;
                levels[band*6 +: 6] <= measured_level >= levels[band*6 +: 6] ? measured_level :
                                      (levels[band*6 +: 6] != 0 ? levels[band*6 +: 6]-1'b1 : 6'd0);
            end else begin q1[band] <= next_q; q2[band] <= q1[band]; end

            if (band == 3'd7) begin
                processing <= 0;
                sample_count <= sample_count + 1'b1;
                if (sample_count == 6'd63) sample_count <= 0;
            end else band <= band + 1'b1;
        end
    end
endmodule
