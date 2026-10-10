#!/bin/bash
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$project_dir/sim/test_audio_video_converter.py"
if command -v iverilog >/dev/null 2>&1;then
 compiler=(iverilog);runner=vvp
elif [ -x "$HOME/.local/opt/iverilog/bin/iverilog" ];then
 tool_dir="$HOME/.local/opt/iverilog"
 compiler=("$tool_dir/bin/iverilog" -B "$tool_dir/lib/x86_64-linux-gnu/ivl")
 runner="$tool_dir/bin/vvp"
else
 echo 'Audio/video RTL simulation requires iverilog and vvp; converter tests completed.' >&2
 exit 127
fi
test_dir="$(mktemp -d /tmp/tf-av-test.XXXXXX)"
trap 'rm -rf -- "$test_dir"' EXIT
"${compiler[@]}" -g2012 -s tb_video_audio_buffer -o "$test_dir/audio" \
 "$project_dir/rtl/video_audio_buffer.v" "$project_dir/sim/tb_video_audio_buffer.v"
"$runner" "$test_dir/audio" +vectors="$project_dir/sim/mulaw_pcm16.hex"
"${compiler[@]}" -g2012 -s tb_audio_presenter -o "$test_dir/presenter" \
 "$project_dir/rtl/video_frame_presenter.v" "$project_dir/sim/tb_audio_presenter.v"
"$runner" "$test_dir/presenter"
"${compiler[@]}" -g2012 -s tb_audio_video_reader -o "$test_dir/reader" \
 "$project_dir/rtl/fat32_video_reader.v" "$project_dir/sim/tb_audio_video_reader.v"
for scenario in 0 1 2 3 4 5 6;do "$runner" "$test_dir/reader" +scenario="$scenario";done
"${compiler[@]}" -g2012 -s tb_video_reader -P tb_video_reader.AUDIO_SUPPORT=1 -o "$test_dir/legacy" \
 "$project_dir/rtl/fat32_video_reader.v" "$project_dir/sim/tb_video_reader.v"
"$runner" "$test_dir/legacy" +scenario=0
