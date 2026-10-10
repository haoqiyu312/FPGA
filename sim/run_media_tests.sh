#!/bin/bash
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
if command -v iverilog >/dev/null 2>&1;then
 compiler=(iverilog);runner=vvp
elif [ -x "$HOME/.local/opt/iverilog/bin/iverilog" ];then
 tool_dir="$HOME/.local/opt/iverilog"
 compiler=("$tool_dir/bin/iverilog" -B "$tool_dir/lib/x86_64-linux-gnu/ivl")
 runner="$tool_dir/bin/vvp"
else
 echo 'Media RTL simulation requires iverilog and vvp.' >&2
 exit 127
fi
test_dir="$(mktemp -d /tmp/tf-media-test.XXXXXX)"
trap 'rm -rf -- "$test_dir"' EXIT
"${compiler[@]}" -g2012 -s tb_media_keys -o "$test_dir/keys" \
 "$project_dir/rtl/key_debounce.v" "$project_dir/rtl/image_key_control.v" \
 "$project_dir/rtl/media_key_control.v" "$project_dir/sim/tb_media_keys.v"
"$runner" "$test_dir/keys"
"${compiler[@]}" -g2012 -s tb_media_frame_write -o "$test_dir/writer" \
 "$project_dir/rtl/vendor/tf_reference/SD/frame_fifo_write.v" "$project_dir/sim/tb_media_frame_write.v"
"$runner" "$test_dir/writer"
