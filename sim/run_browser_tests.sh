#!/bin/bash
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d /tmp/tf-browser-test.XXXXXX)"
trap 'rm -rf -- "$work"' EXIT
if command -v iverilog >/dev/null 2>&1;then
 compiler=(iverilog);runner=vvp
else
 tool="$HOME/.local/opt/iverilog"
 compiler=("$tool/bin/iverilog" -B "$tool/lib/x86_64-linux-gnu/ivl");runner="$tool/bin/vvp"
fi
"${compiler[@]}" -g2012 -s tb_audio_spectrum -o "$work/spectrum" "$root/rtl/audio_spectrum.v" "$root/sim/tb_audio_spectrum.v"
"$runner" "$work/spectrum"
"${compiler[@]}" -g2012 -s tb_media_catalog -o "$work/catalog" "$root/rtl/fat32_media_catalog.v" "$root/sim/tb_media_catalog.v"
"$runner" "$work/catalog"
"${compiler[@]}" -g2012 -s tb_sd_ready_handshake -o "$work/sd_ready" "$root/rtl/vendor/tf_reference/SD/sd_card_sec_read_write.v" "$root/sim/tb_sd_ready_handshake.v"
"$runner" "$work/sd_ready"
"${compiler[@]}" -g2012 -s tb_file_browser -o "$work/browser" "$root/rtl/touch_file_browser.v" "$root/sim/tb_file_browser.v"
"$runner" "$work/browser"
"${compiler[@]}" -g2012 -s tb_browser_render -o "$work/render" "$root/rtl/fat32_media_catalog.v" "$root/rtl/browser_ascii_font.v" "$root/rtl/osd_font16.v" "$root/rtl/file_browser_overlay.v" "$root/sim/tb_browser_render.v"
(cd "$work"; "$runner" "$work/render")
cp "$work/browser.ppm" "$work/direct.ppm"
"${compiler[@]}" -g2012 -s tb_browser_render -Ptb_browser_render.SERIAL_METADATA=1 -o "$work/serial_render" "$root/rtl/fat32_media_catalog.v" "$root/rtl/browser_ascii_font.v" "$root/rtl/osd_font16.v" "$root/rtl/file_browser_overlay.v" "$root/sim/tb_browser_render.v"
(cd "$work"; "$runner" "$work/serial_render")
cmp "$work/direct.ppm" "$work/browser.ppm"
echo 'PASS full-frame serial BRAM metadata rendering matches direct catalog pixels'
if [ -n "${BROWSER_PREVIEW:-}" ];then cp "$work/browser.ppm" "$BROWSER_PREVIEW";fi

"${compiler[@]}" -g2012 -s tb_video_reader -Ptb_video_reader.EXTERNAL_NAME=1 -o "$work/named_video" "$root/rtl/fat32_video_reader.v" "$root/sim/tb_video_reader.v"
"$runner" "$work/named_video" +scenario=0
"${compiler[@]}" -g2012 -s tb_browser_open -o "$work/open" "$root/rtl/key_debounce.v" "$root/rtl/media_key_control.v" "$root/rtl/image_key_control.v" "$root/sim/tb_browser_open.v"
"$runner" "$work/open"
"${compiler[@]}" -g2012 -s tb_browser_autoplay -o "$work/autoplay" "$root/rtl/key_debounce.v" "$root/rtl/image_key_control.v" "$root/sim/tb_browser_open.v"
"$runner" "$work/autoplay"
"${compiler[@]}" -g2012 -s tb_browser_mode_keys -o "$work/modekeys" "$root/rtl/key_debounce.v" "$root/rtl/media_key_control.v" "$root/sim/tb_browser_open.v"
"$runner" "$work/modekeys"
"${compiler[@]}" -g2012 -s tb_browser_prefetch_guard -o "$work/guard" "$root/rtl/touch_file_browser.v" "$root/sim/tb_browser_open.v"
"$runner" "$work/guard"
