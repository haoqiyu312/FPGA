#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
if command -v iverilog >/dev/null 2>&1;then compiler=(iverilog);runner=vvp
else
 tool="$HOME/.local/opt/iverilog"
 compiler=("$tool/bin/iverilog" -B "$tool/lib/x86_64-linux-gnu/ivl");runner="$tool/bin/vvp"
fi
work="$(mktemp -d /tmp/fpga-srt.XXXXXX)"
trap 'rm -rf -- "$work"' EXIT
"${compiler[@]}" -g2012 -s tb_srt -o "$work/srt" rtl/srt_subtitles.v rtl/media_subtitles.v sim/tb_srt_subtitles.v
"$runner" "$work/srt"
"${compiler[@]}" -g2012 -s tb_video_reader -Ptb_video_reader.SUBTITLE_SUPPORT=1 -Ptb_video_reader.EXTERNAL_NAME=1 -o "$work/reader" rtl/fat32_video_reader.v sim/tb_video_reader.v
for condition in '' '+srt_missing=1' '+srt_oversize=1' '+srt_broken=1';do
 "$runner" "$work/reader" $condition
done
"${compiler[@]}" -g2012 -s tb_square_video_reader -Ptb_square_video_reader.SUBTITLES=1 -o "$work/rvf2" rtl/fat32_video_reader.v sim/tb_square_video_reader.v
"$runner" "$work/rvf2"
"${compiler[@]}" -g2012 -s tb_palette_delay -o "$work/palette" rtl/audio_spectrum_overlay.v rtl/file_browser_overlay.v sim/tb_palette_delay.v
"$runner" "$work/palette"
