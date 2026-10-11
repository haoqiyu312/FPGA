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
 echo 'Touch RTL simulation requires iverilog and vvp.' >&2
 exit 127
fi
test_dir="$(mktemp -d /tmp/tf-touch-test.XXXXXX)"
trap 'rm -rf -- "$test_dir"' EXIT
"${compiler[@]}" -g2012 -s tb_touch_menu -o "$test_dir/menu" \
 "$project_dir/rtl/touch_menu_hit.v" "$project_dir/rtl/touch_menu_control.v" \
 "$project_dir/rtl/touch_menu_overlay.v" "$project_dir/sim/tb_touch_menu.v"
"$runner" "$test_dir/menu"
