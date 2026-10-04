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
for test in hdmi_audio hdmi_video_stream;do
 "${compiler[@]}" -g2012 -s "tb_$test" -o "$test_dir/$test" "$project_dir/rtl/hdmi_test_audio.v" "$project_dir/rtl/hdmi_video_stream.v" "$project_dir/sim/tb_$test.v"
 "$runner" "$test_dir/$test"
done
