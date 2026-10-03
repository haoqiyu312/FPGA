// Read-only FAT32 root-directory BMP loader. Supports fragmented cluster chains.
// Supported images: 640x480, positive height (bottom-up), RGB24, BI_RGB.
// Sector interface is independent of the board-specific SD SPI transport.
module fat32_bmp_loader #(
    parameter integer WATCHDOG_BITS = 28,
    parameter integer SELECT_BY_NAME = 0,
    parameter integer AUTO_SCAN = 0
)(
    input wire clk, input wire rst,
    input wire sd_ready, input wire memory_ready,
    output reg sector_req, output reg [31:0] sector_lba,
    input wire [7:0] sector_byte, input wire sector_valid, input wire sector_end,
    output reg write_req, input wire write_ack,
    output reg pixel_valid, output reg [31:0] pixel_data,
    input wire write_finish_toggle,
    output reg image_ready, output reg [3:0] status,
    input wire [4:0] image_index,
    output reg [5:0] image_total, output reg catalog_valid,
    output reg [87:0] image_name // FAT short name, eight basename + three extension bytes
);
    localparam WAIT_READY=0, REQUEST=1, RECEIVE=2, DECIDE=3,
               BEGIN_WRITE=4, WAIT_COMMIT=5, DONE=6, ERROR=7, SCAN_FINISH=8;
    localparam MBR=0, BPB=1, DIRECTORY=2, FILE_DATA=3, FAT_ENTRY=4, SCAN_HEADER=5;
    reg [3:0] state;
    reg [2:0] kind;
    reg fat_for_file;
    reg [8:0] byte_index;
    reg [31:0] volume_lba, partition_lba, fat_lba, data_lba;
    reg [7:0] partition_type, sectors_per_cluster, fat_count;
    reg [3:0] cluster_shift;
    reg [15:0] bytes_per_sector, reserved_sectors, signature;
    reg [31:0] fat_sectors, root_cluster, current_cluster, next_cluster;
    reg [7:0] cluster_sector;
    reg [15:0] chain_hops;
    reg entry_live, extension_b, extension_m, extension_p;
    reg name_matches;
    reg [7:0] entry_attr;
    reg [31:0] entry_cluster, entry_size;
    reg found_file, directory_end;
    // Enumerate valid BMP headers without buffering directory sectors. After
    // probing a candidate, reread its directory sector and resume after it.
    reg [31:0] catalog_cluster[0:31],catalog_size[0:31];
    reg [87:0] entry_name,candidate_name,catalog_name[0:31];
    reg [31:0] directory_lba;
    reg [8:0] resume_byte;
    reg resume_valid;
    wire entry_after_resume = !resume_valid || byte_index>resume_byte;
    reg [31:0] first_cluster, file_size;
    reg [31:0] file_position, pixel_offset, dib_size, bmp_width, bmp_height;
    reg [15:0] bmp_magic, bmp_planes, bmp_bits;
    reg [31:0] bmp_compression;
    reg [18:0] pixel_count;
    reg [1:0] component;
    reg [7:0] blue_byte, green_byte;
    reg [2:0] finish_sync;
    reg memory_done;
    reg header_valid; // Validate once; keep header arithmetic out of the pixel enable path.
    reg [WATCHDOG_BITS-1:0] watchdog;
    wire [8:0] fat_byte_offset = {current_cluster[6:0],2'b00};
    wire header_ok = bmp_magic==16'h4d42 && dib_size>=40 &&
        bmp_width==640 && bmp_height==480 && bmp_planes==1 &&
        bmp_bits==24 && bmp_compression==0 && pixel_offset>=54 &&
        pixel_offset<=file_size && (file_size-pixel_offset)>=921600;
    wire valid_cluster_size = sectors_per_cluster==1 || sectors_per_cluster==2 ||
        sectors_per_cluster==4 || sectors_per_cluster==8 || sectors_per_cluster==16 ||
        sectors_per_cluster==32 || sectors_per_cluster==64 || sectors_per_cluster==128;
    function [31:0] cluster_address;
        input [31:0] cluster;
        begin cluster_address=data_lba+((cluster-2)<<cluster_shift); end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state<=WAIT_READY; kind<=MBR; status<=0; image_ready<=0;
            image_total<=0; catalog_valid<=0;image_name<={11{8'h20}};
            entry_name<=0;candidate_name<=0; directory_lba<=0;resume_byte<=0;resume_valid<=0;
            sector_req<=0; sector_lba<=0; write_req<=0; pixel_valid<=0; pixel_data<=0;
            byte_index<=0; volume_lba<=0; partition_lba<=0; partition_type<=0;
            fat_lba<=0; data_lba<=0; sectors_per_cluster<=0; fat_count<=0;
            cluster_shift<=0; bytes_per_sector<=0; reserved_sectors<=0;
            signature<=0; fat_sectors<=0; root_cluster<=0; current_cluster<=0;
            next_cluster<=0; cluster_sector<=0; chain_hops<=0; fat_for_file<=0;
            name_matches<=0; entry_live<=0; extension_b<=0; extension_m<=0; extension_p<=0;
            entry_attr<=0; entry_cluster<=0; entry_size<=0;
            found_file<=0; directory_end<=0; first_cluster<=0; file_size<=0;
            file_position<=0; pixel_offset<=0; dib_size<=0; bmp_width<=0; bmp_height<=0;
            bmp_magic<=0; bmp_planes<=0; bmp_bits<=0; bmp_compression<=0;
            pixel_count<=0; component<=0; blue_byte<=0; green_byte<=0;
            finish_sync<=0; memory_done<=0; watchdog<=0; header_valid<=0;
        end else begin
            sector_req<=0; pixel_valid<=0;
            finish_sync<={finish_sync[1:0],write_finish_toggle};
            if (finish_sync[2]^finish_sync[1]) memory_done<=1;
            if (sector_valid || (!AUTO_SCAN && state==WAIT_READY) || state==DONE || state==ERROR)
                watchdog<=0;
            else watchdog<=watchdog+1'b1;

            case (state)
                WAIT_READY: if (sd_ready && memory_ready) begin
                    status<=1; sector_lba<=0; kind<=MBR; state<=REQUEST;
                end
                REQUEST: begin sector_req<=1; byte_index<=0; state<=RECEIVE; end
                RECEIVE: begin
                    if (sector_valid) begin
                        byte_index<=byte_index+1'b1;
                        if (kind==MBR || kind==BPB) begin
                            case (byte_index)
                                11: bytes_per_sector[7:0]<=sector_byte;
                                12: bytes_per_sector[15:8]<=sector_byte;
                                13: sectors_per_cluster<=sector_byte;
                                14: reserved_sectors[7:0]<=sector_byte;
                                15: reserved_sectors[15:8]<=sector_byte;
                                16: fat_count<=sector_byte;
                                36: fat_sectors[7:0]<=sector_byte;
                                37: fat_sectors[15:8]<=sector_byte;
                                38: fat_sectors[23:16]<=sector_byte;
                                39: fat_sectors[31:24]<=sector_byte;
                                44: root_cluster[7:0]<=sector_byte;
                                45: root_cluster[15:8]<=sector_byte;
                                46: root_cluster[23:16]<=sector_byte;
                                47: root_cluster[31:24]<=sector_byte;
                                450: partition_type<=sector_byte;
                                454: partition_lba[7:0]<=sector_byte;
                                455: partition_lba[15:8]<=sector_byte;
                                456: partition_lba[23:16]<=sector_byte;
                                457: partition_lba[31:24]<=sector_byte;
                                510: signature[7:0]<=sector_byte;
                                511: signature[15:8]<=sector_byte;
                            endcase
                        end
                        if (kind==DIRECTORY) begin
                            if(byte_index[4:0]<=10)entry_name[87-byte_index[4:0]*8 -: 8]<=sector_byte;
                            case (byte_index[4:0])
                                0: begin
                                    name_matches<=sector_byte=="P";
                                    entry_live<=sector_byte!=0 && sector_byte!=8'he5;
                                    if (sector_byte==0 && entry_after_resume) directory_end<=1;
                                    entry_cluster<=0; entry_size<=0;
                                end
                                1: name_matches<=name_matches && sector_byte=="I";
                                2: name_matches<=name_matches && sector_byte=="C";
                                3: name_matches<=name_matches && sector_byte=="0";
                                4: name_matches<=name_matches && sector_byte==(8'h31+{3'b0,image_index});
                                5,6,7: name_matches<=name_matches && sector_byte==" ";
                                8: extension_b<=sector_byte=="B" || sector_byte=="b";
                                9: extension_m<=sector_byte=="M" || sector_byte=="m";
                                10: extension_p<=sector_byte=="P" || sector_byte=="p";
                                11: entry_attr<=sector_byte;
                                20: entry_cluster[23:16]<=sector_byte;
                                21: entry_cluster[31:24]<=sector_byte;
                                26: entry_cluster[7:0]<=sector_byte;
                                27: entry_cluster[15:8]<=sector_byte;
                                28: entry_size[7:0]<=sector_byte;
                                29: entry_size[15:8]<=sector_byte;
                                30: entry_size[23:16]<=sector_byte;
                                31: if (!found_file && !directory_end && entry_live &&
                                     (!AUTO_SCAN || entry_after_resume) &&
                                     extension_b && extension_m && extension_p &&
                                     (AUTO_SCAN || !SELECT_BY_NAME || name_matches) &&
                                     (entry_attr&8'h18)==0 && entry_cluster>=2 &&
                                     {sector_byte,entry_size[23:0]}>=921654) begin
                                    found_file<=1; first_cluster<=entry_cluster;candidate_name<=entry_name;
                                    file_size<={sector_byte,entry_size[23:0]};
                                    if(AUTO_SCAN) begin resume_byte<=byte_index;resume_valid<=1;directory_lba<=sector_lba;end
                                end
                            endcase
                        end
                        if (kind==FAT_ENTRY) begin
                            if (byte_index==fat_byte_offset) next_cluster[7:0]<=sector_byte;
                            if (byte_index==fat_byte_offset+1) next_cluster[15:8]<=sector_byte;
                            if (byte_index==fat_byte_offset+2) next_cluster[23:16]<=sector_byte;
                            if (byte_index==fat_byte_offset+3) next_cluster[31:24]<={4'b0,sector_byte[3:0]};
                        end
                        if (kind==FILE_DATA || kind==SCAN_HEADER) begin
                            file_position<=file_position+1'b1;
                            case (file_position)
                                0: bmp_magic[7:0]<=sector_byte;
                                1: bmp_magic[15:8]<=sector_byte;
                                10: pixel_offset[7:0]<=sector_byte;
                                11: pixel_offset[15:8]<=sector_byte;
                                12: pixel_offset[23:16]<=sector_byte;
                                13: pixel_offset[31:24]<=sector_byte;
                                14: dib_size[7:0]<=sector_byte;
                                15: dib_size[15:8]<=sector_byte;
                                16: dib_size[23:16]<=sector_byte;
                                17: dib_size[31:24]<=sector_byte;
                                18: bmp_width[7:0]<=sector_byte;
                                19: bmp_width[15:8]<=sector_byte;
                                20: bmp_width[23:16]<=sector_byte;
                                21: bmp_width[31:24]<=sector_byte;
                                22: bmp_height[7:0]<=sector_byte;
                                23: bmp_height[15:8]<=sector_byte;
                                24: bmp_height[23:16]<=sector_byte;
                                25: bmp_height[31:24]<=sector_byte;
                                26: bmp_planes[7:0]<=sector_byte;
                                27: bmp_planes[15:8]<=sector_byte;
                                28: bmp_bits[7:0]<=sector_byte;
                                29: bmp_bits[15:8]<=sector_byte;
                                30: bmp_compression[7:0]<=sector_byte;
                                31: bmp_compression[15:8]<=sector_byte;
                                32: bmp_compression[23:16]<=sector_byte;
                                33: bmp_compression[31:24]<=sector_byte;
                            endcase
                            if (kind==FILE_DATA && file_position==54) begin
                                header_valid<=header_ok;
                                if (!header_ok) begin state<=ERROR; status<=12; end
                            end
                            if (kind==FILE_DATA && file_position>=pixel_offset && file_position>=54 &&
                                pixel_count<307200 && (header_valid || file_position==54)) begin
                                case (component)
                                    0: begin blue_byte<=sector_byte; component<=1; end
                                    1: begin green_byte<=sector_byte; component<=2; end
                                    2: begin
                                        pixel_data<={sector_byte,green_byte,blue_byte,8'b0};
                                        pixel_valid<=1; component<=0;
                                        pixel_count<=pixel_count+1'b1;
                                    end
                                endcase
                            end
                        end
                    end
                    if (sector_end) state<=DECIDE;
                end
                DECIDE: begin
                    case (kind)
                        MBR: if (signature!=16'haa55) begin state<=ERROR; status<=10; end
                             else if (bytes_per_sector==512 && valid_cluster_size && root_cluster>=2)
                                 begin kind<=BPB; state<=DECIDE; end
                             else if (partition_lba!=0 &&
                                      (partition_type==8'h0b || partition_type==8'h0c ||
                                       partition_type==8'h1b || partition_type==8'h1c)) begin
                                 volume_lba<=partition_lba; sector_lba<=partition_lba;
                                 kind<=BPB; state<=REQUEST;
                             end else begin state<=ERROR; status<=10; end
                        BPB: if (signature!=16'haa55 || bytes_per_sector!=512 ||
                                 !valid_cluster_size || reserved_sectors==0 || fat_sectors==0 ||
                                 (fat_count!=1 && fat_count!=2) || root_cluster<2) begin
                                 state<=ERROR; status<=10;
                             end else begin
                                 fat_lba<=volume_lba+reserved_sectors;
                                 data_lba<=volume_lba+reserved_sectors+
                                           (fat_count==2 ? (fat_sectors<<1) : fat_sectors);
                                 case (sectors_per_cluster)
                                     1:cluster_shift<=0; 2:cluster_shift<=1; 4:cluster_shift<=2;
                                     8:cluster_shift<=3; 16:cluster_shift<=4; 32:cluster_shift<=5;
                                     64:cluster_shift<=6; 128:cluster_shift<=7;
                                 endcase
                                 current_cluster<=root_cluster; cluster_sector<=0;
                                 // Address uses new geometry on the following BEGIN_WRITE branch.
                                 status<=2; state<=BEGIN_WRITE;
                             end
                        DIRECTORY: if (found_file) begin
                                 if(AUTO_SCAN) begin
                                     // Geometry/current directory cluster stay intact during the probe.
                                     kind<=SCAN_HEADER;sector_lba<=cluster_address(first_cluster);
                                     file_position<=0;bmp_magic<=0;pixel_offset<=0;dib_size<=0;
                                     bmp_width<=0;bmp_height<=0;bmp_planes<=0;bmp_bits<=0;
                                     bmp_compression<=0;directory_end<=0;state<=REQUEST;
                                 end else begin
                                     current_cluster<=first_cluster; cluster_sector<=0;
                                     file_position<=0; status<=3; write_req<=1; state<=BEGIN_WRITE;
                                 end
                             end else if (directory_end) begin
                                 if(AUTO_SCAN) state<=SCAN_FINISH;
                                 else begin state<=ERROR;status<=11;end
                             end else if (cluster_sector+1<sectors_per_cluster) begin
                                 cluster_sector<=cluster_sector+1'b1;resume_valid<=0;
                                 sector_lba<=sector_lba+1'b1; state<=REQUEST;
                             end else begin
                                 sector_lba<=fat_lba+(current_cluster>>7);resume_valid<=0;
                                 fat_for_file<=0; kind<=FAT_ENTRY; state<=REQUEST;
                             end
                        SCAN_HEADER: begin
                             if(header_ok) begin
                                 catalog_cluster[image_total[4:0]]<=first_cluster;
                                 catalog_size[image_total[4:0]]<=file_size;
                                 catalog_name[image_total[4:0]]<=candidate_name;
                                 image_total<=image_total+1'b1;
                             end
                             found_file<=0;directory_end<=0;
                             if(header_ok && image_total==31) state<=SCAN_FINISH;
                             else begin kind<=DIRECTORY;sector_lba<=directory_lba;state<=REQUEST;end
                         end
                        FILE_DATA: if (pixel_count==307200) begin
                                 status<=4; state<=WAIT_COMMIT;
                             end else if (file_position>=file_size) begin state<=ERROR; status<=12; end
                             else if (cluster_sector+1<sectors_per_cluster) begin
                                 cluster_sector<=cluster_sector+1'b1;
                                 sector_lba<=sector_lba+1'b1; state<=REQUEST;
                             end else begin
                                 sector_lba<=fat_lba+(current_cluster>>7);
                                 fat_for_file<=1; kind<=FAT_ENTRY; state<=REQUEST;
                             end
                        FAT_ENTRY: if (AUTO_SCAN && !fat_for_file && next_cluster>=32'h0ffffff8)
                                 state<=SCAN_FINISH;
                             else if (next_cluster<2 || next_cluster>=32'h0ffffff0 ||
                                       next_cluster==current_cluster || chain_hops==65535) begin
                                 state<=ERROR; status<=13;
                             end else begin
                                 current_cluster<=next_cluster; cluster_sector<=0;resume_valid<=0;
                                 chain_hops<=chain_hops+1'b1;
                                 sector_lba<=cluster_address(next_cluster);
                                 kind<=fat_for_file ? FILE_DATA : DIRECTORY; state<=REQUEST;
                             end
                    endcase
                end
                SCAN_FINISH: begin
                    catalog_valid<=1;
                    if(image_total==0) begin status<=11;state<=ERROR;end
                    else begin
                        // Clamp stale/out-of-range selection after a card contents change.
                        first_cluster<=catalog_cluster[image_index<image_total ? image_index : 5'd0];
                        current_cluster<=catalog_cluster[image_index<image_total ? image_index : 5'd0];
                        file_size<=catalog_size[image_index<image_total ? image_index : 5'd0];
                        image_name<=catalog_name[image_index<image_total ? image_index : 5'd0];
                        cluster_sector<=0;chain_hops<=0;file_position<=0;
                        bmp_magic<=0;pixel_offset<=0;dib_size<=0;bmp_width<=0;bmp_height<=0;
                        bmp_planes<=0;bmp_bits<=0;bmp_compression<=0;header_valid<=0;
                        found_file<=1;status<=3;write_req<=1;state<=BEGIN_WRITE;
                    end
                end
                BEGIN_WRITE: if (!found_file) begin
                        sector_lba<=cluster_address(current_cluster);
                        kind<=DIRECTORY; state<=REQUEST;
                    end else if (write_ack) begin
                        write_req<=0; sector_lba<=cluster_address(current_cluster);
                        if(!AUTO_SCAN)image_name<=candidate_name;
                        kind<=FILE_DATA; state<=REQUEST;
                    end
                WAIT_COMMIT: if (memory_done) begin image_ready<=1; status<=5; state<=DONE; end
                DONE: state<=DONE;
                ERROR: begin state<=ERROR; write_req<=0; end
                default: begin state<=ERROR; status<=15; end
            endcase
            if (&watchdog && state!=DONE && state!=ERROR && (AUTO_SCAN || state!=WAIT_READY)) begin
                state<=ERROR; status<=14; write_req<=0;
            end
        end
    end
endmodule
