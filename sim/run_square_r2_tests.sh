#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
/usr/bin/python3 -m unittest discover -s sim -p 'test_square_media.py'
if ! command -v iverilog >/dev/null || ! command -v vvp >/dev/null;then
 echo '720 R2 RTL simulation NOT RUN: iverilog/vvp unavailable.' >&2
 exit 127
fi
square_r2_test_dir="$(mktemp -d /tmp/fpga720-r2-sim.XXXXXX)"
trap 'rm -rf "$square_r2_test_dir"' EXIT
iverilog -g2012 -s tb_square_r2_frame_write -o "$square_r2_test_dir/write" \
 rtl/vendor/tf_reference/SD/frame_fifo_write.v sim/tb_square_r2_frame_write.v
vvp "$square_r2_test_dir/write"
iverilog -g2012 -s tb_square_r2_audio_clock -o "$square_r2_test_dir/audio" \
 rtl/hdmi_test_audio.v sim/tb_square_r2_audio_clock.v
vvp "$square_r2_test_dir/audio"
iverilog -g2012 -s tb_square_r2_display -o "$square_r2_test_dir/display" \
 rtl/video_timing_registered.v rtl/hdmi_video_stream.v rtl/video_audio_buffer.v sim/tb_square_r2_display.v
vvp "$square_r2_test_dir/display"
iverilog -g2012 -s tb_square_r2_font_pipeline -o "$square_r2_test_dir/font" \
 rtl/osd_font16.v rtl/browser_ascii_font.v rtl/image_status_osd.v rtl/file_browser_overlay.v sim/tb_square_r2_font_pipeline.v
vvp "$square_r2_test_dir/font"
