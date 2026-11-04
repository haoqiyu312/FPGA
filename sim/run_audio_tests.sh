#!/bin/bash
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/tf-audio-test.XXXXXX)"
trap 'rm -rf -- "$test_dir"' EXIT
if command -v iverilog >/dev/null 2>&1; then
 compiler=(iverilog);runner=vvp
else
 tool_dir="$HOME/.local/opt/iverilog"
 compiler=("$tool_dir/bin/iverilog" -B "$tool_dir/lib/x86_64-linux-gnu/ivl")
 runner="$tool_dir/bin/vvp"
fi
"${compiler[@]}" -g2012 -s tb_hdmi_audio -o "$test_dir/hdmi_audio" \
 "$project_dir/rtl/hdmi_test_audio.v" "$project_dir/sim/tb_hdmi_audio.v"
"$runner" "$test_dir/hdmi_audio"
"${compiler[@]}" -g2012 -s tb_hdmi_video_stream -o "$test_dir/video_stream" \
 "$project_dir/rtl/hdmi_video_stream.v" "$project_dir/sim/tb_hdmi_video_stream.v"
"$runner" "$test_dir/video_stream"
"${compiler[@]}" -g2012 -s tb_audio_spectrum -o "$test_dir/spectrum" \
 "$project_dir/rtl/audio_spectrum.v" "$project_dir/sim/tb_audio_spectrum.v"
"$runner" "$test_dir/spectrum"
