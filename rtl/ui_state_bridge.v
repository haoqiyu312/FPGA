// Bundled-data mailbox: source holds the payload from request until ack.
// Destination captures it after a three-clock request synchronizer. Repeated
// snapshots also refresh the UI after an independent destination media reset.
module ui_state_bridge #(parameter integer WIDTH=9)(
    input wire source_clk,source_reset_n,
    input wire [WIDTH-1:0] source_data,
    input wire destination_clk,destination_reset_n,
    output reg [WIDTH-1:0] destination_data
);
    reg [WIDTH-1:0] mailbox;
    reg request,ack;
    (* async_reg="true" *) reg [2:0] ack_sync,request_sync;
    always @(posedge source_clk or negedge source_reset_n)begin
        if(!source_reset_n)begin mailbox<=0;request<=0;ack_sync<=0;end
        else begin
            ack_sync<={ack_sync[1:0],ack};
            if(ack_sync[2]==request)begin mailbox<=source_data;request<=~request;end
        end
    end
    always @(posedge destination_clk or negedge destination_reset_n)begin
        if(!destination_reset_n)begin destination_data<=0;request_sync<=0;ack<=0;end
        else begin
            request_sync<={request_sync[1:0],request};
            if(request_sync[2]!=ack)begin
                destination_data<=mailbox;ack<=request_sync[2];
            end
        end
    end
endmodule
