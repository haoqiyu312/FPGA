`timescale 1ns/1ps
// Both row orders share one writer. Switch modes during an in-flight frame.
module tb_media_frame_write;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,req=0,flip=1,bank=0;
    wire ack,finish,en;
    wire [20:0] addr;
    integer n=0,expected,completed=0;
    frame_fifo_write #(.BURST_SIZE(128),.RUNTIME_V_FLIP(1)) dut
        (.rst(rst),.mem_clk(clk),.write_v_flip(flip),.Sdr_init_done(1'b1),
         .Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.App_rd_busy(1'b0),
         .O_wr_busy(),.App_wr_en(en),.App_wr_addr(addr),.write_req(req),
         .write_req_ack(ack),.write_finish(finish),.write_addr_0(21'd0),
         .write_addr_1(21'd307200),.write_addr_2(21'd0),.write_addr_3(21'd0),
         .write_addr_index({1'b0,bank}),.write_len(21'd307200),
         .fifo_aclr(),.rdusedw(10'd384));
    always @(posedge clk)if(!rst)begin
        if(en)begin
            expected=(bank ? 307200 : 0)+(flip ? (479-n/640)*640+n%640 : n);
            if(addr!==expected)$fatal(1,"row order/bank: pixel %0d address %0d expected %0d",n,addr,expected);
            n=n+1;
        end
        if(finish)begin
            if(n!=307200)$fatal(1,"short frame: %0d",n);
            completed=completed+1;
        end
    end
    task start_frame(input reg f,input reg b);begin
        @(negedge clk);rst=1;req=0;flip=f;bank=b;n=0;
        repeat(5)@(negedge clk);rst=0;
        repeat(5)@(negedge clk);req=1;
        wait(ack);@(negedge clk);req=0;
    end endtask
    initial begin
        start_frame(1,0);wait(completed==1);
        start_frame(0,0);wait(completed==2);
        start_frame(0,1);wait(n>1000);
        start_frame(1,0);wait(completed==3);
        start_frame(0,1);wait(completed==4);
        $display("PASS shared writer: BMP, video, bank 1, reset during frame, return to BMP");
        $finish;
    end
    initial begin #30000000;$fatal(1,"timeout");end
endmodule
