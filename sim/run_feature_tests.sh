#!/bin/bash
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d /tmp/tf-features-test.XXXXXX)"
trap 'rm -rf -- "$work"' EXIT
if command -v iverilog >/dev/null 2>&1;then
 compiler=(iverilog);runner=vvp
elif [ -x "$HOME/.local/opt/iverilog/bin/iverilog" ];then
 tool="$HOME/.local/opt/iverilog"
 compiler=("$tool/bin/iverilog" -B "$tool/lib/x86_64-linux-gnu/ivl");runner="$tool/bin/vvp"
else
 echo '缺少 iverilog/vvp，尚未运行 RTL 仿真。' >&2
 exit 127
fi
for tb in tb_image_scale_address tb_media_transition tb_media_feature_keys tb_media_subtitles tb_media_feature_hints;do
 "${compiler[@]}" -g2012 -s "$tb" -o "$work/test" "$root/rtl/image_scale_address.v" "$root/rtl/media_transition.v" "$root/rtl/media_feature_keys.v" "$root/rtl/media_subtitles.v" "$root/rtl/osd_font16.v" "$root/rtl/image_status_osd.v" "$root/sim/tb_media_features.v"
 "$runner" "$work/test"
done
"${compiler[@]}" -g2012 -s tb_audio_spectrum -o "$work/spectrum" "$root/rtl/audio_spectrum.v" "$root/sim/tb_audio_spectrum.v"
"$runner" "$work/spectrum"
