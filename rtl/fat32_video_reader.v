// Read-only FAT32 VIDEO.RV stream; fragmented root and file chains are supported.
// RVF1: one 512-byte header followed by sector-aligned, top-down RGB332 frames.
module fat32_video_reader #(
    parameter integer WATCHDOG_BITS=28,
    parameter integer FRAME_PIXELS=307200
)(
    input wire clk,rst,sd_ready,memory_ready,
    output reg sector_req, output reg [31:0] sector_lba,
    input wire [7:0] sector_byte, input wire sector_valid,sector_end,
    output reg write_req, input wire write_ack,
    output reg pixel_valid, output reg [31:0] pixel_data,
    input wire write_finish_toggle,
    output reg frame_toggle, input wire consumed_toggle,
    output reg write_bank, output reg [3:0] status,
    output reg [7:0] fps
);
    localparam WAIT_READY=0,REQUEST=1,RECEIVE=2,DECIDE=3,START_WRITE=4,
        WAIT_WRITE=5,WAIT_COMMIT=6,WAIT_PRESENT=7,ADVANCE=8,FAILED=9,SEEK_DIRECTORY=10,CHECK_LENGTH=11;
    localparam BOOT=0,BPB=1,DIRECTORY=2,HEADER=3,DATA=4,FAT=5;
    reg [3:0] state;
    reg [2:0] kind,return_kind;
    reg [8:0] byte_index;
    reg [31:0] volume_lba,partition_lba,fat_lba,data_lba,fat_sectors;
    reg [15:0] bytes_per_sector,reserved_sectors,signature;
    reg [7:0] sectors_per_cluster,fat_count,partition_type,cluster_sector;
    reg [3:0] cluster_shift;
    reg [31:0] root_cluster,current_cluster,next_cluster,first_cluster,file_size;
    reg [31:0] entry_cluster,entry_size,chain_hops;
    reg [7:0] entry_attr;
    reg entry_live,name_match,found_file,directory_end;
    reg [31:0] magic,frame_count,frame_index,frame_bytes,pixel_count;
    reg [31:0] verify_bytes;
    reg [13:0] verify_frames;
    reg [15:0] width,height;
    reg [7:0] version,format_code,header_fps;
    reg [2:0] finish_sync,consumed_sync;
    reg memory_done;
    reg [WATCHDOG_BITS-1:0] watchdog;
    wire [8:0] fat_offset={current_cluster[6:0],2'b00};
    wire valid_cluster_size=sectors_per_cluster==1 || sectors_per_cluster==2 ||
        sectors_per_cluster==4 || sectors_per_cluster==8 || sectors_per_cluster==16 ||
        sectors_per_cluster==32 || sectors_per_cluster==64 || sectors_per_cluster==128;
    wire header_ok=magic==32'h31465652 && version==1 && format_code==1 &&
        width==640 && height==480 && header_fps>=1 && header_fps<=5 &&
        frame_bytes==FRAME_PIXELS && frame_count!=0 && file_size>=512 &&
        frame_count<=13981; // maximum number of 640x480 frames in a FAT32 file
    function [31:0] cluster_address;
        input [31:0] cluster;
        begin cluster_address=data_lba+((cluster-2)<<cluster_shift); end
    endfunction
    function [7:0] expected_name;
        input [4:0] index;
        begin case(index)
          0:expected_name="V";1:expected_name="I";2:expected_name="D";
          3:expected_name="E";4:expected_name="O";8:expected_name="R";
          9:expected_name="V";default:expected_name=" ";
        endcase end
    endfunction
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=WAIT_READY;kind<=BOOT;return_kind<=DIRECTORY;
            sector_req<=0;sector_lba<=0;byte_index<=0;
            volume_lba<=0;partition_lba<=0;fat_lba<=0;data_lba<=0;fat_sectors<=0;
            bytes_per_sector<=0;reserved_sectors<=0;signature<=0;
            sectors_per_cluster<=0;fat_count<=0;partition_type<=0;cluster_sector<=0;cluster_shift<=0;
            root_cluster<=0;current_cluster<=0;next_cluster<=0;first_cluster<=0;file_size<=0;
            entry_cluster<=0;entry_size<=0;chain_hops<=0;entry_attr<=0;
            entry_live<=0;name_match<=0;found_file<=0;directory_end<=0;
            verify_bytes<=0;verify_frames<=0;magic<=0;frame_count<=0;frame_index<=0;frame_bytes<=0;pixel_count<=0;
            width<=0;height<=0;version<=0;format_code<=0;header_fps<=0;fps<=5;
            finish_sync<=0;consumed_sync<=0;memory_done<=0;watchdog<=0;
            write_req<=0;pixel_valid<=0;pixel_data<=0;frame_toggle<=0;write_bank<=1;status<=0;
        end else begin
            sector_req<=0;pixel_valid<=0;
            finish_sync<={finish_sync[1:0],write_finish_toggle};
            consumed_sync<={consumed_sync[1:0],consumed_toggle};
            if(finish_sync[2]^finish_sync[1])memory_done<=1;
            // Paused presentation and a stopped player are intentional waits.
            if(sector_valid || state==WAIT_PRESENT || state==FAILED)watchdog<=0;
            else watchdog<=watchdog+1'b1;
            case(state)
              WAIT_READY: if(sd_ready && memory_ready) begin
                  sector_lba<=0;kind<=BOOT;status<=1;state<=REQUEST;
              end
              REQUEST: begin sector_req<=1;byte_index<=0;state<=RECEIVE;end
              RECEIVE: begin
                  if(sector_valid) begin
                      byte_index<=byte_index+1'b1;
                      if(kind==BOOT || kind==BPB)case(byte_index)
                        11:bytes_per_sector[7:0]<=sector_byte;12:bytes_per_sector[15:8]<=sector_byte;
                        13:sectors_per_cluster<=sector_byte;
                        14:reserved_sectors[7:0]<=sector_byte;15:reserved_sectors[15:8]<=sector_byte;
                        16:fat_count<=sector_byte;
                        36,37,38,39:fat_sectors[(byte_index-36)*8 +: 8]<=sector_byte;
                        44,45,46,47:root_cluster[(byte_index-44)*8 +: 8]<=sector_byte;
                        450:partition_type<=sector_byte;
                        454,455,456,457:partition_lba[(byte_index-454)*8 +: 8]<=sector_byte;
                        510:signature[7:0]<=sector_byte;511:signature[15:8]<=sector_byte;
                      endcase
                      if(kind==DIRECTORY)case(byte_index[4:0])
                        0:begin
                            entry_live<=sector_byte!=0 && sector_byte!=8'he5;
                            if(sector_byte==0)directory_end<=1;
                            name_match<=sector_byte=="V";entry_cluster<=0;entry_size<=0;
                        end
                        1,2,3,4,5,6,7,8,9,10:
                            name_match<=name_match && sector_byte==expected_name(byte_index[4:0]);
                        11:entry_attr<=sector_byte;
                        20:entry_cluster[23:16]<=sector_byte;21:entry_cluster[31:24]<={4'b0,sector_byte[3:0]};
                        26:entry_cluster[7:0]<=sector_byte;27:entry_cluster[15:8]<=sector_byte;
                        28:entry_size[7:0]<=sector_byte;29:entry_size[15:8]<=sector_byte;
                        30:entry_size[23:16]<=sector_byte;
                        31:if(!found_file && !directory_end && entry_live && name_match &&
                            (entry_attr&8'h18)==0 && entry_cluster>=2 && entry_cluster<32'h0ffffff0)begin
                            first_cluster<=entry_cluster;file_size<={sector_byte,entry_size[23:0]};found_file<=1;
                        end
                      endcase
                      if(kind==FAT)begin
                          if(byte_index==fat_offset)next_cluster[7:0]<=sector_byte;
                          if(byte_index==fat_offset+1)next_cluster[15:8]<=sector_byte;
                          if(byte_index==fat_offset+2)next_cluster[23:16]<=sector_byte;
                          if(byte_index==fat_offset+3)next_cluster[31:24]<={4'b0,sector_byte[3:0]};
                      end
                      if(kind==HEADER)case(byte_index)
                        0,1,2,3:magic[byte_index*8 +: 8]<=sector_byte;
                        4:version<=sector_byte;5:format_code<=sector_byte;6:header_fps<=sector_byte;
                        8:width[7:0]<=sector_byte;9:width[15:8]<=sector_byte;
                        10:height[7:0]<=sector_byte;11:height[15:8]<=sector_byte;
                        12,13,14,15:frame_count[(byte_index-12)*8 +: 8]<=sector_byte;
                        16,17,18,19:frame_bytes[(byte_index-16)*8 +: 8]<=sector_byte;
                      endcase
                      if(kind==DATA)begin
                          pixel_data<={sector_byte[7:5],sector_byte[7:5],sector_byte[7:6],
                              sector_byte[4:2],sector_byte[4:2],sector_byte[4:3],
                              sector_byte[1:0],sector_byte[1:0],sector_byte[1:0],sector_byte[1:0],8'b0};
                          pixel_valid<=1;pixel_count<=pixel_count+1'b1;
                      end
                  end
                  if(sector_end)state<=DECIDE;
              end
              DECIDE:case(kind)
                BOOT:if(signature!=16'haa55)begin status<=10;state<=FAILED;end
                     else if(bytes_per_sector==512 && valid_cluster_size && root_cluster>=2)begin
                         kind<=BPB;state<=DECIDE;
                     end else if(partition_lba!=0 && (partition_type==8'h0b || partition_type==8'h0c ||
                         partition_type==8'h1b || partition_type==8'h1c))begin
                         volume_lba<=partition_lba;sector_lba<=partition_lba;kind<=BPB;state<=REQUEST;
                     end else begin status<=10;state<=FAILED;end
                BPB:if(signature!=16'haa55 || bytes_per_sector!=512 || !valid_cluster_size ||
                    reserved_sectors==0 || fat_sectors==0 || (fat_count!=1 && fat_count!=2) ||
                    root_cluster<2 || root_cluster>=32'h0ffffff0)begin status<=10;state<=FAILED;end
                    else begin
                        fat_lba<=volume_lba+reserved_sectors;
                        data_lba<=volume_lba+reserved_sectors+(fat_count==2 ? fat_sectors<<1 : fat_sectors);
                        case(sectors_per_cluster)
                          1:cluster_shift<=0;2:cluster_shift<=1;4:cluster_shift<=2;8:cluster_shift<=3;
                          16:cluster_shift<=4;32:cluster_shift<=5;64:cluster_shift<=6;128:cluster_shift<=7;
                        endcase
                        current_cluster<=root_cluster;cluster_sector<=0;kind<=DIRECTORY;
                        state<=SEEK_DIRECTORY;status<=2;
                    end
                DIRECTORY:if(found_file)begin
                        current_cluster<=first_cluster;cluster_sector<=0;chain_hops<=0;
                        sector_lba<=cluster_address(first_cluster);kind<=HEADER;state<=REQUEST;
                    end else if(directory_end)begin status<=11;state<=FAILED;end
                    else begin return_kind<=DIRECTORY;state<=ADVANCE;end
                HEADER:if(!header_ok)begin status<=12;state<=FAILED;end
                    else begin
                        verify_bytes<=file_size-512;verify_frames<=frame_count[13:0];
                        fps<=header_fps;state<=CHECK_LENGTH;status<=3;
                    end
                DATA:if(pixel_count==FRAME_PIXELS)begin state<=WAIT_COMMIT;status<=4;end
                    else begin return_kind<=DATA;state<=ADVANCE;end
                FAT:if(next_cluster<2 || next_cluster>=32'h0ffffff0 || next_cluster==current_cluster ||
                    chain_hops>=file_size/512+65536)begin status<=13;state<=FAILED;end
                    else begin
                        current_cluster<=next_cluster;cluster_sector<=0;chain_hops<=chain_hops+1'b1;
                        sector_lba<=cluster_address(next_cluster);kind<=return_kind;state<=REQUEST;
                    end
              endcase
              // One subtraction per clock avoids a large combinational divider.
              CHECK_LENGTH:if(verify_frames==0)state<=START_WRITE;
                  else if(verify_bytes<FRAME_PIXELS)begin status<=12;state<=FAILED;end
                  else begin verify_bytes<=verify_bytes-FRAME_PIXELS;verify_frames<=verify_frames-1'b1;end
              START_WRITE:begin
                  write_req<=1;memory_done<=0;pixel_count<=0;state<=WAIT_WRITE;
              end
              WAIT_WRITE:if(write_ack)begin write_req<=0;return_kind<=DATA;state<=ADVANCE;end
              WAIT_COMMIT:if(memory_done)begin
                  frame_toggle<=~frame_toggle;state<=WAIT_PRESENT;status<=5;
              end
              WAIT_PRESENT:if(consumed_sync[2]==frame_toggle)begin
                  write_bank<=~write_bank;status<=3;
                  if(frame_index+1==frame_count)begin
                      // Re-read the header at the start of each loop (also handles a one-sector cluster).
                      current_cluster<=first_cluster;cluster_sector<=0;chain_hops<=0;frame_index<=0;
                      sector_lba<=cluster_address(first_cluster);kind<=HEADER;state<=REQUEST;
                  end else begin frame_index<=frame_index+1'b1;state<=START_WRITE;end
              end
              SEEK_DIRECTORY:begin sector_lba<=cluster_address(current_cluster);state<=REQUEST;end
              ADVANCE:begin
                  if(cluster_sector+1<sectors_per_cluster)begin
                      cluster_sector<=cluster_sector+1'b1;sector_lba<=sector_lba+1'b1;
                      kind<=return_kind;state<=REQUEST;
                  end else begin
                      sector_lba<=fat_lba+(current_cluster>>7);kind<=FAT;state<=REQUEST;
                  end
              end
              FAILED:write_req<=0;
              default:begin status<=15;state<=FAILED;end
            endcase
            if(&watchdog && state!=WAIT_PRESENT && state!=FAILED)begin
                status<=14;state<=FAILED;write_req<=0;
            end
        end
    end
endmodule
