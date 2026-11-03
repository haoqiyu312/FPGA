create_clock -name sys_clk -period 20 [get_ports sys_clk]
derive_clocks
# Asynchronous assertion only; reset release chains and downstream logic remain timed.
set_false_path -through [get_nets {ready_clock}] -to [get_regs {sd_reset_pipe* mem_reset_pipe*}]
set_false_path -through [get_nets {video_ready}] -to [get_regs {video_reset_pipe*}]

# Browser mailbox toggles enter three-register synchronizers. Cut only the
# asynchronous input net; the following synchronizer stages remain timed.
set_false_path -through [get_nets {u_oled_bridge/ack u_ui_bridge/ack u_feature_bridge/ack}] -to [get_regs {u_oled_bridge/ack_sync* u_ui_bridge/ack_sync* u_feature_bridge/ack_sync*}]
set_false_path -through [get_nets {u_oled_bridge/request u_ui_bridge/request u_feature_bridge/request}] -to [get_regs {u_oled_bridge/request_sync* u_ui_bridge/request_sync* u_feature_bridge/request_sync*}]
# Catalog buses stop changing before done crosses two system clocks. These
# destinations are consumed only after done; catalog RAM stays immutable
# until KEY1 reset. No blanket clock-group exception is applied.
set_false_path -from [get_regs {u_catalog/count* u_catalog/status* u_catalog/image_count* u_catalog/bmp_index* u_catalog/debug_root_byte* u_catalog/debug_root_lba*}] -to [get_regs {file_count_sys* catalog_status_sys* debug_root_byte_sys* debug_root_lba_sys* total_meta*}]
# Existing frame-ready input already has a three-register synchronizer.
set_false_path -from [get_regs {u_movie_presenter/show_frame* show_picture*}] -to [get_regs {u_image_keys/ready_sync*}]

# Only the first-stage input is cut; second-stage completion synchronizers remain timed.
set_false_path -through [get_nets {catalog_done_sd}] -to [get_regs {catalog_done_sys* catalog_sync*}]

