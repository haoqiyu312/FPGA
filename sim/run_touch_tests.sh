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
"${compiler[@]}" -g2012 -s tb_touch_i2c -o "$test_dir/i2c" \
 "$project_dir/rtl/i2c_register_master.v" "$project_dir/sim/tb_touch_i2c.v"
"$runner" "$test_dir/i2c"
"${compiler[@]}" -g2012 -s tb_gt911_reader -o "$test_dir/reader" \
 "$project_dir/rtl/gt911_touch_reader.v" "$project_dir/rtl/touch_coordinate_map.v" \
 "$project_dir/sim/tb_gt911_reader.v"
"$runner" "$test_dir/reader"
"${compiler[@]}" -g2012 -s tb_touch_integration -o "$test_dir/integration" \
 "$project_dir/rtl/key_debounce.v" "$project_dir/rtl/media_key_control.v" \
 "$project_dir/rtl/media_volume.v" "$project_dir/rtl/ui_state_bridge.v" \
 "$project_dir/rtl/image_key_control.v" \
 "$project_dir/sim/tb_touch_integration.v"
"$runner" "$test_dir/integration"
