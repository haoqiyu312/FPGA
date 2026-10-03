// Automatically indexed FAT32/BMP -> embedded SDRAM -> existing video transmitter.
// KEY1(A2) is reset. Both HDMI ports show the same image; no audio in this step.
module tf_image_top (
    input wire sys_clk, input wire sys_rst_n,
    input wire key_next_n, key_prev_n, key_auto_n,
    input wire [1:0] interval_switch,
    input wire direction_switch,
    output wire [7:0] seg_n,digit_en,
    output wire buzzer_n,
    output wire HDMI_CLK_P, HDMI_D0_P, HDMI_D1_P, HDMI_D2_P,
    output wire HDMI_CLK_P1, HDMI_D0_P1, HDMI_D1_P1, HDMI_D2_P1,
    output wire sd_ncs, sd_dclk, sd_mosi, input wire sd_miso
);
    key_beeper u_key_beeper (.clk(sys_clk),
        .keys_n({key_auto_n,key_prev_n,key_next_n,sys_rst_n}),.buzzer_n(buzzer_n));
    wire pixel_clk, serial_clk, video_lock;
    wire sd_clk, mem_clk, mem_clk_shift, memory_lock;
    video_pll u_video_pll (.refclk(sys_clk),.reset(~sys_rst_n),
        .extlock(video_lock),.clk0_out(serial_clk),.clk1_out(pixel_clk));
    sys_pll u_memory_pll (.refclk(sys_clk),.reset(~sys_rst_n),
        .extlock(memory_lock),.clk0_out(sd_clk),.clk1_out(mem_clk),.clk2_out(mem_clk_shift));

    wire [3:0] load_status;
    wire image_ready;
    wire [4:0] image_index;
    wire [5:0] catalog_total;
    wire catalog_valid;
    wire [87:0] image_name;
    reg [5:0] image_total=0,total_meta=0,total_sync=0;
    reg [1:0] catalog_sync=0;
    wire [1:0] stable_interval;
    wire stable_direction;
    // Catalog size is published only after the full scan; hold it during reloads.
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n)begin image_total<=0;total_meta<=0;total_sync<=0;catalog_sync<=0;end
        else begin
            total_meta<=catalog_total;total_sync<=total_meta;
            catalog_sync<={catalog_sync[0],catalog_valid};
            if(catalog_sync[1])image_total<=total_sync;
        end
    end
    wire run_reset_n;
    wire auto_mode;
    reg show_image;
    image_key_control u_image_keys (.clk(sys_clk),.reset_n(sys_rst_n),
        .image_ready(show_image),.key_next_n(key_next_n),.key_prev_n(key_prev_n),
        .key_auto_n(key_auto_n),.interval_switch(interval_switch),.auto_mode(auto_mode),
        .direction_switch(direction_switch),.image_total(image_total),
        .stable_interval(stable_interval),.stable_direction(stable_direction),
        .image_index(image_index),.run_reset_n(run_reset_n));
    image_number_display u_image_number (.clk(sys_clk),.reset_n(sys_rst_n),
        .image_index(image_index),.total_count(image_total),.seg_n(seg_n),.digit_en(digit_en));
    wire startup_done;
    reg [1:0] ready_sys_sync=0;
    reg has_loaded=0,video_started=0;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin ready_sys_sync<=0;has_loaded<=0;video_started<=0;end
        else begin
            ready_sys_sync<={ready_sys_sync[0],image_ready};
            if(ready_sys_sync[1]) has_loaded<=1;
            if(!video_lock || !memory_lock) video_started<=0;
            else if(startup_done) video_started<=1;
        end
    end
    reg [1:0] load_error_sync=0;
    always @(posedge sys_clk or negedge sys_rst_n)
        if(!sys_rst_n) load_error_sync<=0;
        else load_error_sync<={load_error_sync[0],load_status>=10};
    tf_startup_control u_startup (.clk(sys_clk),.reset_n(run_reset_n),
        .locked(video_lock & memory_lock),.load_error(load_error_sync[1]),
        .run_enable(startup_done),.fast_start(has_loaded));
    wire ready_clock=sys_rst_n & startup_done & video_lock & memory_lock;
    // Asynchronous assertion, three-clock synchronous release per domain.
    // tf_image.sdc exempts only asynchronous requests entering these synchronizers.
    reg [2:0] sd_reset_pipe=0,mem_reset_pipe=0,video_reset_pipe=0;
    always @(posedge sd_clk or negedge ready_clock)
        if(!ready_clock) sd_reset_pipe<=0;else sd_reset_pipe<={sd_reset_pipe[1:0],1'b1};
    always @(posedge mem_clk or negedge ready_clock)
        if(!ready_clock) mem_reset_pipe<=0;else mem_reset_pipe<={mem_reset_pipe[1:0],1'b1};
    wire video_ready=sys_rst_n & video_started & video_lock & memory_lock;
    always @(posedge pixel_clk or negedge video_ready)
        if(!video_ready) video_reset_pipe<=0;else video_reset_pipe<={video_reset_pipe[1:0],1'b1};
    wire sd_rst=~sd_reset_pipe[2], mem_rst=~mem_reset_pipe[2], video_rst=~video_reset_pipe[2];

    wire sector_req,sector_valid,sector_end,sd_ready;
    wire [31:0] sector_lba;
    wire [7:0] sector_byte;
    sd_card_top #(.SPI_LOW_SPEED_DIV(123),.SPI_HIGH_SPEED_DIV(0)) u_sd_transport (
        .clk(sd_clk),.rst(sd_rst),.SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),
        .SD_MOSI(sd_mosi),.SD_MISO(sd_miso),.sd_init_done(sd_ready),
        .sd_sec_read(sector_req),.sd_sec_read_addr(sector_lba),
        .sd_sec_read_data(sector_byte),.sd_sec_read_data_valid(sector_valid),
        .sd_sec_read_end(sector_end),.sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),
        .sd_sec_write_data(8'd0),.sd_sec_write_data_req(),.sd_sec_write_end());

    wire memory_initialized,memory_refresh,memory_busy;
    reg [1:0] memory_init_sync;
    always @(posedge sd_clk or posedge sd_rst)
        if(sd_rst) memory_init_sync<=0;
        else memory_init_sync<={memory_init_sync[0],memory_initialized};
    wire write_req,write_ack,pixel_valid,write_finish;
    reg [2:0] write_ack_sync;
    always @(posedge sd_clk or posedge sd_rst)
        if(sd_rst) write_ack_sync<=0;
        else write_ack_sync<={write_ack_sync[1:0],write_ack};
    wire [31:0] pixel_data;
    reg finish_toggle;
    always @(posedge mem_clk or posedge mem_rst)
        if(mem_rst) finish_toggle<=0;
        else if(write_finish) finish_toggle<=~finish_toggle;
    fat32_bmp_loader #(.AUTO_SCAN(1)) u_loader (
        .clk(sd_clk),.rst(sd_rst),.sd_ready(sd_ready),.memory_ready(memory_init_sync[1]),
        .sector_req(sector_req),.sector_lba(sector_lba),.sector_byte(sector_byte),
        .sector_valid(sector_valid),.sector_end(sector_end),
        .write_req(write_req),.write_ack(write_ack_sync[2]),.pixel_valid(pixel_valid),
        .pixel_data(pixel_data),.write_finish_toggle(finish_toggle),
        .image_ready(image_ready),.status(load_status),.image_index(image_index),
        .image_total(catalog_total),.catalog_valid(catalog_valid),.image_name(image_name));

    wire [9:0] x,y;
    wire de,hs,vs;
    video_timing_640x480 u_timing (.pixel_clk(pixel_clk),.rst_n(~video_rst),
        .pixel_x(x),.pixel_y(y),.de(de),.hsync(hs),.vsync(vs));
    reg [2:0] image_sync,ack_sync;
    wire read_ack;
    reg read_req,frame_primed;
    always @(posedge pixel_clk or posedge video_rst) begin
        if(video_rst) begin
            image_sync<=0;ack_sync<=0;read_req<=0;frame_primed<=0;show_image<=0;
        end else begin
            image_sync<={image_sync[1:0],image_ready};
            ack_sync<={ack_sync[1:0],read_ack};
            // Refill/reset the read FIFO in vertical blanking, never mid-frame.
            if(!image_sync[2]) begin
                read_req<=0;frame_primed<=0;show_image<=0;
            end else if(x==0 && y==480) read_req<=1;
            else if(ack_sync[2]) begin read_req<=0;frame_primed<=1;end
            if(x==0 && y==0 && frame_primed && image_sync[2]) show_image<=1;
        end
    end
    wire fifo_read_en,delayed_de,delayed_hs,delayed_vs;
    wire [31:0] fifo_pixel;
    wire [23:0] image_rgb;
    video_delay u_read_latency (.video_clk(pixel_clk),.rst(video_rst),
        .read_en(fifo_read_en),.read_data(fifo_pixel[31:8]),.hs(hs),.vs(vs),.de(de),
        .hs_r(delayed_hs),.vs_r(delayed_vs),.de_r(delayed_de),.vout_data(image_rgb));

    wire app_rd_en,sdram_rd_valid,app_wr_en;
    wire [20:0] app_rd_addr,app_wr_addr;
    wire [31:0] sdram_rd_data,app_wr_data;
    wire [3:0] app_wr_mask;
    // 128 divides 640: BMP row flips occur between bursts, never inside one.
    frame_read_write #(.BURST_SIZE(128),.WRITE_V_FLIP(1),.FRAME_WIDTH(640),.FRAME_HEIGHT(480)) u_frame (
        .rst(mem_rst),.mem_clk(mem_clk),.Sdr_init_done(memory_initialized),
        .Sdr_init_ref_vld(memory_refresh),.Sdr_busy(memory_busy),
        .App_rd_en(app_rd_en),.App_rd_addr(app_rd_addr),
        .Sdr_rd_en(sdram_rd_valid),.Sdr_rd_dout(sdram_rd_data),
        .read_clk(pixel_clk),.read_req(read_req),.read_req_ack(read_ack),.read_finish(),
        .read_addr_0(21'd0),.read_addr_1(21'd0),.read_addr_2(21'd0),.read_addr_3(21'd0),
        .read_addr_index(2'd0),.read_len(21'd307200),
        .read_en(fifo_read_en & show_image),.read_data(fifo_pixel),
        .App_wr_en(app_wr_en),.App_wr_addr(app_wr_addr),.App_wr_din(app_wr_data),.App_wr_dm(app_wr_mask),
        .write_clk(sd_clk),.write_req(write_req),.write_req_ack(write_ack),.write_finish(write_finish),
        .write_addr_0(21'd0),.write_addr_1(21'd0),.write_addr_2(21'd0),.write_addr_3(21'd0),
        .write_addr_index(2'd0),.write_len(21'd307200),.write_en(pixel_valid),.write_data(pixel_data));
    sdram u_sdram (.Clk(mem_clk),.Clk_sft(mem_clk_shift),.Rst(mem_rst),
        .Sdr_init_done(memory_initialized),.Sdr_init_ref_vld(memory_refresh),.Sdr_busy(memory_busy),
        .App_wr_en(app_wr_en),.App_wr_addr(app_wr_addr),.App_wr_dm(app_wr_mask),.App_wr_din(app_wr_data),
        .App_rd_en(app_rd_en),.App_rd_addr(app_rd_addr),.Sdr_rd_en(sdram_rd_valid),.Sdr_rd_dout(sdram_rd_data));

    // Animate a spinner while loading; overlay persistent text on errors.
    // The multi-bit status is sampled twice, then latched at frame start.
    reg [3:0] status_meta,status_sync,status_frame;
    always @(posedge pixel_clk or posedge video_rst) begin
        if(video_rst) begin status_meta<=0;status_sync<=0;status_frame<=0;end
        else begin
            status_meta<=load_status;status_sync<=status_meta;
            if(x==0 && y==0) status_frame<=status_sync;
        end
    end
    wire [23:0] loading_rgb;
    loading_spinner_rgb u_loading_spinner (.pixel_clk(pixel_clk),.rst_n(~video_rst),
        .pixel_x(x),.pixel_y(y),.de(de),.rgb(loading_rgb));
    wire osd_cover;
    wire [23:0] osd_rgb;
    image_status_osd u_status_osd (.pixel_clk(pixel_clk),.rst_n(~video_rst),
        .x(x),.y(y),.de(de),.image_shown(show_image),.load_status(load_status),
        .image_index(image_index),.image_total(image_total),.auto_mode(auto_mode),
        .interval_setting(stable_interval),.reverse_direction(stable_direction),
        .overlay_active(osd_cover),.rgb(osd_rgb),.image_name(image_name));
    reg [19:0] osd_cover_delay;
    reg [23:0] osd_delay[0:19];
    reg [23:0] loading_delay[0:20];
    integer i;
    always @(posedge pixel_clk or posedge video_rst) begin
        if(video_rst) begin
            osd_cover_delay<=0;
            for(i=0;i<=20;i=i+1)loading_delay[i]<=0;
            for(i=0;i<20;i=i+1)osd_delay[i]<=0;
        end
        else begin
            loading_delay[0]<=status_frame>=10 ? 24'h000000 : loading_rgb;
            // The Chinese font contributes one clock; add twenty to total twenty-one.
            osd_cover_delay<={osd_cover_delay[18:0],osd_cover};
            osd_delay[0]<=osd_rgb;
            for(i=1;i<=20;i=i+1)loading_delay[i]<=loading_delay[i-1];
            for(i=1;i<20;i=i+1)osd_delay[i]<=osd_delay[i-1];
        end
    end
    wire [23:0] output_rgb=osd_cover_delay[19] ? osd_delay[19] : (show_image ? image_rgb : loading_delay[20]);
    hdmi_tx #(.FAMILY("EG4")) u_hdmi (.PXLCLK_I(pixel_clk),.PXLCLK_5X_I(serial_clk),
        .RST_N(~video_rst),.VGA_HS(delayed_hs),.VGA_VS(delayed_vs),
        .VGA_DE(delayed_de),.VGA_RGB(output_rgb),.HDMI_CLK_P(HDMI_CLK_P),
        .HDMI_D0_P(HDMI_D0_P),.HDMI_D1_P(HDMI_D1_P),.HDMI_D2_P(HDMI_D2_P));
    assign HDMI_CLK_P1=HDMI_CLK_P;
    assign HDMI_D0_P1=HDMI_D0_P;
    assign HDMI_D1_P1=HDMI_D1_P;
    assign HDMI_D2_P1=HDMI_D2_P;
endmodule
