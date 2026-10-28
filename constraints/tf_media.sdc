create_clock -name sys_clk -period 20 [get_ports sys_clk]
derive_clocks
# Asynchronous assertion only; reset release chains and downstream logic remain timed.
set_false_path -through [get_nets {ready_clock}] -to [get_regs {sd_reset_pipe* mem_reset_pipe*}]
set_false_path -through [get_nets {video_ready}] -to [get_regs {video_reset_pipe*}]

# Browser mailbox toggles enter three-register synchronizers. Cut only the
# asynchronous input net; the following synchronizer stages remain timed.
set_false_path -through [get_nets {u_browser_bridge/ack u_ui_bridge/ack u_feature_bridge/ack}] -to [get_regs {u_browser_bridge/ack_sync* u_ui_bridge/ack_sync* u_feature_bridge/ack_sync*}]
set_false_path -through [get_nets {u_browser_bridge/request u_ui_bridge/request u_feature_bridge/request}] -to [get_regs {u_browser_bridge/request_sync* u_ui_bridge/request_sync* u_feature_bridge/request_sync*}]
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
