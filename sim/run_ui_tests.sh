#!/bin/bash
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/tf-ui-test.XXXXXX)"
trap 'rm -rf -- "$test_dir"' EXIT
if command -v iverilog >/dev/null 2>&1; then
 compiler=(iverilog);runner=vvp
else
 tool_dir="$HOME/.local/opt/iverilog"
 compiler=("$tool_dir/bin/iverilog" -B "$tool_dir/lib/x86_64-linux-gnu/ivl")
 runner="$tool_dir/bin/vvp"
fi
for tb in tb_image_keys tb_auto tb_direction tb_switch_debounce tb_dynamic_keys tb_image_number tb_osd;do
 "${compiler[@]}" -g2012 -s "$tb" -o "$test_dir/test" "$project_dir/rtl/image_key_control.v" "$project_dir/rtl/image_number_display.v" "$project_dir/rtl/image_status_osd.v" "$project_dir/rtl/osd_font16.v" "$project_dir/rtl/key_debounce.v" "$project_dir/sim/$tb.v"
 "$runner" "$test_dir/test"
done
