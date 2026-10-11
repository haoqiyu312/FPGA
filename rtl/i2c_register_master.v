// Single-master, open-drain I2C. 16-bit register address, MSB first.
// Read 1..8 bytes (first byte in read_data[7:0]) or write one byte.
// No internal pullups: external 3.3V pullups must be verified before wiring.
module i2c_register_master #(
    parameter integer QUARTER_CYCLES=125,
    parameter integer TIMEOUT_CYCLES=500000
)(
    input wire clk,reset_n,start,read_request,
    input wire [6:0] device_address,
    input wire [15:0] register_address,
    input wire [3:0] read_length,
    input wire [7:0] write_data,
    output reg busy,done,error,
    output reg [63:0] read_data,
    input wire scl_in,sda_in,
    output wire scl_drive_low,sda_drive_low
);
    localparam IDLE=0,START_FREE=1,START_PULL=2,START_LOW=3,
        TX_LOW=4,TX_RISE=5,TX_HIGH=6,TX_FALL=7,
        ACK_LOW=8,ACK_RISE=9,ACK_HIGH=10,ACK_FALL=11,
        RESTART_LOW=12,RESTART_RISE=13,RESTART_HIGH=14,RESTART_PULL=15,
        RX_LOW=16,RX_RISE=17,RX_HIGH=18,RX_FALL=19,
        MACK_LOW=20,MACK_RISE=21,MACK_HIGH=22,MACK_FALL=23,
        STOP_LOW=24,STOP_RISE=25,STOP_HIGH=26,STOP_RELEASE=27,FINISH=28;
    localparam Q_BITS=QUARTER_CYCLES<2 ? 1 : $clog2(QUARTER_CYCLES);
    localparam T_BITS=TIMEOUT_CYCLES<2 ? 1 : $clog2(TIMEOUT_CYCLES);
    reg [4:0] state;
    reg [Q_BITS-1:0] quarter;
    reg [T_BITS-1:0] watchdog;
    reg scl_low,sda_low,reading,nack;
    reg [1:0] scl_sync=2'b11,sda_sync=2'b11;
    reg [6:0] address;
    reg [15:0] reg_address;
    reg [7:0] tx,rx,write_byte;
    reg [2:0] bit_index,byte_index,step;
    reg [3:0] length;
    assign scl_drive_low=scl_low;
    assign sda_drive_low=sda_low;
    wire waiting_high=state==START_FREE || state==TX_HIGH || state==ACK_HIGH ||
        state==RESTART_HIGH || state==RX_HIGH || state==MACK_HIGH || state==STOP_HIGH;
    // Keep input synchronizers free-running. Transactions wait for the bus
    // after reset; asynchronous reset is only needed by the state machine.
    always @(posedge clk) begin
        scl_sync<={scl_sync[0],scl_in};sda_sync<={sda_sync[0],sda_in};
    end
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            state<=IDLE;quarter<=0;watchdog<=0;scl_low<=0;sda_low<=0;
            busy<=0;done<=0;error<=0;read_data<=0;reading<=0;nack<=0;
            address<=0;reg_address<=0;write_byte<=0;tx<=0;rx<=0;
            bit_index<=7;byte_index<=0;step<=0;length<=0;
        end else begin
            done<=0;
            if(state==IDLE) begin
                quarter<=0;watchdog<=0;scl_low<=0;sda_low<=0;
                if(start) begin
                    error<=0;read_data<=0;
                    if(read_request && (read_length==0 || read_length>8)) begin
                        error<=1;done<=1;
                    end else begin
                        address<=device_address;reg_address<=register_address;
                        write_byte<=write_data;length<=read_length;reading<=read_request;
                        busy<=1;state<=START_FREE;step<=0;byte_index<=0;
                        tx<={device_address,1'b0};bit_index<=7;nack<=0;
                    end
                end
            end else if(watchdog==TIMEOUT_CYCLES-1) begin
                // A stuck bus cannot support a STOP; release both lines safely.
                busy<=0;done<=1;error<=1;scl_low<=0;sda_low<=0;state<=IDLE;
            end else begin
                watchdog<=watchdog+1'b1;
                if(waiting_high && !scl_sync[1]) quarter<=0;
                else if(quarter!=QUARTER_CYCLES-1)quarter<=quarter+1'b1;
                else begin
                    quarter<=0;
                    case(state)
                        START_FREE: if(sda_sync[1])state<=START_PULL;
                        START_PULL: begin sda_low<=1;state<=START_LOW;end
                        START_LOW: begin scl_low<=1;state<=TX_LOW;end
                        TX_LOW: begin sda_low<=~tx[bit_index];state<=TX_RISE;end
                        TX_RISE: begin scl_low<=0;state<=TX_HIGH;end
                        TX_HIGH: state<=TX_FALL;
                        TX_FALL: begin
                            scl_low<=1;
                            if(bit_index==0)state<=ACK_LOW;
                            else begin bit_index<=bit_index-1'b1;state<=TX_LOW;end
                        end
                        ACK_LOW: begin sda_low<=0;state<=ACK_RISE;end
                        ACK_RISE: begin scl_low<=0;state<=ACK_HIGH;end
                        ACK_HIGH: begin nack<=sda_sync[1];state<=ACK_FALL;end
                        ACK_FALL: begin
                            scl_low<=1;bit_index<=7;
                            if(nack)begin error<=1;state<=STOP_LOW;end
                            else case(step)
                                0:begin tx<=reg_address[15:8];step<=1;state<=TX_LOW;end
                                1:begin tx<=reg_address[7:0];step<=2;state<=TX_LOW;end
                                2:if(reading)begin step<=3;state<=RESTART_LOW;end
                                  else begin tx<=write_byte;step<=4;state<=TX_LOW;end
                                3:begin state<=RX_LOW;rx<=0;end
                                default:state<=STOP_LOW;
                            endcase
                        end
                        RESTART_LOW: begin sda_low<=0;state<=RESTART_RISE;end
                        RESTART_RISE: begin scl_low<=0;state<=RESTART_HIGH;end
                        RESTART_HIGH: state<=RESTART_PULL;
                        RESTART_PULL: begin
                            sda_low<=1;tx<={address,1'b1};state<=START_LOW;
                        end
                        RX_LOW: begin sda_low<=0;state<=RX_RISE;end
                        RX_RISE: begin scl_low<=0;state<=RX_HIGH;end
                        RX_HIGH: begin rx[bit_index]<=sda_sync[1];state<=RX_FALL;end
                        RX_FALL: begin
                            scl_low<=1;
                            if(bit_index==0) begin
                                read_data[byte_index*8+:8]<=rx;state<=MACK_LOW;
                            end else begin bit_index<=bit_index-1'b1;state<=RX_LOW;end
                        end
                        MACK_LOW: begin sda_low<=({1'b0,byte_index}+1<length);state<=MACK_RISE;end
                        MACK_RISE: begin scl_low<=0;state<=MACK_HIGH;end
                        MACK_HIGH:state<=MACK_FALL;
                        MACK_FALL:begin
                            scl_low<=1;
                            if({1'b0,byte_index}+1==length)state<=STOP_LOW;
                            else begin byte_index<=byte_index+1'b1;bit_index<=7;rx<=0;state<=RX_LOW;end
                        end
                        STOP_LOW: begin scl_low<=1;sda_low<=1;state<=STOP_RISE;end
                        STOP_RISE:begin scl_low<=0;state<=STOP_HIGH;end
                        STOP_HIGH:state<=STOP_RELEASE;
                        STOP_RELEASE:begin sda_low<=0;state<=FINISH;end
                        FINISH:begin busy<=0;done<=1;state<=IDLE;end
                        default:begin error<=1;state<=STOP_LOW;end
                    endcase
                end
            end
        end
    end
endmodule
