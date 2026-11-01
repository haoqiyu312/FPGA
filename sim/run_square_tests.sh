#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
/usr/bin/python3 -m unittest discover -s sim -p 'test_square_media.py'
if ! command -v iverilog >/dev/null || ! command -v vvp >/dev/null;then
 echo '720 RTL simulation not run: iverilog/vvp unavailable.' >&2
 exit 127
fi
square_test_dir="$(mktemp -d /tmp/fpga720-sim.XXXXXX)"
trap 'rm -rf "$square_test_dir"' EXIT
iverilog -g2012 -s tb_square_display -o "$square_test_dir/display" \
 rtl/video_timing_registered.v rtl/hdmi_video_stream.v rtl/video_audio_buffer.v sim/tb_square_display.v
vvp "$square_test_dir/display"
iverilog -g2012 -s tb_square_frame_write -o "$square_test_dir/write" \
 rtl/vendor/tf_reference/SD/frame_fifo_write.v sim/tb_square_frame_write.v
vvp "$square_test_dir/write"
iverilog -g2012 -s tb_square_video_reader -o "$square_test_dir/reader" \
 rtl/fat32_video_reader.v sim/tb_square_video_reader.v
for scenario in 0 1 2 3 4 5 6;do
 vvp "$square_test_dir/reader" +scenario="$scenario"
done
