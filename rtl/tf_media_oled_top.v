// Native 720x720 media player with SSD1306 side menu and 4x4 keypad.
// D or board KEY1 resets/rescans; HDMI carries media, subtitles and spectrum.
module tf_media_oled_top (
    input wire sys_clk, input wire sys_rst_n,
    input wire [3:0] keypad_columns,output wire [3:0] keypad_rows,
    inout wire oled_scl,oled_sda,
    output wire [7:0] seg_n,digit_en,
    output wire buzzer_n,
    output wire HDMI_CLK_P, HDMI_D0_P, HDMI_D1_P, HDMI_D2_P,
    output wire HDMI_CLK_P1, HDMI_D0_P1, HDMI_D1_P1, HDMI_D2_P1,
    output wire HDMI_DDC_SCL, inout wire HDMI_DDC_SDA,
    output wire sd_ncs, sd_dclk, sd_mosi, input wire sd_miso
);
    reg[6:0] soft_reset_count=0;
    wire core_reset_n=sys_rst_n && soft_reset_count==0;
    always @(posedge sys_clk or negedge sys_rst_n)
        if(!sys_rst_n)soft_reset_count<=0;
        else if(key_event && key_code==15)soft_reset_count<=64;
        else if(soft_reset_count!=0)soft_reset_count<=soft_reset_count-1'b1;
    localparam WIDTH=720, HEIGHT=720, FRAME_PIXELS=WIDTH*HEIGHT;
    // Waveshare 4inch HDMI LCD (C) published timing: 48 MHz, 940x768 total.
    localparam PIXEL_HZ=48000000;
    // S3 toggles the spectrum in video mode; S1 toggles subtitles.
    localparam ENABLE_SPECTRUM=1;
    localparam HTOTAL=940, VTOTAL=768, HSA=20,HBP=100,HFP=100,VSA=8,VBP=20,VFP=20;
    // The board buzzer is active low; keep it disabled for all key presses.
    assign buzzer_n = 1'b1;
    reg [3:0] feature_frame;
    wire [1:0] zoom_frame=feature_frame[3:2];
    wire [15:0] status_font_pixels,browser_font_pixels;
    wire pixel_clk, serial_clk, video_lock;
    wire sd_clk, mem_clk, mem_clk_shift, memory_lock;
    video_pll_48 u_video_pll (.refclk(sys_clk),.reset(~core_reset_n),
        .extlock(video_lock),.clk0_out(serial_clk),.clk1_out(pixel_clk));
    memory_pll_50 u_memory_pll (.refclk(sys_clk),.reset(~core_reset_n),
        .extlock(memory_lock),.clk0_out(sd_clk),.clk1_out(mem_clk),.clk2_out(mem_clk_shift));

    // Configuration-time reset initializes control logic and HDMI audio level.
    reg [2:0] touch_reset_pipe=0;
    always @(posedge sys_clk or negedge core_reset_n)
        if(!core_reset_n) touch_reset_pipe<=0;
        else touch_reset_pipe<={touch_reset_pipe[1:0],1'b1};
    wire touch_reset_n=core_reset_n & touch_reset_pipe[2];
    reg video_mode;wire physical_short,physical_long,media_reset_n;
    reg menu_return_active,saved_video_mode;
    reg [4:0] saved_image_index;
    // This display has no FPGA-compatible touch connection; use physical keys.
    wire browser_visible,open_file,open_video,selected_valid;
    wire [4:0] selected_file,query_index,catalog_display_index,query_bmp_index;
    wire [87:0] query_name,catalog_display_name;
    wire [1:0] query_type,catalog_display_type;
    wire key_next_pressed,key_prev_pressed;
    wire [1:0] zoom_setting;
    wire subtitles_setting,spectrum_setting;
    wire key_event;wire[3:0] key_code;
    matrix_keypad u_keypad(.clk(sys_clk),.reset_n(sys_rst_n),.columns(keypad_columns),
        .rows(keypad_rows),.pressed(key_event),.code(key_code));
    reg [1:0] zoom_control,interval_switch;
    reg [4:0] interval_seconds_control;
    reg subtitle_control,spectrum_control,direction_switch,video_paused_setting;
    reg [6:0] media_reset_count;
    assign zoom_setting=zoom_control;assign subtitles_setting=subtitle_control;assign spectrum_setting=spectrum_control;
    assign physical_short=key_event && key_code==5;
    assign physical_long=key_event && key_code==3;
    assign key_next_pressed=key_event && key_code==6;
    assign key_prev_pressed=key_event && key_code==4;
    wire replay=key_event && key_code==12 && video_mode && !browser_visible;
    assign media_reset_n=core_reset_n && media_reset_count==0;
    always @(posedge sys_clk or negedge touch_reset_n)begin
        if(!touch_reset_n)begin
            zoom_control<=0;interval_switch<=0;interval_seconds_control<=5;subtitle_control<=1;spectrum_control<=1;
            direction_switch<=0;video_mode<=0;media_reset_count<=0;video_paused_setting<=0;
            menu_return_active<=0;saved_video_mode<=0;saved_image_index<=0;
        end else begin
            if(media_reset_count!=0)media_reset_count<=media_reset_count-1'b1;
            if(key_event)case(key_code)
                0:if(video_mode)subtitle_control<=~subtitle_control;
                  else interval_switch[0]<=~interval_switch[0];
                2:if(video_mode)spectrum_control<=~spectrum_control;
                  else direction_switch<=~direction_switch;
                7:if(!browser_visible && !video_mode)begin
                    if(zoom_control==1)zoom_control<=0;
                    else if(zoom_control==0)zoom_control<=2;
                end
                8:if(!browser_visible && !video_mode && interval_seconds_control>1)
                    interval_seconds_control<=interval_seconds_control-1'b1;
                10:if(!browser_visible && !video_mode && interval_seconds_control<20)
                    interval_seconds_control<=interval_seconds_control+1'b1;
                11:if(!browser_visible && !video_mode)begin
                    if(zoom_control==2)zoom_control<=0;
                    else if(zoom_control==0)zoom_control<=1;
                end
            endcase
            if(physical_short && !browser_visible && video_mode)video_paused_setting<=~video_paused_setting;
            if(open_file || replay)begin
                media_reset_count<=64;video_paused_setting<=0;
                if(open_file)begin video_mode<=open_video;menu_return_active<=0;end
            end else if(physical_long && !browser_visible && !menu_return_active)begin
                // Pause media in the browser; S4 returns to the previous media.
                menu_return_active<=1;saved_video_mode<=video_mode;
                saved_image_index<=requested_image;video_mode<=0;media_reset_count<=64;
            end else if(physical_long && browser_visible && menu_return_active)begin
                menu_return_active<=0;video_mode<=saved_video_mode;media_reset_count<=64;
            end
        end
    end
    wire catalog_done_sd;wire [5:0] file_count_sd;wire [3:0] catalog_status_sd;
    wire [7:0] debug_root_byte_sd;wire [15:0] debug_root_lba_sd;
    reg [1:0] catalog_done_sys;
    reg [5:0] file_count_sys;reg [3:0] catalog_status_sys;
    reg [7:0] debug_root_byte_sys;reg [15:0] debug_root_lba_sys;
    reg default_index_applied;
    reg [4:0] requested_image=0;
    reg [87:0] requested_video="VIDEO   RV ";
    // Keep the mixed-media directory ordinal for the item currently opened.
    reg [4:0] current_file_index=0;
    always @(posedge sys_clk or negedge touch_reset_n)begin
        if(!touch_reset_n)begin
            catalog_done_sys<=0;file_count_sys<=0;catalog_status_sys<=0;
            debug_root_byte_sys<=0;debug_root_lba_sys<=0;
            default_index_applied<=0;
            requested_image<=0;requested_video<="VIDEO   RV ";current_file_index<=0;
        end else begin
            catalog_done_sys<={catalog_done_sys[0],catalog_done_sd};
            if(catalog_done_sys[1])begin
                file_count_sys<=file_count_sd;catalog_status_sys<=catalog_status_sd;
                debug_root_byte_sys<=debug_root_byte_sd;debug_root_lba_sys<=debug_root_lba_sd;
            end
            if(open_file)begin
                default_index_applied<=1;
                current_file_index<=selected_file;
                if(open_video)requested_video<=query_name;else requested_image<=query_bmp_index;
            end else if(physical_long && browser_visible && menu_return_active)requested_image<=saved_image_index;
            else if(catalog_done_sys[1] && !default_index_applied)begin
                default_index_applied<=1;
            end
        end
    end
    oled_file_menu u_browser (.clk(sys_clk),.reset_n(touch_reset_n),.enable(touch_reset_n),
        .catalog_done(catalog_done_sys[1]),.file_count(file_count_sys),.query_type(query_type),
        .visible(browser_visible),.valid(selected_valid),.selected(selected_file),.open_event(open_file),
        .open_video(open_video),.query_index(query_index),
        .down(key_event && key_code==9),.up(key_event && key_code==1),
        .confirm(physical_short && browser_visible),.back(physical_long));
    wire short_press=physical_short & ~browser_visible;
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
    always @(posedge sys_clk or negedge core_reset_n)begin
        if(!core_reset_n)image_paused<=0;
        else if(!interval_switch[0] || open_file)image_paused<=0;
        else if(short_press && !video_mode)image_paused<=~image_paused;
    end
    image_key_control #(.EXTERNAL_STEP(1),.EXTERNAL_SELECTION(1),.EXTERNAL_AUTO_LEVEL(1),.EXTERNAL_INTERVAL(1)) u_image_keys (.clk(sys_clk),.reset_n(media_reset_n && default_index_applied),
        .image_ready(show_image & ~video_mode),.key_next_n(1'b1),.key_prev_n(1'b1),
        .key_auto_n(1'b1),.interval_switch(interval_switch),.auto_mode(auto_mode),.auto_pause(image_paused),
        .direction_switch(direction_switch),.image_total(image_total),
        .stable_interval(stable_interval),.stable_direction(stable_direction),.external_interval_seconds(interval_seconds_control),
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
    (* async_reg="true" *) reg [2:0] init_stage_sys_meta,init_stage_sys;
    always @(posedge sys_clk or negedge core_reset_n)
        if(!core_reset_n)begin init_stage_sys_meta<=0;init_stage_sys<=0;end
        else begin init_stage_sys_meta<=sd_init_stage;init_stage_sys<=init_stage_sys_meta;end
    tf_startup_control #(.POWER_WAIT_CYCLES(5000000)) u_startup (.clk(sys_clk),.reset_n(run_reset_n),
        .locked(video_lock & memory_lock),.load_error(load_error_sync[1]),
        .run_enable(startup_done),.fast_start(has_loaded));
    (* dont_touch="true" *) wire ready_clock=media_reset_n & startup_done & video_lock & memory_lock;
    // Asynchronous assertion, three-clock synchronous release per domain.
    // tf_media.sdc exempts only asynchronous requests entering these synchronizers.
    (* async_reg="true", dont_touch="true" *) reg [2:0] sd_reset_pipe=0,mem_reset_pipe=0,video_reset_pipe=0;
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

    (* async_reg="true" *) reg [1:0] mode_sd=0,mode_mem=0,mode_pixel=0,browser_pixel_sync=0,browser_sd_sync=0;
    always @(posedge sd_clk) mode_sd<={mode_sd[0],video_mode};
    always @(posedge sd_clk) browser_sd_sync<={browser_sd_sync[0],browser_visible};
    always @(posedge mem_clk) mode_mem<={mode_mem[0],video_mode};
    always @(posedge pixel_clk) mode_pixel<={mode_pixel[0],video_mode};
    always @(posedge pixel_clk) browser_pixel_sync<={browser_pixel_sync[0],browser_visible};
    wire video_sd=mode_sd[1],video_mem=mode_mem[1],video_pixel=mode_pixel[1];
    wire image_rst=sd_rst | video_sd | browser_sd_sync[1] | ~catalog_done_sd, movie_rst=sd_rst | ~video_sd | ~catalog_done_sd;
    wire [3:0] image_status,movie_status;
    assign load_status=video_sd ? movie_status : image_status;
    wire [7:0] video_fps;
    wire [31:0] movie_frame_count;
    reg [31:0] movie_count_meta,movie_count_pixel;
    always @(posedge pixel_clk)begin movie_count_meta<=movie_frame_count;movie_count_pixel<=movie_count_meta;end
    // Count frames actually presented (so pauses freeze the progress bar).
    localparam [9:0] PROGRESS_BAR_WIDTH=WIDTH-64;
    wire [11:0] movie_total_pixel=movie_count_pixel[11:0];
    reg progress_configured,progress_div_busy;
    reg [3:0] progress_div_bits;
    reg [9:0] progress_dividend,progress_div_quotient,progress_step_whole;
    reg [11:0] progress_divisor,progress_div_remainder,progress_step_remainder;
    reg [11:0] presented_frames,progress_position,progress_fraction;
    wire [12:0] progress_div_trial={progress_div_remainder,progress_dividend[9]};
    wire progress_div_subtract=progress_div_trial>={1'b0,progress_divisor};
    wire [12:0] progress_div_remainder_next=progress_div_subtract ?
        progress_div_trial-{1'b0,progress_divisor} : progress_div_trial;
    wire [9:0] progress_div_quotient_next={progress_div_quotient[8:0],progress_div_subtract};
    wire [12:0] progress_fraction_sum={1'b0,progress_fraction}+{1'b0,progress_step_remainder};
    always @(posedge pixel_clk or posedge video_rst)begin
        if(video_rst)begin
            progress_configured<=0;progress_div_busy<=0;progress_div_bits<=0;
            progress_dividend<=0;progress_div_quotient<=0;progress_divisor<=0;
            progress_div_remainder<=0;progress_step_whole<=0;progress_step_remainder<=0;
            presented_frames<=0;progress_position<=0;progress_fraction<=0;
        end else if(!video_pixel)begin
            progress_configured<=0;progress_div_busy<=0;progress_div_bits<=0;
            progress_dividend<=0;progress_div_quotient<=0;progress_divisor<=0;
            progress_div_remainder<=0;progress_step_whole<=0;progress_step_remainder<=0;
            presented_frames<=0;progress_position<=0;progress_fraction<=0;
        end else if(progress_div_busy)begin
            progress_dividend<={progress_dividend[8:0],1'b0};
            progress_div_quotient<=progress_div_quotient_next;
            progress_div_remainder<=progress_div_remainder_next[11:0];
            if(progress_div_bits==1)begin
                progress_div_busy<=0;progress_configured<=1;
                progress_step_whole<=progress_div_quotient_next;
                progress_step_remainder<=progress_div_remainder_next[11:0];
            end else progress_div_bits<=progress_div_bits-1'b1;
        end else if(!progress_configured && movie_total_pixel!=0)begin
            // Divide the fixed bar width by frame count over ten clocks.
            progress_div_busy<=1;progress_div_bits<=10;
            progress_dividend<=PROGRESS_BAR_WIDTH;progress_div_quotient<=0;
            progress_divisor<=movie_total_pixel;progress_div_remainder<=0;
        end else if(frame_started && progress_configured)begin
            if(presented_frames>=movie_total_pixel)begin
                // The RV reader loops at end of file; restart the bar with it.
                presented_frames<=1;progress_position<=progress_step_whole;
                progress_fraction<=progress_step_remainder;
            end else begin
                presented_frames<=presented_frames+1'b1;
                if(progress_fraction_sum>=movie_total_pixel)begin
                    progress_position<=progress_position+progress_step_whole+1'b1;
                    progress_fraction<=progress_fraction_sum-movie_total_pixel;
                end else begin
                    progress_position<=progress_position+progress_step_whole;
                    progress_fraction<=progress_fraction_sum[11:0];
                end
            end
        end
    end
    wire audio_enabled,audio_write_valid;
    wire [13:0] audio_write_address;
    wire [7:0] audio_write_data;
    wire img_sector_req,mov_sector_req,img_write_req,mov_write_req,img_pixel_valid,mov_pixel_valid;
    wire [31:0] img_sector_lba,mov_sector_lba,img_pixel_data,mov_pixel_data;
    wire write_bank,read_bank,frame_toggle,consumed_toggle;
    wire sector_req,sector_valid,sector_end,sd_ready;
    wire [2:0] sd_init_stage;
    wire [31:0] sector_lba;
    wire [7:0] sector_byte;
    sd_card_top #(.SPI_LOW_SPEED_DIV(61),.SPI_HIGH_SPEED_DIV(0)) u_sd_transport (
        .clk(sd_clk),.rst(sd_rst),.SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),
        .SD_MOSI(sd_mosi),.SD_MISO(sd_miso),.sd_init_done(sd_ready),.sd_init_stage(sd_init_stage),
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
    wire catalog_reset_n=core_reset_n & video_lock & memory_lock;
    always @(posedge sd_clk or negedge catalog_reset_n)
        if(!catalog_reset_n)catalog_reset_pipe<=0;
        else catalog_reset_pipe<={catalog_reset_pipe[1:0],1'b1};
    wire cat_sector_req;wire [31:0] cat_sector_lba;
    fat32_media_catalog #(.FRAME_WIDTH(WIDTH),.FRAME_HEIGHT(HEIGHT),.AUDIO_RATE(12000)) u_catalog (.clk(sd_clk),.rst(~catalog_reset_pipe[2]),.sd_ready(sd_ready),
        .sector_req(cat_sector_req),.sector_lba(cat_sector_lba),.sector_byte(sector_byte),
        .sector_valid(sector_valid),.sector_end(sector_end),.done(catalog_done_sd),
        .image_count(browser_image_total),.count(file_count_sd),.status(catalog_status_sd),.query_index(query_index),
        .query_name(query_name),.query_type(query_type),.query_image_index(query_bmp_index),
        .display_clk(pixel_clk),.display_index(catalog_display_index),.display_name(catalog_display_name),.display_type(catalog_display_type),
        .debug_root_byte(debug_root_byte_sd),.debug_root_lba(debug_root_lba_sd),
        .default_image_valid(),.default_image_index());
    wire subtitle_done,subtitle_error,subtitle_byte_valid;
    wire [15:0] external_subtitle_codepoint;
    wire [9:0] subtitle_prefetch_x=x+1-(WIDTH-512)/2;
    wire external_subtitle_visible;
    assign sector_req=!catalog_done_sd ? cat_sector_req : video_sd ? mov_sector_req : img_sector_req;
    assign sector_lba=!catalog_done_sd ? cat_sector_lba : video_sd ? mov_sector_lba : img_sector_lba;
    assign write_req=video_sd ? mov_write_req : img_write_req;
    assign pixel_valid=video_sd ? mov_pixel_valid : img_pixel_valid;
    assign pixel_data=video_sd ? mov_pixel_data : img_pixel_data;
    fat32_bmp_loader #(.FRAME_WIDTH(WIDTH),.FRAME_HEIGHT(HEIGHT),.AUTO_SCAN(1),.QUICK_SELECT(1)) u_loader (
        .clk(sd_clk),.rst(image_rst),.sd_ready(sd_ready),.memory_ready(memory_init_sync[1]),
        .sector_req(img_sector_req),.sector_lba(img_sector_lba),.sector_byte(sector_byte),
        .sector_valid(sector_valid),.sector_end(sector_end),
        .write_req(img_write_req),.write_ack(write_ack_sync[2]),.pixel_valid(img_pixel_valid),
        .pixel_data(img_pixel_data),.write_finish_toggle(finish_toggle),
        .image_ready(image_ready),.status(image_status),.image_index(image_index),
        .image_total(catalog_total),.catalog_valid(catalog_valid),.image_name(image_name));

    fat32_video_reader #(.FRAME_WIDTH(WIDTH),.FRAME_HEIGHT(HEIGHT),.AUDIO_SUPPORT(1),.AUDIO_RATE(12000),.EXTERNAL_NAME(1),.EXTERNAL_SUBTITLES(1)) u_movie_loader (
        .clk(sd_clk),.rst(movie_rst),.sd_ready(sd_ready),.memory_ready(memory_init_sync[1]),
        .sector_req(mov_sector_req),.sector_lba(mov_sector_lba),.sector_byte(sector_byte),
        .sector_valid(sector_valid),.sector_end(sector_end),
        .write_req(mov_write_req),.write_ack(write_ack_sync[2]),.pixel_valid(mov_pixel_valid),
        .pixel_data(mov_pixel_data),.write_finish_toggle(finish_toggle),
        .frame_toggle(frame_toggle),.consumed_toggle(consumed_toggle),
        .write_bank(write_bank),.status(movie_status),.fps(video_fps),
        .audio_enabled(audio_enabled),.audio_valid(audio_write_valid),
        .audio_address(audio_write_address),.audio_data(audio_write_data),.selected_name(requested_video),.total_frames(movie_frame_count),.subtitle_byte_valid(subtitle_byte_valid),
        .subtitle_done(subtitle_done),.subtitle_error(subtitle_error));
    wire [9:0] x,y;
    wire de,hs,vs;
    video_timing_640x480 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.HTOTAL(HTOTAL),.VTOTAL(VTOTAL),.HSA(HSA),.HBP(HBP),.VSA(VSA),.VBP(VBP)) u_timing (.pixel_clk(pixel_clk),.rst_n(~video_rst),
        .pixel_x(x),.pixel_y(y),.de(de),.hsync(hs),.vsync(vs));
    (* dont_touch="true" *) reg [2:0] image_sync,ack_sync;
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
            end else if(x==0 && y==HEIGHT) image_read_req<=1;
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
    video_audio_buffer #(.AUDIO_RATE(12000)) u_movie_audio (.write_clk(sd_clk),.write_valid(audio_write_valid),
        .write_bank(write_bank),.write_address(audio_write_address),.write_data(audio_write_data),
        .clk(pixel_clk),.rst(video_rst | ~video_pixel),.enabled(audio_enable_sync[1]),
        .paused(paused),.start(frame_started),.read_bank(read_bank),.sample_tick(audio_tick),
        .fps(audio_fps_sync),.busy(audio_busy),.pcm_sample(audio_pcm));
    video_frame_presenter #(.PIXEL_HZ(PIXEL_HZ),.TIMER_HZ(48000),.EXTERNAL_TICK(1),.AUDIO_SYNC(1)) u_movie_presenter (.clk(pixel_clk),.rst(video_rst | ~video_pixel),
        .vblank(x==0 && y==HEIGHT),.frame_start(x==0 && y==0),.paused(paused),
        .frame_toggle(frame_toggle),.fps(video_fps),.consumed_toggle(consumed_toggle),
        .audio_busy(audio_busy),.frame_started(frame_started),.timebase_tick(audio_tick),
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
    // Long reads supply 48 MHz pixels. Writes split at physical page and flipped-row boundaries.
    frame_read_write #(.BURST_SIZE(128),.SAFE_WRITE_BURSTS(1),.RUNTIME_V_FLIP(1),.WRITE_V_FLIP(1),.FRAME_WIDTH(WIDTH),.FRAME_HEIGHT(HEIGHT)) u_frame (
        .write_v_flip(~video_mem),.rst(mem_rst),.mem_clk(mem_clk),.Sdr_init_done(memory_initialized),
        .Sdr_init_ref_vld(memory_refresh),.Sdr_busy(memory_busy),
        .App_rd_en(app_rd_en),.App_rd_addr(app_rd_addr),
        .Sdr_rd_en(sdram_rd_valid),.Sdr_rd_dout(sdram_rd_data),
        .read_clk(pixel_clk),.read_req(read_req),.read_req_ack(read_ack),.read_finish(),
        .read_addr_0(21'd0),.read_addr_1(FRAME_PIXELS),.read_addr_2(21'd0),.read_addr_3(21'd0),
        .read_addr_index({1'b0,video_pixel & read_bank}),.read_len(FRAME_PIXELS),
        .read_en(fifo_read_en & show_image),.read_data(fifo_pixel),
        .App_wr_en(app_wr_en),.App_wr_addr(app_wr_addr),.App_wr_din(app_wr_data),.App_wr_dm(app_wr_mask),
        .write_clk(sd_clk),.write_req(write_req),.write_req_ack(write_ack),.write_finish(write_finish),
        .write_addr_0(21'd0),.write_addr_1(FRAME_PIXELS),.write_addr_2(21'd0),.write_addr_3(21'd0),
        .write_addr_index({1'b0,video_sd & write_bank}),.write_len(FRAME_PIXELS),.write_en(pixel_valid),.write_data(pixel_data));
    wire [20:0] scaled_rd_addr;
    image_scale_address #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_scale_address (.clk(mem_clk),.rst(mem_rst),.ack(read_ack),
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
    loading_spinner_rgb #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_loading_spinner (.pixel_clk(pixel_clk),.rst_n(~video_rst),
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
        .enabled(ENABLE_SPECTRUM && video_pixel && show_image && audio_enable_sync[1]),
        .sample_tick(audio_tick && !paused),.sample(audio_pcm[23:8]),.levels(spectrum_levels));
    integer coord_i;
    always @(posedge pixel_clk or posedge video_rst)begin
        if(video_rst)begin
            feature_frame<=4'b0011;spectrum_frame<=0;
            for(coord_i=0;coord_i<=20;coord_i=coord_i+1)begin output_x[coord_i]<=0;output_y[coord_i]<=0;end
        end else begin
            if(x==0 && y==HEIGHT)begin feature_frame<=feature_snapshot;spectrum_frame<=spectrum_levels;end
            output_x[0]<=x;output_y[0]<=y;
            for(coord_i=1;coord_i<=20;coord_i=coord_i+1)begin output_x[coord_i]<=output_x[coord_i-1];output_y[coord_i]<=output_y[coord_i-1];end
        end
    end
    wire subtitle_request,subtitle_panel,subtitle_ink;
    wire [15:0] subtitle_font_code;
    wire [3:0] subtitle_font_row;
    srt_subtitles u_srt_cache (.load_clk(sd_clk),.load_rst(movie_rst),.byte_data(sector_byte),
        .byte_valid(subtitle_byte_valid),.load_done(subtitle_done),.load_error(subtitle_error),
        .clk(pixel_clk),.rst(video_rst),.frame_start(x==0 && y==0),.frame_started(frame_started),
        .video_mode(video_pixel),.shown(show_image),.fps(audio_fps_sync),.movie_frames(movie_count_pixel),
        .read_index(subtitle_prefetch_x[8:4]),.codepoint(external_subtitle_codepoint),.visible(external_subtitle_visible));
    media_subtitles #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.FONT_LATENCY(2),.EXTERNAL_SRT(1)) u_subtitles (.clk(pixel_clk),.rst_n(~video_rst),
        .frame_start(x==0 && y==0),.frame_started(frame_started),.shown(show_image),
        .video_mode(video_pixel),.enabled(feature_frame[1]),.fps(audio_fps_sync),.zoom(zoom_frame),
        .x(x),.y(y),.de(de),.font_request(subtitle_request),
        .font_codepoint(subtitle_font_code),.font_row(subtitle_font_row),.font_pixels(status_font_pixels),
        .panel(subtitle_panel),.ink(subtitle_ink),.external_codepoint(external_subtitle_codepoint),.external_visible(external_subtitle_visible));
    // OLED and its glyph port remain alive during media reloads.
    (* async_reg="true", dont_touch="true" *) reg[2:0] oled_reset_pipe=0;
    (* dont_touch="true" *) wire oled_reset_request=core_reset_n & video_lock;
    always @(posedge pixel_clk or negedge oled_reset_request)
        if(!oled_reset_request)oled_reset_pipe<=0;else oled_reset_pipe<={oled_reset_pipe[1:0],1'b1};
    wire oled_reset_n=oled_reset_pipe[2];
    reg[87:0] oled_playing_name;reg image_name_seen;
    reg[3:0] load_ui_meta,load_ui_sync;
    wire[3:0] oled_diagnostic_status=(catalog_status_sys==4'd14) ? {1'b0,init_stage_sys} : load_ui_sync;
    always @(posedge sys_clk or negedge touch_reset_n)begin
        if(!touch_reset_n)begin oled_playing_name<=0;image_name_seen<=0;load_ui_meta<=0;load_ui_sync<=0;end
        else begin
            load_ui_meta<=load_status;load_ui_sync<=load_ui_meta;image_name_seen<=ready_sys_sync[1];
            if(open_file)oled_playing_name<=query_name;
            else if(!video_mode && ready_sys_sync[1] && !image_name_seen)oled_playing_name<=image_name;
        end
    end
    wire[121:0] oled_snapshot;
    ui_state_bridge #(.WIDTH(122)) u_oled_bridge(.source_clk(sys_clk),.source_reset_n(touch_reset_n),
        .source_data({oled_playing_name,catalog_done_sys[1],browser_visible,file_count_sys,selected_file,
            catalog_status_sys,oled_diagnostic_status,video_mode,(video_mode ? video_paused_setting : image_paused),
            interval_switch[0],interval_seconds_control,direction_switch,subtitles_setting,spectrum_setting,zoom_setting}),
        .destination_clk(pixel_clk),.destination_reset_n(oled_reset_n),.destination_data(oled_snapshot));
    wire[2:0] oled_page;wire[6:0] oled_column;
    wire oled_fetch,oled_byte_valid,oled_online,oled_address_3d;wire[7:0] oled_pixels;
    wire[15:0] oled_font_code;wire[3:0] oled_font_row;
    ssd1306_i2c #(.CLOCK_HZ(PIXEL_HZ)) u_oled_bus(.clk(pixel_clk),.reset_n(oled_reset_n),
        .scl(oled_scl),.sda(oled_sda),.page(oled_page),.column(oled_column),.fetch(oled_fetch),
        .valid(oled_byte_valid),.pixels(oled_pixels),.online(oled_online),.address_3d(oled_address_3d));
    oled_text_renderer u_oled_text(.clk(pixel_clk),.reset_n(oled_reset_n),.fetch(oled_fetch),
        .page(oled_page),.column(oled_column),.ui(oled_snapshot),.file_name(catalog_display_name),
        .display_index(catalog_display_index),.valid(oled_byte_valid),.pixels(oled_pixels),
        .font_code(oled_font_code),.font_row(oled_font_row),.font_pixels(browser_font_pixels));
    reg[15:0] font_code_a_pipe,font_code_b_pipe;
    reg[3:0] font_row_a_pipe,font_row_b_pipe;
    always @(posedge pixel_clk or posedge video_rst)
        if(video_rst)begin font_code_a_pipe<=32;font_row_a_pipe<=0;end
        else begin font_code_a_pipe<=subtitle_font_code;font_row_a_pipe<=subtitle_font_row;end
    always @(posedge pixel_clk or negedge oled_reset_n)
        if(!oled_reset_n)begin font_code_b_pipe<=32;font_row_b_pipe<=0;end
        else begin font_code_b_pipe<=oled_font_code;font_row_b_pipe<=oled_font_row;end
    osd_font16 u_shared_osd_font(.clk(pixel_clk),.codepoint(font_code_a_pipe),.row(font_row_a_pipe),
        .pixels(status_font_pixels),.codepoint_b(font_code_b_pipe),.row_b(font_row_b_pipe),.pixels_b(browser_font_pixels));
    reg[19:0] subtitle_panel_delay,subtitle_ink_delay;
    reg[23:0] loading_delay[0:20];integer i;
    always @(posedge pixel_clk or posedge video_rst)begin
        if(video_rst)begin
            subtitle_panel_delay<=0;subtitle_ink_delay<=0;
            for(i=0;i<=20;i=i+1)loading_delay[i]<=0;
        end else begin
            subtitle_panel_delay<={subtitle_panel_delay[18:0],subtitle_panel};
            subtitle_ink_delay<={subtitle_ink_delay[18:0],subtitle_ink};
            loading_delay[0]<=status_frame>=10 ? 24'd0 : loading_rgb;
            for(i=1;i<=20;i=i+1)loading_delay[i]<=loading_delay[i-1];
        end
    end
    wire small_margin=!video_pixel && zoom_frame==1 &&
        (output_x[20]<WIDTH/4 || output_x[20]>=WIDTH*3/4 || output_y[20]<HEIGHT/4 || output_y[20]>=HEIGHT*3/4);
    wire [23:0] scaled_rgb=small_margin ? 24'h000000 : image_rgb;
    wire [23:0] transition_rgb;
    wire [1:0] transition_effect;
    media_transition #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_transition (.clk(pixel_clk),.rst_n(~video_rst),
        .frame_start(x==0 && y==HEIGHT),.shown(show_image),.video_mode(video_pixel),
        .x(output_x[20]),.y(output_y[20]),.rgb_in(scaled_rgb),.rgb_out(transition_rgb),.effect(transition_effect));
    wire [23:0] media_base=video_pixel ? (show_image ? image_rgb : 24'h000000) :
                                      (show_image ? transition_rgb : loading_delay[20]);
    wire [23:0] subtitle_base=subtitle_ink_delay[18] ? 24'hfff3b0 :
        subtitle_panel_delay[18] ? {1'b0,media_base[23:17],1'b0,media_base[15:9],1'b0,media_base[7:1]} : media_base;
    wire spectrum_cover;
    wire [23:0] spectrum_rgb;wire [4:0] spectrum_color_index;wire [23:0] spectrum_decoded_rgb;reg [23:0] spectrum_delayed_rgb;
    audio_spectrum_overlay u_spectrum_overlay (.clk(pixel_clk),.rst_n(~video_rst),
        .x(x),.y(y),.de(de),.visible(ENABLE_SPECTRUM && feature_frame[0] && video_pixel && show_image && audio_enable_sync[1]),
        .levels(spectrum_frame),.active(spectrum_cover),.rgb(spectrum_rgb),.color_index(spectrum_color_index));
    reg [19:0] spectrum_cover_delay;
    reg [4:0] spectrum_delay[0:19];
    integer spectrum_i;
    always @(posedge pixel_clk or posedge video_rst)begin
        if(video_rst)begin
            spectrum_cover_delay<=0;
            for(spectrum_i=0;spectrum_i<20;spectrum_i=spectrum_i+1)spectrum_delay[spectrum_i]<=0;
        end else begin
            spectrum_cover_delay<={spectrum_cover_delay[18:0],spectrum_cover};
            spectrum_delay[0]<=spectrum_color_index;
            for(spectrum_i=1;spectrum_i<20;spectrum_i=spectrum_i+1)spectrum_delay[spectrum_i]<=spectrum_delay[spectrum_i-1];
        end
    end
    audio_spectrum_palette u_spectrum_delayed_palette(.index(spectrum_delay[18]),.rgb(spectrum_decoded_rgb));
    always @(posedge pixel_clk or posedge video_rst)
        if(video_rst)spectrum_delayed_rgb<=0;
        else spectrum_delayed_rgb<=spectrum_decoded_rgb;
    wire [23:0] visualized_rgb=spectrum_cover_delay[19] ? spectrum_delayed_rgb : subtitle_base;
    // Thin bottom progress track; coordinates are delayed to match the video pixels.
    wire progress_band=video_pixel && show_image && progress_configured &&
        output_y[20]>=HEIGHT-12 && output_y[20]<HEIGHT-6 &&
        output_x[20]>=32 && output_x[20]<WIDTH-32;
    wire progress_filled=(output_x[20]-32)<progress_position;
    wire [23:0] progress_rgb=progress_filled ? 24'h36d6c3 : 24'h35404a;
    wire[23:0] output_rgb=browser_pixel_sync[1] ? 24'h000000 :
        (progress_band ? progress_rgb : visualized_rgb);
    wire [23:0] volume_pcm;
    media_volume_apply u_volume_apply (.pcm_in(audio_pcm),.level(4'd8),.pcm_out(volume_pcm));
    hdmi_audio_oled_output #(.PIXEL_HZ(PIXEL_HZ),.TEST_AUDIO(0),.EXTERNAL_AUDIO(1),.FRAME_WIDTH(WIDTH),.FRAME_HEIGHT(HEIGHT),.HTOTAL(HTOTAL),.HSA(HSA),.HFP(HFP),.HBP(HBP),.VTOTAL(VTOTAL),.VSA(VSA),.VFP(VFP),.VBP(VBP),.VIDEO_VIC(0)) u_hdmi (.pixel_clk(pixel_clk),.serial_clk(serial_clk),
        .pcm_left(volume_pcm),.pcm_right(volume_pcm),.audio_tick(audio_tick),
        .rst(video_rst),.vs(delayed_vs),.de(delayed_de),.rgb(output_rgb),
        .clk_p(HDMI_CLK_P),.d0_p(HDMI_D0_P),.d1_p(HDMI_D1_P),.d2_p(HDMI_D2_P),
        .ddc_scl(HDMI_DDC_SCL),.ddc_sda(HDMI_DDC_SDA));
    assign HDMI_CLK_P1=HDMI_CLK_P;
    assign HDMI_D0_P1=HDMI_D0_P;
    assign HDMI_D1_P1=HDMI_D1_P;
    assign HDMI_D2_P1=HDMI_D2_P;
endmodule
