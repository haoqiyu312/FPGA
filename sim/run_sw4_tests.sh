#!/bin/bash
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d /tmp/tf-sw4-test.XXXXXX)"
trap 'rm -rf -- "$work"' EXIT
if command -v iverilog >/dev/null 2>&1; then
    compiler=(iverilog); runner=vvp
elif [ -x "$HOME/.local/opt/iverilog/bin/iverilog" ]; then
    tool="$HOME/.local/opt/iverilog"
    compiler=("$tool/bin/iverilog" -B "$tool/lib/x86_64-linux-gnu/ivl")
    runner="$tool/bin/vvp"
else
    echo '缺少 iverilog/vvp，尚未运行 SW4 RTL 仿真。' >&2
    exit 127
fi
"${compiler[@]}" -g2012 -s tb_playback_osd_switch -o "$work/test" \
    "$root/rtl/tf_media_top.v" "$root/sim/tb_playback_osd_switch.v"
"$runner" "$work/test"
