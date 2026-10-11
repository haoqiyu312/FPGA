`timescale 1ns/1ps
// This test substitutes the register-transaction transport. The separate
// tb_touch_i2c exercises the actual open-drain bus and clock stretching.
module i2c_register_master #(
    parameter QUARTER_CYCLES=125,TIMEOUT_CYCLES=500000
)(input wire clk,reset_n,start,read_request,
  input wire [6:0] device_address,input wire [15:0] register_address,
  input wire [3:0] read_length,input wire [7:0] write_data,
  output reg busy,done,error,output reg [63:0] read_data,
  input wire scl_in,sda_in,output wire scl_drive_low,sda_drive_low);
    integer transaction,delay_count;
    assign scl_drive_low=0;assign sda_drive_low=0;
    always @(posedge clk)begin
        if(!reset_n)begin transaction<=0;busy<=0;done<=0;error<=0;read_data<=0;delay_count<=0;end
        else begin
            done<=0;
            if(start)begin
                if(busy)$fatal(1,"overlapping requests");
                busy<=1;delay_count<=3;transaction<=transaction+1;error<=0;read_data<=0;
                if(device_address!==(transaction==0 ? 7'h14 : 7'h5d))$fatal(1,"address fallback");
                case(transaction)
                    0,1,11:begin
                        if(!read_request || register_address!=16'h8140 || read_length!=4)$fatal(1,"ID request");
                        if(transaction==0)error<=1;else read_data<=64'h00313139;
                    end
                    2,3,5,7,9,12:begin
                        if(!read_request || register_address!=16'h814e || read_length!=8)$fatal(1,"report request");
                        case(transaction)
                            2:read_data<=0;
                            5:read_data<=64'h000002cf02cf0081;
                            7:read_data<=64'h0000006400640082;
                            default:read_data<=64'h80;
                        endcase
                    end
                    4,6,8,10,13:begin
                        if(read_request || register_address!=16'h814e || write_data!=0)$fatal(1,"status clear");
                        if(transaction==10)error<=1;
                    end
                    default:$fatal(1,"unexpected request %0d",transaction);
                endcase
            end else if(busy)begin
                if(delay_count==0)begin busy<=0;done<=1;end
                else delay_count<=delay_count-1;
            end
        end
    end
endmodule
module tb_gt911_reader;
    reg clk=0;always #5 clk=~clk;
    reg reset_n=0;
    tri1 scl,sda;
    wire online,valid,down,multi,fault;
    wire [15:0] x,y;wire [6:0] address;
    gt911_touch_reader #(.POWERUP_CYCLES(4),.POLL_CYCLES(4)) dut (
        .clk(clk),.reset_n(reset_n),.scl_in(scl),.sda_in(sda),.scl_drive_low(),.sda_drive_low(),
        .online(online),.sample_valid(valid),.contact_down(down),.multiple_contacts(multi),
        .raw_x(x),.raw_y(y),.active_address(address),.fault(fault));
    wire in_range;wire [9:0] dx,dy;
    touch_coordinate_map map (.raw_x(x),.raw_y(y),.in_range(in_range),.display_x(dx),.display_y(dy));
    integer samples=0,faults=0;
    always @(negedge clk)if(reset_n)begin
        if(fault)faults=faults+1;
        if(valid)begin
            if(!online || address!=7'h5d)$fatal(1,"publish while offline");
            case(samples)
                0:if(down || multi)$fatal(1,"UP report");
                1:if(!down || multi || x!=719 || y!=719 || !in_range || dx!=639 || dy!=479)$fatal(1,"DOWN coordinates");
                2:if(!down || !multi)$fatal(1,"multitouch must cancel gestures");
                3:begin
                    if(down || multi || faults!=2)$fatal(1,"recovery, clear failure must not publish UP");
                    $display("GT911_READER_TESTS_PASSED");$finish;
                end
                default:$fatal(1,"unexpected sample");
            endcase
            samples=samples+1;
        end
    end
    initial begin repeat(3)@(negedge clk);reset_n=1;end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
