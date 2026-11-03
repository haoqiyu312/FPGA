#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
if command -v iverilog >/dev/null 2>&1;then compiler=(iverilog);runner=vvp
else
 tool="$HOME/.local/opt/iverilog"
 compiler=("$tool/bin/iverilog" -B "$tool/lib/x86_64-linux-gnu/ivl");runner="$tool/bin/vvp"
fi
work="$(mktemp -d /tmp/fpga-oled-test.XXXXXX)"
trap 'rm -rf -- "$work"' EXIT
"${compiler[@]}" -g2012 -s tb_matrix_keypad -o "$work/keys" rtl/matrix_keypad.v sim/tb_matrix_keypad.v
"$runner" "$work/keys"
"${compiler[@]}" -g2012 -i -s tb_oled_controls -o "$work/controls" rtl/tf_media_oled_top.v rtl/oled_file_menu.v rtl/matrix_keypad.v sim/tb_oled_controls.v
"$runner" "$work/controls"
for address in 0 1;do
 "${compiler[@]}" -g2012 -s tb_oled_panel -Ptb_oled_panel.ADDRESS_3D="$address" -o "$work/panel" rtl/ssd1306_i2c.v rtl/oled_text_renderer.v rtl/browser_ascii_font.v rtl/osd_font16.v sim/tb_oled_panel.v
 "$runner" "$work/panel"
done
"${compiler[@]}" -g2012 -i -s tb_oled_serial_reset -o "$work/serial_reset" rtl/hdmi_audio_oled_output.v rtl/oled_hdmi_phy.v rtl/vendor/hdmi_audio/lane_lvds_10_1.v sim/tb_oled_serial_reset.v
"$runner" "$work/serial_reset"
