// GT911 polling frontend. Uses the panel's existing power-on configuration;
// never rewrites firmware/config or drives its reset/address-select pins.
// DTBO identifies goodix,gt911 at 0x14 (Pi4) / 0x5d (Pi3).
module gt911_touch_reader #(
    parameter integer POWERUP_CYCLES=10000000,
    parameter integer POLL_CYCLES=500000,
    parameter integer I2C_QUARTER_CYCLES=125,
    parameter integer I2C_TIMEOUT_CYCLES=500000
)(
    input wire clk,reset_n,
    input wire scl_in,sda_in,
    output wire scl_drive_low,sda_drive_low,
    output reg online,sample_valid,contact_down,multiple_contacts,
    output reg [15:0] raw_x,raw_y,
    output reg [6:0] active_address,
    output reg fault
);
    localparam WAIT_POWER=0,PROBE=1,PROBE_WAIT=2,DELAY=3,
        REPORT=4,REPORT_WAIT=5,CLEAR=6,CLEAR_WAIT=7;
    localparam MAX_DELAY=POWERUP_CYCLES>POLL_CYCLES ? POWERUP_CYCLES : POLL_CYCLES;
    localparam COUNT_BITS=MAX_DELAY<2 ? 1 : $clog2(MAX_DELAY);
    reg [COUNT_BITS-1:0] count;
    reg [2:0] state;
    reg start,reading;
    reg [15:0] register_address;
    reg [3:0] length;
    wire busy,done,error;
    wire [63:0] data;
    reg [63:0] report;
    i2c_register_master #(.QUARTER_CYCLES(I2C_QUARTER_CYCLES),
        .TIMEOUT_CYCLES(I2C_TIMEOUT_CYCLES)) u_bus (
        .clk(clk),.reset_n(reset_n),.start(start),.read_request(reading),
        .device_address(active_address),.register_address(register_address),
        .read_length(length),.write_data(8'd0),.busy(busy),.done(done),.error(error),
        .read_data(data),.scl_in(scl_in),.sda_in(sda_in),
        .scl_drive_low(scl_drive_low),.sda_drive_low(sda_drive_low));
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            count<=0;state<=WAIT_POWER;start<=0;reading<=1;register_address<=0;length<=0;
            online<=0;sample_valid<=0;contact_down<=0;multiple_contacts<=0;
            raw_x<=0;raw_y<=0;active_address<=7'h14;fault<=0;report<=0;
        end else begin
            start<=0;sample_valid<=0;fault<=0;
            case(state)
                WAIT_POWER:if(count==POWERUP_CYCLES-1)begin count<=0;state<=PROBE;end
                           else count<=count+1'b1;
                PROBE:if(!busy)begin
                    reading<=1;register_address<=16'h8140;length<=4;start<=1;state<=PROBE_WAIT;
                end
                PROBE_WAIT:if(done)begin
                    // ID bytes '9','1','1'. Do not accept unrelated devices.
                    if(!error && data[23:0]==24'h313139)begin online<=1;count<=0;state<=DELAY;end
                    else begin
                        online<=0;fault<=1;active_address<=active_address==7'h14 ? 7'h5d : 7'h14;
                        count<=0;state<=WAIT_POWER;
                    end
                end
                DELAY:if(count==POLL_CYCLES-1)begin count<=0;state<=REPORT;end
                      else count<=count+1'b1;
                REPORT:if(!busy)begin
                    reading<=1;register_address<=16'h814e;length<=8;start<=1;state<=REPORT_WAIT;
                end
                REPORT_WAIT:if(done)begin
                    if(error)begin online<=0;fault<=1;count<=0;state<=WAIT_POWER;end
                    else if(data[7])begin report<=data;state<=CLEAR;end
                    else begin count<=0;state<=DELAY;end
                end
                CLEAR:if(!busy)begin
                    reading<=0;register_address<=16'h814e;length<=1;start<=1;state<=CLEAR_WAIT;
                end
                CLEAR_WAIT:if(done)begin
                    if(error)begin online<=0;fault<=1;count<=0;state<=WAIT_POWER;end
                    else begin
                        sample_valid<=1;contact_down<=report[3:0]!=0;
                        multiple_contacts<=report[3:0]>1;
                        raw_x<=report[31:16];raw_y<=report[47:32];
                        count<=0;state<=DELAY;
                    end
                end
                default:begin state<=WAIT_POWER;count<=0;online<=0;end
            endcase
        end
    end
endmodule
