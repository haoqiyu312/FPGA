// FAT32 VIDEO.RV -> double-buffered SDRAM -> HDMI.
// KEY1 resets; KEY4 pauses. Both HDMI ports mirror silent video; use HDMI_B.
module tf_video_top (
    input wire sys_clk, input wire sys_rst_n,
    input wire key_next_n, key_prev_n, key_auto_n,
    input wire [1:0] interval_switch,
    input wire direction_switch,
    output wire [7:0] seg_n,digit_en,
    output wire buzzer_n,
    output wire HDMI_CLK_P, HDMI_D0_P, HDMI_D1_P, HDMI_D2_P,
    output wire HDMI_CLK_P1, HDMI_D0_P1, HDMI_D1_P1, HDMI_D2_P1,
    output wire HDMI_DDC_SCL, inout wire HDMI_DDC_SDA,
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
    wire startup_done;
    wire run_reset_n=sys_rst_n;
    tf_startup_control u_startup (.clk(sys_clk),.reset_n(run_reset_n),
        .locked(video_lock & memory_lock),.load_error(1'b0),
        .run_enable(startup_done),.fast_start(1'b0));
    (* dont_touch="true" *) wire ready_clock=sys_rst_n & startup_done & video_lock & memory_lock;
    (* async_reg="true" *) reg [2:0] sd_reset_pipe=0,mem_reset_pipe=0,video_reset_pipe=0;
    always @(posedge sd_clk or negedge ready_clock)
        if(!ready_clock)sd_reset_pipe<=0;else sd_reset_pipe<={sd_reset_pipe[1:0],1'b1};
    always @(posedge mem_clk or negedge ready_clock)
        if(!ready_clock)mem_reset_pipe<=0;else mem_reset_pipe<={mem_reset_pipe[1:0],1'b1};
    always @(posedge pixel_clk or negedge ready_clock)
        if(!ready_clock)video_reset_pipe<=0;else video_reset_pipe<={video_reset_pipe[1:0],1'b1};
    wire sd_rst=~sd_reset_pipe[2],mem_rst=~mem_reset_pipe[2],video_rst=~video_reset_pipe[2];
    wire write_bank,read_bank,frame_toggle,consumed_toggle;
    wire [7:0] video_fps;
    wire show_image;
    wire paused;
    wire pause_event;
    key_debounce u_pause (.clk(pixel_clk),.reset_n(~video_rst),
        .key_n(key_auto_n),.pressed(pause_event));
    reg pause_reg;
    always @(posedge pixel_clk or posedge video_rst)
        if(video_rst)pause_reg<=0;else if(pause_event)pause_reg<=~pause_reg;
    assign paused=pause_reg;
    // Diagnostic number: status 0..5 normal; 10..15 errors (see video documentation).
    reg [3:0] status_meta,status_sync;
    reg [7:0] fps_meta,fps_sync;
    always @(posedge sys_clk or negedge sys_rst_n)
        if(!sys_rst_n)begin status_meta<=0;status_sync<=0;fps_meta<=5;fps_sync<=5;end
        else begin status_meta<=load_status;status_sync<=status_meta;fps_meta<=video_fps;fps_sync<=fps_meta;end
    image_number_display #(.RAW_INDEX(1)) u_status (.clk(sys_clk),.reset_n(sys_rst_n),
        .image_index({1'b0,status_sync}),.total_count(fps_sync[5:0]),.seg_n(seg_n),.digit_en(digit_en));

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
    fat32_video_reader u_loader (
        .clk(sd_clk),.rst(sd_rst),.sd_ready(sd_ready),.memory_ready(memory_init_sync[1]),
        .sector_req(sector_req),.sector_lba(sector_lba),.sector_byte(sector_byte),
        .sector_valid(sector_valid),.sector_end(sector_end),
        .write_req(write_req),.write_ack(write_ack_sync[2]),.pixel_valid(pixel_valid),
        .pixel_data(pixel_data),.write_finish_toggle(finish_toggle),
        .frame_toggle(frame_toggle),.consumed_toggle(consumed_toggle),
        .write_bank(write_bank),.status(load_status),.fps(video_fps));
    wire [9:0] x,y;
    wire de,hs,vs;
    video_timing_640x480 u_timing (.pixel_clk(pixel_clk),.rst_n(~video_rst),
        .pixel_x(x),.pixel_y(y),.de(de),.hsync(hs),.vsync(vs));
    wire read_ack,read_req;
    video_frame_presenter u_presenter (.clk(pixel_clk),.rst(video_rst),
        .vblank(x==0 && y==480),.frame_start(x==0 && y==0),.paused(paused),
        .frame_toggle(frame_toggle),.fps(video_fps),.consumed_toggle(consumed_toggle),
        .read_bank(read_bank),.read_req(read_req),.read_ack(read_ack),.show_frame(show_image));
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
    // Two full RGB888 buffers; input frames are already top-down.
    frame_read_write #(.BURST_SIZE(128),.WRITE_V_FLIP(0),.FRAME_WIDTH(640),.FRAME_HEIGHT(480)) u_frame (
        .rst(mem_rst),.mem_clk(mem_clk),.Sdr_init_done(memory_initialized),
        .Sdr_init_ref_vld(memory_refresh),.Sdr_busy(memory_busy),
        .App_rd_en(app_rd_en),.App_rd_addr(app_rd_addr),
        .Sdr_rd_en(sdram_rd_valid),.Sdr_rd_dout(sdram_rd_data),
        .read_clk(pixel_clk),.read_req(read_req),.read_req_ack(read_ack),.read_finish(),
        .read_addr_0(21'd0),.read_addr_1(21'd307200),.read_addr_2(21'd0),.read_addr_3(21'd0),
        .read_addr_index({1'b0,read_bank}),.read_len(21'd307200),
        .read_en(fifo_read_en & show_image),.read_data(fifo_pixel),
        .App_wr_en(app_wr_en),.App_wr_addr(app_wr_addr),.App_wr_din(app_wr_data),.App_wr_dm(app_wr_mask),
        .write_clk(sd_clk),.write_req(write_req),.write_req_ack(write_ack),.write_finish(write_finish),
        .write_addr_0(21'd0),.write_addr_1(21'd307200),.write_addr_2(21'd0),.write_addr_3(21'd0),
        .write_addr_index({1'b0,write_bank}),.write_len(21'd307200),.write_en(pixel_valid),.write_data(pixel_data));
    sdram u_sdram (.Clk(mem_clk),.Clk_sft(mem_clk_shift),.Rst(mem_rst),
        .Sdr_init_done(memory_initialized),.Sdr_init_ref_vld(memory_refresh),.Sdr_busy(memory_busy),
        .App_wr_en(app_wr_en),.App_wr_addr(app_wr_addr),.App_wr_dm(app_wr_mask),.App_wr_din(app_wr_data),
        .App_rd_en(app_rd_en),.App_rd_addr(app_rd_addr),.Sdr_rd_en(sdram_rd_valid),.Sdr_rd_dout(sdram_rd_data));

    wire [23:0] output_rgb=show_image ? image_rgb : 24'h000000;
    hdmi_audio_output #(.TEST_AUDIO(0)) u_hdmi (.pixel_clk(pixel_clk),.serial_clk(serial_clk),
        .rst(video_rst),.vs(delayed_vs),.de(delayed_de),.rgb(output_rgb),
        .clk_p(HDMI_CLK_P),.d0_p(HDMI_D0_P),.d1_p(HDMI_D1_P),.d2_p(HDMI_D2_P),
        .ddc_scl(HDMI_DDC_SCL),.ddc_sda(HDMI_DDC_SDA));
    assign HDMI_CLK_P1=HDMI_CLK_P;
    assign HDMI_D0_P1=HDMI_D0_P;
    assign HDMI_D1_P1=HDMI_D1_P;
    assign HDMI_D2_P1=HDMI_D2_P;
endmodule
