`timescale 1ns/1ps
module tb_touch_i2c;
    reg clk=0;always #5 clk=~clk;
    reg reset_n=0,start=0,reading=1;
    reg [3:0] length=8;
    tri1 scl,sda;
    reg slave_low=0,stretch_low=0,stuck=0,nack_address=0,stretch_once=0;
    assign sda=slave_low ? 1'b0 : 1'bz;
    assign scl=(stretch_low || stuck) ? 1'b0 : 1'bz;
    wire busy,done,error;wire [63:0] data;
    wire master_scl_low,master_sda_low;
    assign scl=master_scl_low ? 1'b0 : 1'bz;
    assign sda=master_sda_low ? 1'b0 : 1'bz;
    i2c_register_master #(.QUARTER_CYCLES(8),.TIMEOUT_CYCLES(20000)) dut (
        .clk(clk),.reset_n(reset_n),.start(start),.read_request(reading),
        .device_address(7'h14),.register_address(16'h814e),.read_length(length),
        .write_data(8'h00),.busy(busy),.done(done),.error(error),.read_data(data),
        .scl_in(scl),.sda_in(sda),.scl_drive_low(master_scl_low),.sda_drive_low(master_sda_low));
    task receive_byte;
        output [7:0] value;integer k;
        begin for(k=7;k>=0;k=k-1)begin @(posedge scl);value[k]=sda;end end
    endtask
    task ack;
        input acknowledge;
        begin
            @(negedge scl);slave_low=acknowledge;
            if(stretch_once)begin stretch_once=0;stretch_low=1;#1000;stretch_low=0;end
            @(posedge scl);@(negedge scl);slave_low=0;
        end
    endtask
    task send_byte;
        input [7:0] value;input last;integer k;
        begin
            for(k=7;k>=0;k=k-1)begin
                slave_low=~value[k];@(posedge scl);@(negedge scl);
            end
            slave_low=0;@(posedge scl);
            if(sda!==last)$fatal(1,"master ACK/NACK incorrect: last=%0d sda=%b",last,sda);
            @(negedge scl);
        end
    endtask
    task stop_seen;
        begin : wait_stop
            // A slave may release ACK while SCL is low before the master
            // prepares STOP. Only SDA rising while SCL is high is STOP.
            forever begin @(posedge sda);if(scl===1)disable wait_stop;end
        end
    endtask
    reg [7:0] value;
    integer i,transactions=0;
    initial forever begin
        // START while bus high; ignore data edges while SCL low.
        @(negedge sda);
        if(scl===1)begin
            receive_byte(value);
            if(value!==8'h28)$fatal(1,"wrong write address: %h",value);
            if(nack_address)begin ack(0);stop_seen;end
            else begin
                ack(1);receive_byte(value);if(value!==8'h81)$fatal(1,"register MSB");
                ack(1);receive_byte(value);if(value!==8'h4e)$fatal(1,"register LSB");ack(1);
                if(reading)begin
                    @(negedge sda);if(scl!==1)$fatal(1,"missing repeated START");
                    receive_byte(value);if(value!==8'h29)$fatal(1,"wrong read address");ack(1);
                    for(i=0;i<length;i=i+1)send_byte(8'ha0+i,i==length-1);
                end else begin
                    receive_byte(value);if(value!==0)$fatal(1,"write byte");ack(1);
                end
                stop_seen;
            end
            transactions=transactions+1;
        end
    end
    task request;
        input expect_error;
        begin
            @(negedge clk);start=1;@(negedge clk);start=0;
            wait(done);#1;
            if(error!==expect_error || busy!==0)$fatal(1,"completion error=%b expected=%b",error,expect_error);
            @(negedge clk);
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);reset_n=1;
        request(0);if(data!==64'ha7a6a5a4a3a2a1a0)$fatal(1,"burst data order %h",data);
        length=1;stretch_once=1;request(0);if(data!==64'ha0)$fatal(1,"single byte");
        reading=0;request(0);
        nack_address=1;reading=1;request(1);nack_address=0;
        length=0;request(1); // rejected without starting the bus
        length=9;request(1);
        length=1;stuck=1;request(1);stuck=0;
        #100;if(scl!==1 || sda!==1)$fatal(1,"bus not released after timeout");
        if(transactions!=4)$fatal(1,"unexpected transaction count %0d",transactions);
        $display("TOUCH_I2C_TESTS_PASSED");$finish;
    end
    initial begin #1000000;$fatal(1,"test timeout");end
endmodule
