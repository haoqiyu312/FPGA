// Shared FAT32 image/video player; KEY4 hold or KEY4+KEY2 switches mode.
// KEY1 resets to image mode. RVF2 soundtrack is sent over HDMI_B.
module tf_media_top (
    input wire sys_clk, input wire sys_rst_n,
    input wire key_next_n, key_prev_n, key_auto_n,
    input wire [1:0] interval_switch,
    input wire direction_switch,
    output wire [7:0] seg_n,digit_en,
    output wire buzzer_n,
    output wire HDMI_CLK_P, HDMI_D0_P, HDMI_D1_P, HDMI_D2_P,
    output wire HDMI_CLK_P1, HDMI_D0_P1, HDMI_D1_P1, HDMI_D2_P1,
    output wire HDMI_DDC_SCL, inout wire HDMI_DDC_SDA,
    output wire sd_ncs, sd_dclk, sd_mosi, input wire sd_miso,
    inout wire touch_scl,touch_sda
);
    // The board buzzer is active low; keep it disabled for all key presses.
    assign buzzer_n = 1'b1;
    wire pixel_clk, serial_clk, video_lock;
    wire sd_clk, mem_clk, mem_clk_shift, memory_lock;
    video_pll u_video_pll (.refclk(sys_clk),.reset(~sys_rst_n),
        .extlock(video_lock),.clk0_out(serial_clk),.clk1_out(pixel_clk));
    sys_pll u_memory_pll (.refclk(sys_clk),.reset(~sys_rst_n),
        .extlock(memory_lock),.clk0_out(sd_clk),.clk1_out(mem_clk),.clk2_out(mem_clk_shift));

    // Configuration-time reset also initializes the touch probe and full volume.
    reg [2:0] touch_reset_pipe=0;
    always @(posedge sys_clk or negedge sys_rst_n)
        if(!sys_rst_n) touch_reset_pipe<=0;
        else touch_reset_pipe<={touch_reset_pipe[1:0],1'b1};
    wire touch_reset_n=sys_rst_n & touch_reset_pipe[2];
    wire video_mode,physical_short,media_reset_n;
    wire touch_online,touch_fault,touch_action_valid;
    wire [2:0] touch_action,pressed_button;
    wire [9:0] touch_x,touch_y;
    touch_player_frontend u_touch (.clk(sys_clk),.reset_n(touch_reset_n),
        .menu_visible(1'b1),.video_mode(video_mode),.touch_scl(touch_scl),.touch_sda(touch_sda),
        .online(touch_online),.fault(touch_fault),.action_valid(touch_action_valid),
        .action(touch_action),.pressed_button(pressed_button),.touch_x(touch_x),.touch_y(touch_y));
    wire touch_event=touch_action_valid & media_reset_n;
    wire short_press=physical_short | (touch_event && touch_action==2);
    wire [3:0] volume_level;
    media_volume_control u_volume (.clk(sys_clk),.reset_n(touch_reset_n),
        .up_event(touch_event && touch_action==7),.down_event(touch_event && touch_action==6),
        .level(volume_level));
    media_key_control #(.EXTERNAL_ACTIONS(1),.CHORD_MODE(1)) u_media_keys (.clk(sys_clk),.reset_n(sys_rst_n),
        .key_auto_n(key_auto_n),.restart_n(key_next_n),.video_mode(video_mode),
        .short_press(physical_short),.media_reset_n(media_reset_n),
        .mode_event(touch_event && touch_action==1),.restart_event(touch_event && touch_action==5));
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
    always @(posedge sys_clk or negedge media_reset_n) begin
        if(!media_reset_n)begin image_total<=0;total_meta<=0;total_sync<=0;catalog_sync<=0;end
        else begin
            total_meta<=catalog_total;total_sync<=total_meta;
            catalog_sync<={catalog_sync[0],catalog_valid};
            if(catalog_sync[1])image_total<=total_sync;
        end
    end
    wire run_reset_n;
    wire auto_mode;
    wire show_image;
    reg show_picture;
    image_key_control #(.EXTERNAL_AUTO(1),.EXTERNAL_STEP(1)) u_image_keys (.clk(sys_clk),.reset_n(media_reset_n),
        .image_ready(show_image & ~video_mode),.key_next_n(key_next_n | video_mode),.key_prev_n(key_prev_n | video_mode),
        .key_auto_n(~(short_press & ~video_mode)),.interval_switch(interval_switch),.auto_mode(auto_mode),
        .direction_switch(direction_switch),.image_total(image_total),
        .stable_interval(stable_interval),.stable_direction(stable_direction),
        .image_index(image_index),.run_reset_n(run_reset_n),
        .next_event(touch_event && !video_mode && touch_action==4),
        .prev_event(touch_event && !video_mode && touch_action==3));
    wire [7:0] image_seg,image_digit,video_seg,video_digit;
    image_number_display u_image_number (.clk(sys_clk),.reset_n(media_reset_n),
        .image_index(image_index),.total_count(image_total),.seg_n(image_seg),.digit_en(image_digit));
    wire startup_done;
    reg [1:0] ready_sys_sync=0;
    reg has_loaded=0,video_started=0;
    always @(posedge sys_clk or negedge media_reset_n) begin
        if(!media_reset_n) begin ready_sys_sync<=0;has_loaded<=0;video_started<=0;end
        else begin
            ready_sys_sync<={ready_sys_sync[0],image_ready};
            if(ready_sys_sync[1]) has_loaded<=1;
            if(!video_lock || !memory_lock) video_started<=0;
            else if(startup_done) video_started<=1;
        end
    end
    reg [1:0] load_error_sync=0;
    always @(posedge sys_clk or negedge media_reset_n)
        if(!media_reset_n) load_error_sync<=0;
        else load_error_sync<={load_error_sync[0],load_status>=10};
    tf_startup_control u_startup (.clk(sys_clk),.reset_n(run_reset_n),
        .locked(video_lock & memory_lock),.load_error(load_error_sync[1]),
        .run_enable(startup_done),.fast_start(has_loaded));
    (* dont_touch="true" *) wire ready_clock=media_reset_n & startup_done & video_lock & memory_lock;
    // Asynchronous assertion, three-clock synchronous release per domain.
    // tf_media.sdc exempts only asynchronous requests entering these synchronizers.
    (* async_reg="true" *) reg [2:0] sd_reset_pipe=0,mem_reset_pipe=0,video_reset_pipe=0;
    always @(posedge sd_clk or negedge ready_clock)
        if(!ready_clock) sd_reset_pipe<=0;else sd_reset_pipe<={sd_reset_pipe[1:0],1'b1};
    always @(posedge mem_clk or negedge ready_clock)
        if(!ready_clock) mem_reset_pipe<=0;else mem_reset_pipe<={mem_reset_pipe[1:0],1'b1};
    // Image reloads keep HDMI running; video retries must also reset the
    // presenter so its bank/toggle state cannot outlive a reset reader.
    (* dont_touch="true" *) wire video_ready=media_reset_n & video_started &
        video_lock & memory_lock & (~video_mode | startup_done);
    always @(posedge pixel_clk or negedge video_ready)
        if(!video_ready) video_reset_pipe<=0;else video_reset_pipe<={video_reset_pipe[1:0],1'b1};
    wire sd_rst=~sd_reset_pipe[2], mem_rst=~mem_reset_pipe[2], video_rst=~video_reset_pipe[2];

    (* async_reg="true" *) reg [1:0] mode_sd=0,mode_mem=0,mode_pixel=0;
    always @(posedge sd_clk) mode_sd<={mode_sd[0],video_mode};
    always @(posedge mem_clk) mode_mem<={mode_mem[0],video_mode};
    always @(posedge pixel_clk) mode_pixel<={mode_pixel[0],video_mode};
    wire video_sd=mode_sd[1],video_mem=mode_mem[1],video_pixel=mode_pixel[1];
    wire image_rst=sd_rst | video_sd, movie_rst=sd_rst | ~video_sd;
    wire [3:0] image_status,movie_status;
    assign load_status=video_sd ? movie_status : image_status;
    wire [7:0] video_fps;
    wire audio_enabled,audio_write_valid;
    wire [13:0] audio_write_address;
    wire [7:0] audio_write_data;
    reg [3:0] status_meta_sys,status_sync_sys;
    reg [7:0] fps_meta_sys,fps_sync_sys;
    always @(posedge sys_clk or negedge media_reset_n)
        if(!media_reset_n)begin status_meta_sys<=0;status_sync_sys<=0;fps_meta_sys<=3;fps_sync_sys<=3;end
        else begin status_meta_sys<=movie_status;status_sync_sys<=status_meta_sys;
                   fps_meta_sys<=video_fps;fps_sync_sys<=fps_meta_sys;end
    image_number_display #(.RAW_INDEX(1)) u_movie_number (.clk(sys_clk),.reset_n(media_reset_n),
        .image_index({1'b0,status_sync_sys}),.total_count(fps_sync_sys[5:0]),
        .seg_n(video_seg),.digit_en(video_digit));
    assign seg_n=video_mode ? video_seg : image_seg;
    assign digit_en=video_mode ? video_digit : image_digit;
    wire img_sector_req,mov_sector_req,img_write_req,mov_write_req,img_pixel_valid,mov_pixel_valid;
    wire [31:0] img_sector_lba,mov_sector_lba,img_pixel_data,mov_pixel_data;
    wire write_bank,read_bank,frame_toggle,consumed_toggle;
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
    assign sector_req=video_sd ? mov_sector_req : img_sector_req;
    assign sector_lba=video_sd ? mov_sector_lba : img_sector_lba;
    assign write_req=video_sd ? mov_write_req : img_write_req;
    assign pixel_valid=video_sd ? mov_pixel_valid : img_pixel_valid;
    assign pixel_data=video_sd ? mov_pixel_data : img_pixel_data;
    fat32_bmp_loader #(.AUTO_SCAN(1)) u_loader (
        .clk(sd_clk),.rst(image_rst),.sd_ready(sd_ready),.memory_ready(memory_init_sync[1]),
        .sector_req(img_sector_req),.sector_lba(img_sector_lba),.sector_byte(sector_byte),
        .sector_valid(sector_valid),.sector_end(sector_end),
        .write_req(img_write_req),.write_ack(write_ack_sync[2]),.pixel_valid(img_pixel_valid),
        .pixel_data(img_pixel_data),.write_finish_toggle(finish_toggle),
        .image_ready(image_ready),.status(image_status),.image_index(image_index),
        .image_total(catalog_total),.catalog_valid(catalog_valid),.image_name(image_name));

    fat32_video_reader #(.AUDIO_SUPPORT(1)) u_movie_loader (
        .clk(sd_clk),.rst(movie_rst),.sd_ready(sd_ready),.memory_ready(memory_init_sync[1]),
        .sector_req(mov_sector_req),.sector_lba(mov_sector_lba),.sector_byte(sector_byte),
        .sector_valid(sector_valid),.sector_end(sector_end),
        .write_req(mov_write_req),.write_ack(write_ack_sync[2]),.pixel_valid(mov_pixel_valid),
        .pixel_data(mov_pixel_data),.write_finish_toggle(finish_toggle),
        .frame_toggle(frame_toggle),.consumed_toggle(consumed_toggle),
        .write_bank(write_bank),.status(movie_status),.fps(video_fps),
        .audio_enabled(audio_enabled),.audio_valid(audio_write_valid),
        .audio_address(audio_write_address),.audio_data(audio_write_data));
    wire [9:0] x,y;
    wire de,hs,vs;
    video_timing_640x480 u_timing (.pixel_clk(pixel_clk),.rst_n(~video_rst),
        .pixel_x(x),.pixel_y(y),.de(de),.hsync(hs),.vsync(vs));
    reg [2:0] image_sync,ack_sync;
    wire read_ack;
    reg image_read_req,frame_primed;
    wire movie_read_req,movie_shown;
    wire read_req=video_pixel ? movie_read_req : image_read_req;
    assign show_image=video_pixel ? movie_shown : show_picture;
    always @(posedge pixel_clk or posedge video_rst) begin
        if(video_rst) begin
            image_sync<=0;ack_sync<=0;image_read_req<=0;frame_primed<=0;show_picture<=0;
        end else if(video_pixel) begin
            image_sync<=0;ack_sync<=0;image_read_req<=0;frame_primed<=0;show_picture<=0;
        end else begin
            image_sync<={image_sync[1:0],image_ready};
            ack_sync<={ack_sync[1:0],read_ack};
            // Refill/reset the read FIFO in vertical blanking, never mid-frame.
            if(!image_sync[2]) begin
                image_read_req<=0;frame_primed<=0;show_picture<=0;
            end else if(x==0 && y==480) image_read_req<=1;
            else if(ack_sync[2]) begin image_read_req<=0;frame_primed<=1;end
            if(x==0 && y==0 && frame_primed && image_sync[2]) show_picture<=1;
        end
    end
    // Short events cross into pixel clock with a toggle, never as a one-cycle pulse.
    reg pause_toggle=0;
    always @(posedge sys_clk or negedge media_reset_n)
        if(!media_reset_n)pause_toggle<=0;
        else if(video_mode && short_press)pause_toggle<=~pause_toggle;
    reg [2:0] pause_sync;
    reg paused;
    always @(posedge pixel_clk or posedge video_rst)
        if(video_rst)begin pause_sync<=0;paused<=0;end
        else begin
            pause_sync<={pause_sync[1:0],pause_toggle};
            if(pause_sync[2]!=pause_sync[1])paused<=~paused;
        end
    wire audio_busy,frame_started,audio_tick;
    wire [23:0] audio_pcm;
    reg [1:0] audio_enable_sync;
    reg [7:0] audio_fps_meta,audio_fps_sync;
    always @(posedge pixel_clk or posedge video_rst)
        if(video_rst)begin audio_enable_sync<=0;audio_fps_meta<=3;audio_fps_sync<=3;end
        else begin audio_enable_sync<={audio_enable_sync[0],audio_enabled};
                   audio_fps_meta<=video_fps;audio_fps_sync<=audio_fps_meta;end
    video_audio_buffer u_movie_audio (.write_clk(sd_clk),.write_valid(audio_write_valid),
        .write_bank(write_bank),.write_address(audio_write_address),.write_data(audio_write_data),
        .clk(pixel_clk),.rst(video_rst | ~video_pixel),.enabled(audio_enable_sync[1]),
        .paused(paused),.start(frame_started),.read_bank(read_bank),.sample_tick(audio_tick),
        .fps(audio_fps_sync),.busy(audio_busy),.pcm_sample(audio_pcm));
    video_frame_presenter #(.AUDIO_SYNC(1)) u_movie_presenter (.clk(pixel_clk),.rst(video_rst | ~video_pixel),
        .vblank(x==0 && y==480),.frame_start(x==0 && y==0),.paused(paused),
        .frame_toggle(frame_toggle),.fps(video_fps),.consumed_toggle(consumed_toggle),
        .audio_busy(audio_busy),.frame_started(frame_started),
        .read_bank(read_bank),.read_req(movie_read_req),.read_ack(read_ack),.show_frame(movie_shown));
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
    frame_read_write #(.BURST_SIZE(128),.RUNTIME_V_FLIP(1),.WRITE_V_FLIP(1),.FRAME_WIDTH(640),.FRAME_HEIGHT(480)) u_frame (
        .write_v_flip(~video_mem),.rst(mem_rst),.mem_clk(mem_clk),.Sdr_init_done(memory_initialized),
        .Sdr_init_ref_vld(memory_refresh),.Sdr_busy(memory_busy),
        .App_rd_en(app_rd_en),.App_rd_addr(app_rd_addr),
        .Sdr_rd_en(sdram_rd_valid),.Sdr_rd_dout(sdram_rd_data),
        .read_clk(pixel_clk),.read_req(read_req),.read_req_ack(read_ack),.read_finish(),
        .read_addr_0(21'd0),.read_addr_1(21'd307200),.read_addr_2(21'd0),.read_addr_3(21'd0),
        .read_addr_index({1'b0,video_pixel & read_bank}),.read_len(21'd307200),
        .read_en(fifo_read_en & show_image),.read_data(fifo_pixel),
        .App_wr_en(app_wr_en),.App_wr_addr(app_wr_addr),.App_wr_din(app_wr_data),.App_wr_dm(app_wr_mask),
        .write_clk(sd_clk),.write_req(write_req),.write_req_ack(write_ack),.write_finish(write_finish),
        .write_addr_0(21'd0),.write_addr_1(21'd307200),.write_addr_2(21'd0),.write_addr_3(21'd0),
        .write_addr_index({1'b0,video_sd & write_bank}),.write_len(21'd307200),.write_en(pixel_valid),.write_data(pixel_data));
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
    // Mailbox transfers the complete UI snapshot; frame latch avoids tearing.
    wire [8:0] ui_snapshot;
    reg [8:0] ui_frame;
    ui_state_bridge u_ui_bridge (.source_clk(sys_clk),.source_reset_n(touch_reset_n),
        .source_data({touch_online,auto_mode,volume_level,pressed_button}),
        .destination_clk(pixel_clk),.destination_reset_n(~video_rst),
        .destination_data(ui_snapshot));
    wire [23:0] menu_rgb;
    touch_menu_overlay #(.SHOW_STATUS(1)) u_menu_overlay (.x(x),.y(y),.de(de),
        .menu_visible(1'b1),.video_mode(video_pixel),.playing(video_pixel ? ~paused : ui_frame[7]),
        .pressed_button(ui_frame[2:0]),.touch_online(ui_frame[8]),.volume_level(ui_frame[6:3]),
        .rgb_in(24'd0),.rgb_out(menu_rgb));
    reg [20:0] menu_cover_delay;
    reg [23:0] menu_delay[0:20];
    integer i;
    always @(posedge pixel_clk or posedge video_rst) begin
        if(video_rst) begin
            osd_cover_delay<=0;
            ui_frame<={1'b0,1'b0,4'd8,3'd0};menu_cover_delay<=0;
            for(i=0;i<=20;i=i+1)menu_delay[i]<=0;
            for(i=0;i<=20;i=i+1)loading_delay[i]<=0;
            for(i=0;i<20;i=i+1)osd_delay[i]<=0;
        end
        else begin
            if(x==0 && y==0)ui_frame<=ui_snapshot;
            menu_cover_delay<={menu_cover_delay[19:0],(de && y>=400 && y<480)};
            menu_delay[0]<=menu_rgb;
            for(i=1;i<=20;i=i+1)menu_delay[i]<=menu_delay[i-1];
            loading_delay[0]<=status_frame>=10 ? 24'h000000 : loading_rgb;
            // The Chinese font contributes one clock; add twenty to total twenty-one.
            osd_cover_delay<={osd_cover_delay[18:0],osd_cover};
            osd_delay[0]<=osd_rgb;
            for(i=1;i<=20;i=i+1)loading_delay[i]<=loading_delay[i-1];
            for(i=1;i<20;i=i+1)osd_delay[i]<=osd_delay[i-1];
        end
    end
    wire [23:0] picture_rgb=osd_cover_delay[19] ? osd_delay[19] : (show_image ? image_rgb : loading_delay[20]);
    wire [23:0] base_rgb=video_pixel ? (show_image ? image_rgb : 24'h000000) : picture_rgb;
    wire [23:0] output_rgb=menu_cover_delay[20] ? menu_delay[20] : base_rgb;
    wire [23:0] volume_pcm;
    media_volume_apply u_volume_apply (.pcm_in(audio_pcm),.level(ui_snapshot[6:3]),.pcm_out(volume_pcm));
    hdmi_audio_output #(.TEST_AUDIO(0),.EXTERNAL_AUDIO(1)) u_hdmi (.pixel_clk(pixel_clk),.serial_clk(serial_clk),
        .pcm_left(volume_pcm),.pcm_right(volume_pcm),.audio_tick(audio_tick),
        .rst(video_rst),.vs(delayed_vs),.de(delayed_de),.rgb(output_rgb),
        .clk_p(HDMI_CLK_P),.d0_p(HDMI_D0_P),.d1_p(HDMI_D1_P),.d2_p(HDMI_D2_P),
        .ddc_scl(HDMI_DDC_SCL),.ddc_sda(HDMI_DDC_SDA));
    assign HDMI_CLK_P1=HDMI_CLK_P;
    assign HDMI_D0_P1=HDMI_D0_P;
    assign HDMI_D1_P1=HDMI_D1_P;
    assign HDMI_D2_P1=HDMI_D2_P;
endmodule
