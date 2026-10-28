// Shared FAT32 image/video player; KEY4 hold or KEY4+KEY2 switches mode.
// KEY1 resets to image mode. RVF2 soundtrack is sent over HDMI_B.
module tf_media_top (
    input wire sys_clk, input wire sys_rst_n,
    input wire key_next_n, key_prev_n, key_auto_n,
    input wire [1:0] interval_switch,
    input wire direction_switch, input wire menu_hide_switch,
    output wire [7:0] seg_n,digit_en,
    output wire buzzer_n,
    output wire HDMI_CLK_P, HDMI_D0_P, HDMI_D1_P, HDMI_D2_P,
    output wire HDMI_CLK_P1, HDMI_D0_P1, HDMI_D1_P1, HDMI_D2_P1,
    output wire HDMI_DDC_SCL, inout wire HDMI_DDC_SDA,
    output wire sd_ncs, sd_dclk, sd_mosi, input wire sd_miso
);
    // The board buzzer is active low; keep it disabled for all key presses.
    assign buzzer_n = 1'b1;
    reg [3:0] feature_frame;
    wire [1:0] zoom_frame=feature_frame[3:2];
    wire [15:0] status_font_code,browser_font_code,status_font_pixels,browser_font_pixels;
    wire [3:0] status_font_row,browser_font_row;
    wire pixel_clk, serial_clk, video_lock;
    wire sd_clk, mem_clk, mem_clk_shift, memory_lock;
    video_pll u_video_pll (.refclk(sys_clk),.reset(~sys_rst_n),
        .extlock(video_lock),.clk0_out(serial_clk),.clk1_out(pixel_clk));
    sys_pll u_memory_pll (.refclk(sys_clk),.reset(~sys_rst_n),
        .extlock(memory_lock),.clk0_out(sd_clk),.clk1_out(mem_clk),.clk2_out(mem_clk_shift));

    // Configuration-time reset initializes control logic and HDMI audio level.
    reg [2:0] touch_reset_pipe=0;
    always @(posedge sys_clk or negedge sys_rst_n)
        if(!sys_rst_n) touch_reset_pipe<=0;
        else touch_reset_pipe<={touch_reset_pipe[1:0],1'b1};
    wire touch_reset_n=sys_rst_n & touch_reset_pipe[2];
    wire video_mode,physical_short,physical_long,media_reset_n;
    // This display has no FPGA-compatible touch connection; use physical keys.
    wire browser_visible,open_file,open_video,selected_valid;
    wire [4:0] browser_scroll_first;
    wire [4:0] selected_file,query_index,catalog_display_index,query_bmp_index;
    wire [87:0] query_name,catalog_display_name;
    wire [1:0] query_type,catalog_display_type;
    wire key_next_pressed,key_prev_pressed;
    wire [1:0] zoom_setting;
    wire subtitles_setting,spectrum_setting;
    media_feature_keys u_feature_keys (.clk(sys_clk),.rst_n(touch_reset_n),
        .next_n(key_next_n),.prev_n(key_prev_n),.browser_visible(browser_visible),.video_mode(video_mode),
        .next_event(key_next_pressed),.prev_event(key_prev_pressed),.zoom(zoom_setting),
        .subtitles(subtitles_setting),.spectrum(spectrum_setting));
    wire catalog_done_sd;wire [5:0] file_count_sd;wire [3:0] catalog_status_sd;
    wire [7:0] debug_root_byte_sd;wire [15:0] debug_root_lba_sd;
    reg [1:0] catalog_done_sys;
    reg [5:0] file_count_sys;reg [3:0] catalog_status_sys;
    reg [7:0] debug_root_byte_sys;reg [15:0] debug_root_lba_sys;
    reg [4:0] requested_image=0;
    reg [87:0] requested_video="VIDEO   RV ";
    // Keep the mixed-media directory ordinal for the item currently opened.
    reg [4:0] current_file_index=0;
    always @(posedge sys_clk or negedge touch_reset_n)begin
        if(!touch_reset_n)begin
            catalog_done_sys<=0;file_count_sys<=0;catalog_status_sys<=0;
            debug_root_byte_sys<=0;debug_root_lba_sys<=0;
            requested_image<=0;requested_video<="VIDEO   RV ";current_file_index<=0;
        end else begin
            catalog_done_sys<={catalog_done_sys[0],catalog_done_sd};
            if(catalog_done_sys[1])begin
                file_count_sys<=file_count_sd;catalog_status_sys<=catalog_status_sd;
                debug_root_byte_sys<=debug_root_byte_sd;debug_root_lba_sys<=debug_root_lba_sd;
            end
            if(open_file)begin
                current_file_index<=selected_file;
                if(open_video)requested_video<=query_name;else requested_image<=query_bmp_index;
            end
        end
    end
    touch_file_browser u_browser (.clk(sys_clk),.reset_n(touch_reset_n),.enable(media_reset_n),
        .catalog_done(catalog_done_sys[1]),.file_count(file_count_sys),.query_type(query_type),
        .visible(browser_visible),.scroll_first(browser_scroll_first),
        .selection_valid(selected_valid),.selected(selected_file),.open_event(open_file),
        .open_video(open_video),.query_index(query_index),
        .nav_down(key_next_pressed),.nav_up(key_prev_pressed),
        .nav_open(physical_short & browser_visible),
        .nav_menu(physical_long));
    wire short_press=physical_short & ~browser_visible;
    media_key_control #(.EXTERNAL_ACTIONS(1),.EXTERNAL_OPEN(1),.BROWSER_KEYS(1)) u_media_keys (.clk(sys_clk),.reset_n(sys_rst_n),
        .key_auto_n(key_auto_n),.restart_n(1'b1),.video_mode(video_mode),
        .short_press(physical_short),.long_press(physical_long),.media_reset_n(media_reset_n),
        .mode_event(1'b0),.restart_event(1'b0),.open_event(open_file),.open_video(open_video));
    wire [3:0] load_status;
    wire image_ready;
    wire [4:0] image_index;
    wire [5:0] catalog_total;
    wire [5:0] browser_image_total;
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
            total_meta<=browser_image_total;total_sync<=total_meta;
            catalog_sync<={catalog_sync[0],catalog_done_sd};
            if(catalog_sync[1])image_total<=total_sync;
        end
    end
    wire run_reset_n;
    wire auto_mode;
    wire show_image;
    reg show_picture;
    reg image_paused=0;
    always @(posedge sys_clk or negedge sys_rst_n)begin
        if(!sys_rst_n)image_paused<=0;
        else if(!interval_switch[0] || open_file)image_paused<=0;
        else if(short_press && !video_mode)image_paused<=~image_paused;
    end
    image_key_control #(.EXTERNAL_STEP(1),.EXTERNAL_SELECTION(1),.EXTERNAL_AUTO_LEVEL(1)) u_image_keys (.clk(sys_clk),.reset_n(media_reset_n),
        .image_ready(show_image & ~video_mode),.key_next_n(1'b1),.key_prev_n(1'b1),
        .key_auto_n(1'b1),.interval_switch(interval_switch),.auto_mode(auto_mode),.auto_pause(image_paused),
        .direction_switch(direction_switch),.image_total(image_total),
        .stable_interval(stable_interval),.stable_direction(stable_direction),
        .image_index(image_index),.run_reset_n(run_reset_n),
        .next_event(key_next_pressed & ~video_mode & ~browser_visible),.prev_event(key_prev_pressed & ~video_mode & ~browser_visible),.initial_index(requested_image));
    // In the browser show the highlighted row; during playback keep showing
    // the directory row that was opened. The count covers the mixed-media list.
    wire [4:0] displayed_file_index=browser_visible && selected_valid ? selected_file : current_file_index;
    image_number_display u_file_number (.clk(sys_clk),.reset_n(media_reset_n),
        .image_index(displayed_file_index),.total_count(file_count_sys),.seg_n(seg_n),.digit_en(digit_en));
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
    // Keep the HDMI timing/transmitter alive while the SD card is scanned or
    // media is loading. The browser and loading UI must remain visible even
    // when the card has no playable image or a media read fails.
    (* dont_touch="true" *) wire video_ready=media_reset_n & video_lock & memory_lock;
    always @(posedge pixel_clk or negedge video_ready)
        if(!video_ready) video_reset_pipe<=0;else video_reset_pipe<={video_reset_pipe[1:0],1'b1};
    wire sd_rst=~sd_reset_pipe[2], mem_rst=~mem_reset_pipe[2], video_rst=~video_reset_pipe[2];

    (* async_reg="true" *) reg [1:0] mode_sd=0,mode_mem=0,mode_pixel=0;
    always @(posedge sd_clk) mode_sd<={mode_sd[0],video_mode};
    always @(posedge mem_clk) mode_mem<={mode_mem[0],video_mode};
    always @(posedge pixel_clk) mode_pixel<={mode_pixel[0],video_mode};
    wire video_sd=mode_sd[1],video_mem=mode_mem[1],video_pixel=mode_pixel[1];
    wire image_rst=sd_rst | video_sd | ~catalog_done_sd, movie_rst=sd_rst | ~video_sd | ~catalog_done_sd;
    wire [3:0] image_status,movie_status;
    assign load_status=video_sd ? movie_status : image_status;
    wire [7:0] video_fps;
    wire audio_enabled,audio_write_valid;
    wire [13:0] audio_write_address;
    wire [7:0] audio_write_data;
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
    // Catalog reset is independent of media reloads; its immutable names and
    // counts survive opening another file. KEY1/card reset triggers a rescan.
    reg [2:0] catalog_reset_pipe=0;
    wire catalog_reset_n=sys_rst_n & video_lock & memory_lock;
    always @(posedge sd_clk or negedge catalog_reset_n)
        if(!catalog_reset_n)catalog_reset_pipe<=0;
        else catalog_reset_pipe<={catalog_reset_pipe[1:0],1'b1};
    wire cat_sector_req;wire [31:0] cat_sector_lba;
    fat32_media_catalog u_catalog (.clk(sd_clk),.rst(~catalog_reset_pipe[2]),.sd_ready(sd_ready),
        .sector_req(cat_sector_req),.sector_lba(cat_sector_lba),.sector_byte(sector_byte),
        .sector_valid(sector_valid),.sector_end(sector_end),.done(catalog_done_sd),
        .image_count(browser_image_total),.count(file_count_sd),.status(catalog_status_sd),.query_index(query_index),
        .query_name(query_name),.query_type(query_type),.query_image_index(query_bmp_index),
        .display_clk(pixel_clk),.display_index(catalog_display_index),.display_name(catalog_display_name),.display_type(catalog_display_type),
        .debug_root_byte(debug_root_byte_sd),.debug_root_lba(debug_root_lba_sd));
    assign sector_req=!catalog_done_sd ? cat_sector_req : video_sd ? mov_sector_req : img_sector_req;
    assign sector_lba=!catalog_done_sd ? cat_sector_lba : video_sd ? mov_sector_lba : img_sector_lba;
    assign write_req=video_sd ? mov_write_req : img_write_req;
    assign pixel_valid=video_sd ? mov_pixel_valid : img_pixel_valid;
    assign pixel_data=video_sd ? mov_pixel_data : img_pixel_data;
    fat32_bmp_loader #(.AUTO_SCAN(1),.QUICK_SELECT(1)) u_loader (
        .clk(sd_clk),.rst(image_rst),.sd_ready(sd_ready),.memory_ready(memory_init_sync[1]),
        .sector_req(img_sector_req),.sector_lba(img_sector_lba),.sector_byte(sector_byte),
        .sector_valid(sector_valid),.sector_end(sector_end),
        .write_req(img_write_req),.write_ack(write_ack_sync[2]),.pixel_valid(img_pixel_valid),
        .pixel_data(img_pixel_data),.write_finish_toggle(finish_toggle),
        .image_ready(image_ready),.status(image_status),.image_index(image_index),
        .image_total(catalog_total),.catalog_valid(catalog_valid),.image_name(image_name));

    fat32_video_reader #(.AUDIO_SUPPORT(1),.EXTERNAL_NAME(1)) u_movie_loader (
        .clk(sd_clk),.rst(movie_rst),.sd_ready(sd_ready),.memory_ready(memory_init_sync[1]),
        .sector_req(mov_sector_req),.sector_lba(mov_sector_lba),.sector_byte(sector_byte),
        .sector_valid(sector_valid),.sector_end(sector_end),
        .write_req(mov_write_req),.write_ack(write_ack_sync[2]),.pixel_valid(mov_pixel_valid),
        .pixel_data(mov_pixel_data),.write_finish_toggle(finish_toggle),
        .frame_toggle(frame_toggle),.consumed_toggle(consumed_toggle),
        .write_bank(write_bank),.status(movie_status),.fps(video_fps),
        .audio_enabled(audio_enabled),.audio_valid(audio_write_valid),
        .audio_address(audio_write_address),.audio_data(audio_write_data),.selected_name(requested_video));
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
    wire [20:0] scaled_rd_addr;
    image_scale_address u_scale_address (.clk(mem_clk),.rst(mem_rst),.ack(read_ack),
        .read_en(app_rd_en),.video_mode(video_mem),.zoom_request(zoom_frame),
        .address(app_rd_addr),.mapped_address(scaled_rd_addr));
    sdram u_sdram (.Clk(mem_clk),.Clk_sft(mem_clk_shift),.Rst(mem_rst),
        .Sdr_init_done(memory_initialized),.Sdr_init_ref_vld(memory_refresh),.Sdr_busy(memory_busy),
        .App_wr_en(app_wr_en),.App_wr_addr(app_wr_addr),.App_wr_dm(app_wr_mask),.App_wr_din(app_wr_data),
        .App_rd_en(app_rd_en),.App_rd_addr(scaled_rd_addr),.Sdr_rd_en(sdram_rd_valid),.Sdr_rd_dout(sdram_rd_data));

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
    // Atomic feature state crosses clocks, then changes only in vertical blank.
    wire [3:0] feature_snapshot;
    ui_state_bridge #(.WIDTH(4)) u_feature_bridge (.source_clk(sys_clk),.source_reset_n(touch_reset_n),
        .source_data({zoom_setting,subtitles_setting,spectrum_setting}),
        .destination_clk(pixel_clk),.destination_reset_n(~video_rst),.destination_data(feature_snapshot));
    reg [9:0] output_x[0:20],output_y[0:20];
    reg [47:0] spectrum_frame;
    wire [47:0] spectrum_levels;
    audio_spectrum u_spectrum (.clk(pixel_clk),.rst(video_rst),
        .enabled(video_pixel && show_image && audio_enable_sync[1]),
        .sample_tick(audio_tick && !paused),.sample(audio_pcm[23:8]),.levels(spectrum_levels));
    integer coord_i;
    always @(posedge pixel_clk or posedge video_rst)begin
        if(video_rst)begin
            feature_frame<=4'b0011;spectrum_frame<=0;
            for(coord_i=0;coord_i<=20;coord_i=coord_i+1)begin output_x[coord_i]<=0;output_y[coord_i]<=0;end
        end else begin
            if(x==0 && y==480)begin feature_frame<=feature_snapshot;spectrum_frame<=spectrum_levels;end
            output_x[0]<=x;output_y[0]<=y;
            for(coord_i=1;coord_i<=20;coord_i=coord_i+1)begin output_x[coord_i]<=output_x[coord_i-1];output_y[coord_i]<=output_y[coord_i-1];end
        end
    end
    wire subtitle_request,subtitle_panel,subtitle_ink;
    wire [15:0] subtitle_font_code;
    wire [3:0] subtitle_font_row;
    media_subtitles u_subtitles (.clk(pixel_clk),.rst_n(~video_rst),
        .frame_start(x==0 && y==0),.frame_started(frame_started),.shown(show_image),
        .video_mode(video_pixel),.enabled(feature_frame[1]),.fps(audio_fps_sync),.zoom(zoom_frame),
        .x(x),.y(y),.de(de),.font_request(subtitle_request),
        .font_codepoint(subtitle_font_code),.font_row(subtitle_font_row),.font_pixels(status_font_pixels),
        .panel(subtitle_panel),.ink(subtitle_ink));
    wire osd_cover;
    wire [23:0] osd_rgb;
    wire [87:0] playing_file_name=video_pixel ? requested_video : image_name;
    osd_font16 u_shared_osd_font (.clk(pixel_clk),.codepoint(subtitle_request ? subtitle_font_code : status_font_code),.row(subtitle_request ? subtitle_font_row : status_font_row),
        .pixels(status_font_pixels),.codepoint_b(browser_font_code),.row_b(browser_font_row),
        .pixels_b(browser_font_pixels));
    image_status_osd #(.FEATURE_HINTS(1)) u_status_osd (.pixel_clk(pixel_clk),.rst_n(~video_rst),
        .x(x),.y(y),.de(de),.image_shown(show_image),.load_status(load_status),
        .image_index(image_index),.image_total(image_total),.auto_mode(auto_mode),
        .interval_setting(stable_interval),.reverse_direction(stable_direction),
        .video_mode(video_pixel),.overlay_active(osd_cover),.rgb(osd_rgb),.image_name(playing_file_name),
        .font_codepoint(status_font_code),.font_row(status_font_row),.font_pixels(status_font_pixels));
    reg [19:0] subtitle_panel_delay,subtitle_ink_delay;
    reg [19:0] osd_cover_delay;
    reg [23:0] osd_delay[0:19];
    reg [23:0] loading_delay[0:20];
    wire [46:0] browser_snapshot;
    reg [46:0] browser_frame;
    ui_state_bridge #(.WIDTH(47)) u_browser_bridge (.source_clk(sys_clk),.source_reset_n(touch_reset_n),
        .source_data({debug_root_byte_sys,debug_root_lba_sys,browser_visible,catalog_done_sys[1],file_count_sys,catalog_status_sys,
                      browser_scroll_first,selected_valid,selected_file}),
        .destination_clk(pixel_clk),.destination_reset_n(~video_rst),.destination_data(browser_snapshot));
    wire browser_cover;wire [23:0] browser_rgb;
    file_browser_overlay u_file_overlay (.clk(pixel_clk),.rst_n(~video_rst),.x(x),.y(y),.de(de),
        .visible(browser_frame[22]),.ready(browser_frame[21]),.count(browser_frame[20:15]),
        .debug_root_byte(browser_frame[46:39]),.debug_root_lba(browser_frame[38:23]),
        .status(browser_frame[14:11]),.scroll_first(browser_frame[10:6]),.selection_valid(browser_frame[5]),
        .selected(browser_frame[4:0]),.display_index(catalog_display_index),
        .file_name(catalog_display_name),.file_type(catalog_display_type),.overlay_active(browser_cover),.rgb(browser_rgb),
        .cn_codepoint(browser_font_code),.cn_font_row(browser_font_row),.cn_pixels(browser_font_pixels));
    reg [19:0] browser_cover_delay;
    reg [23:0] browser_delay[0:19];
    integer i;
    always @(posedge pixel_clk or posedge video_rst) begin
        if(video_rst) begin
            browser_frame<=0;browser_cover_delay<=0;subtitle_panel_delay<=0;subtitle_ink_delay<=0;
            for(i=0;i<20;i=i+1)browser_delay[i]<=0;
            osd_cover_delay<=0;
            for(i=0;i<=20;i=i+1)loading_delay[i]<=0;
            for(i=0;i<20;i=i+1)osd_delay[i]<=0;
        end
        else begin
            if(x==0 && y==0)browser_frame<=browser_snapshot;
            subtitle_panel_delay<={subtitle_panel_delay[18:0],subtitle_panel};
            subtitle_ink_delay<={subtitle_ink_delay[18:0],subtitle_ink};
            browser_cover_delay<={browser_cover_delay[18:0],browser_cover};
            browser_delay[0]<=browser_rgb;
            for(i=1;i<20;i=i+1)browser_delay[i]<=browser_delay[i-1];
            loading_delay[0]<=status_frame>=10 ? 24'h000000 : loading_rgb;
            // The Chinese font contributes one clock; add twenty to total twenty-one.
            osd_cover_delay<={osd_cover_delay[18:0],osd_cover};
            osd_delay[0]<=osd_rgb;
            for(i=1;i<=20;i=i+1)loading_delay[i]<=loading_delay[i-1];
            for(i=1;i<20;i=i+1)osd_delay[i]<=osd_delay[i-1];
        end
    end
    wire small_margin=!video_pixel && zoom_frame==1 &&
        (output_x[20]<160 || output_x[20]>=480 || output_y[20]<120 || output_y[20]>=360);
    wire [23:0] scaled_rgb=small_margin ? 24'h000000 : image_rgb;
    wire [23:0] transition_rgb;
    wire [1:0] transition_effect;
    media_transition u_transition (.clk(pixel_clk),.rst_n(~video_rst),
        .frame_start(x==0 && y==480),.shown(show_image),.video_mode(video_pixel),
        .x(output_x[20]),.y(output_y[20]),.rgb_in(scaled_rgb),.rgb_out(transition_rgb),.effect(transition_effect));
    wire [23:0] media_base=video_pixel ? (show_image ? image_rgb : 24'h000000) :
                                      (show_image ? transition_rgb : loading_delay[20]);
    wire [23:0] subtitle_base=subtitle_ink_delay[19] ? 24'hfff3b0 :
        subtitle_panel_delay[19] ? {1'b0,media_base[23:17],1'b0,media_base[15:9],1'b0,media_base[7:1]} : media_base;
    wire spectrum_cover;
    wire [23:0] spectrum_rgb;
    audio_spectrum_overlay u_spectrum_overlay (.clk(pixel_clk),.rst_n(~video_rst),
        .x(x),.y(y),.de(de),.visible(feature_frame[0] && video_pixel && show_image && audio_enable_sync[1]),
        .levels(spectrum_frame),.active(spectrum_cover),.rgb(spectrum_rgb));
    reg [19:0] spectrum_cover_delay;
    reg [23:0] spectrum_delay[0:19];
    integer spectrum_i;
    always @(posedge pixel_clk or posedge video_rst)begin
        if(video_rst)begin
            spectrum_cover_delay<=0;
            for(spectrum_i=0;spectrum_i<20;spectrum_i=spectrum_i+1)spectrum_delay[spectrum_i]<=0;
        end else begin
            spectrum_cover_delay<={spectrum_cover_delay[18:0],spectrum_cover};
            spectrum_delay[0]<=spectrum_rgb;
            for(spectrum_i=1;spectrum_i<20;spectrum_i=spectrum_i+1)spectrum_delay[spectrum_i]<=spectrum_delay[spectrum_i-1];
        end
    end
    wire [23:0] visualized_rgb=spectrum_cover_delay[19] ? spectrum_delay[19] : subtitle_base;
    // SW4 only masks the final status layer. Feature mailbox, framebuffer
    // addressing, pixel consumption and HDMI timing retain the coffee baseline.
    wire playback_osd_visible;
    playback_osd_switch u_playback_osd_switch (
        .clk(pixel_clk),.rst(video_rst),.hide_switch(menu_hide_switch),
        .vblank(x==0 && y==480),.visible(playback_osd_visible));
    wire [23:0] base_rgb=(osd_cover_delay[19] && playback_osd_visible) ? osd_delay[19] : visualized_rgb;
    wire [23:0] output_rgb=browser_cover_delay[19] ? browser_delay[19] : base_rgb;
    wire [23:0] volume_pcm;
    media_volume_apply u_volume_apply (.pcm_in(audio_pcm),.level(4'd8),.pcm_out(volume_pcm));
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

// Pixel-domain level control, independent of the system-domain feature mailbox.
// 500000 pixel clocks at 25 MHz give 20 ms of debounce. Visibility only changes
// in vertical blanking, before the next active frame starts.
module playback_osd_switch #(
    parameter integer DEBOUNCE_CYCLES=500000
)(input wire clk,rst,hide_switch,vblank,output reg visible);
    (* async_reg="true" *) reg [1:0] switch_sync;
    localparam integer COUNT_BITS=DEBOUNCE_CYCLES<=1 ? 1 : $clog2(DEBOUNCE_CYCLES);
    reg [COUNT_BITS-1:0] stable_count;
    reg stable_hidden;
    always @(posedge clk or posedge rst)begin
        if(rst)begin switch_sync<=0;stable_count<=0;stable_hidden<=0;visible<=1;end
        else begin
            switch_sync<={switch_sync[0],hide_switch};
            if(switch_sync[1]==stable_hidden)stable_count<=0;
            else if(DEBOUNCE_CYCLES<=1 || stable_count==DEBOUNCE_CYCLES-1)begin
                stable_hidden<=switch_sync[1];stable_count<=0;
            end else stable_count<=stable_count+1'b1;
            if(vblank)visible<=~stable_hidden;
        end
    end
endmodule