# Query words freeze after their 12-byte prefetch. A second tap cannot open
# before 64 system clocks (>1us); SD prefetch needs <20 clocks at 50MHz.
# Names/types/ordinals therefore settle before these event-enabled captures.
set_false_path -from [get_regs {u_catalog/query_data*}] -to [get_regs {requested_video* requested_image* u_browser/* u_media_keys/video_mode*}]

# These SD-domain status buses enter two-stage system-clock synchronizers.
# Loader status and fps drive display/error logic only after that pipeline.
set_false_path -through [get_nets {u_loader/status* u_movie_loader/status* u_movie_loader/fps* load_status*}] -to [get_clocks sys_clk]
# Pixel-domain frame-ready is sampled by ready_sync[0]; subsequent stages
# retain ordinary timing. Optimization may pack that flop into number logic.
set_false_path -through [get_nets {show_image}] -to [get_clocks sys_clk]

# The BMP loader's ready pulse enters ready_sys_sync[0] before system logic.
set_false_path -through [get_nets {u_loader/image_ready}] -to [get_clocks sys_clk]

# Zoom selection is held throughout a frame and sampled by two memory-clock
# stages before read_ack latches it. Only the asynchronous first stage is cut.
set_false_path -from [get_regs {feature_frame*}] -to [get_regs {u_scale_address/zoom_meta*}]

# R2: 48 MHz video is not phase synchronous with 50 MHz system/memory.
# Only reviewed first synchronizer inputs are exempt; later stages stay timed.
set_false_path -from [get_clocks {sys_clk u_memory_pll/pll_inst.clkc[0] u_memory_pll/pll_inst.clkc[1]}] -to [get_regs {u_status_osd/meta* u_status_osd/name_meta*}]
set_false_path -through [get_nets {read_ack}] -to [get_regs {ack_sync* u_movie_presenter/ack_sync*}]
set_false_path -through [get_nets {u_movie_presenter/consumed_toggle}] -to [get_regs {u_movie_loader/consumed_sync*}]
set_false_path -from [get_clocks {u_video_pll/pll_inst.clkc[1]}] -to [get_regs {u_frame/frame_fifo_read_m0/read_addr_index_d0*}]
# Registered Gray pointers: limit each crossing to one 20 ns source period.
# Do not waive timing on the second-stage synchronizer or Gray decoding.
set_max_delay 20 -from [get_regs {u_frame/read_buf/wr_to_rd_cross_inst/primary_addr_gray_reg*}] -to [get_regs {u_frame/read_buf/wr_to_rd_cross_inst/sync_r1*}]
set_max_delay 20 -from [get_regs {u_frame/read_buf/rd_to_wr_cross_inst/primary_addr_gray_reg*}] -to [get_regs {u_frame/read_buf/rd_to_wr_cross_inst/sync_r1*}]
# FIFO clear is asynchronously asserted and synchronously released by two flops.
set_false_path -through [get_nets {u_frame/read_fifo_aclr}] -to [get_regs {u_frame/read_buf/asy_r_rst*}]

# Additional existing two/three-stage display synchronizers, exposed after
# longer text paths were removed. Sources enter only their first stage.
set_false_path -through [get_nets {load_status*}] -to [get_regs {status_meta*}]
set_false_path -through [get_nets {image_ready}] -to [get_regs {image_sync*}]
# read_req is a pixel-domain mode mux; physical packing can absorb that mux
# into the first memory-domain request flop. Keep its input boundary explicit.
set_false_path -from [get_clocks {u_video_pll/pll_inst.clkc[1]}] -to [get_regs {u_frame/frame_fifo_read_m0/read_req_d0*}]

# Mailboxes hold payload unchanged until the synchronized request has been
# received (three pixel clocks) and acknowledged. Bound payload arrival to
# one source period instead of the unrelated 0.834 ns clock-edge separation.
set_max_delay 20 -through [get_nets {u_oled_bridge/mailbox* u_ui_bridge/mailbox* u_feature_bridge/mailbox*}] -to [get_clocks {u_video_pll/pll_inst.clkc[1]}]
set_false_path -from [get_clocks {sys_clk}] -to [get_regs {u_status_osd/dir_meta* u_status_osd/video_meta* mode_pixel* pause_sync*}]
set_false_path -from [get_clocks {u_memory_pll/pll_inst.clkc[0]}] -to [get_regs {status_meta* image_sync* u_catalog/display_done* u_movie_presenter/fps_meta* audio_fps_meta* audio_enable_sync* u_movie_presenter/frame_sync*}]

# SRT count freezes before finished is raised, then enters a two-flop pixel
# snapshot. Ready crosses three flops; scan logic consumes the count only after
# ready. Cut source-to-first-stage inputs, keeping pixel pipeline timing active.
set_false_path -from [get_clocks {u_memory_pll/pll_inst.clkc[0]}] -to [get_regs {u_srt_cache/count_meta* u_srt_cache/ready_sync* movie_count_meta*}]

# OLED reset synchronously releases in the pixel domain, independent of media resets.
set_false_path -through [get_nets {oled_reset_request}] -to [get_regs {oled_reset_pipe*}]

# Filename payloads are held stable before guarded capture: catalog query has
# a 64-clock settle guard; BMP name precedes ready_sys_sync by the whole load.
set_false_path -from [get_regs {u_catalog/query_data* u_loader/image_name*}] -to [get_regs {oled_playing_name*}]

# HDMI pixel reset enters a three-flop asynchronous-assert / serial-clock
# synchronous-release bridge. Later serial stages and DDR outputs stay timed.
set_false_path -from [get_clocks {u_video_pll/pll_inst.clkc[1]}] -to [get_regs {u_hdmi/serial_reset_pipe*}]
