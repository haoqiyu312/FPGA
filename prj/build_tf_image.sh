#!/bin/bash
set -eu
cd "$(dirname "$0")"
if [ -n "${TD_BIN:-}" ];then
 td_program="$TD_BIN"
elif [ -x "$HOME/.local/opt/TD_6.2.1_Release_175876_NL/bin/td.sh" ];then
 td_program="$HOME/.local/opt/TD_6.2.1_Release_175876_NL/bin/td.sh"
elif command -v td.sh >/dev/null 2>&1;then
 td_program="$(command -v td.sh)"
else
 td_program="$HOME/.local/opt/TD_6.2.1_Release_175876_NL/bin/td.sh"
fi
if [ ! -x "$td_program" ];then
 echo '找不到 TD 编译工具。请设置 TD_BIN=/你的TD安装目录/bin/td.sh' >&2
 exit 1
fi
td_version="$("$td_program" -version)"
if ! printf '%s\n' "$td_version" | grep -Eq '^Release: 6\.2\.1[[:space:]]*$';then
 echo "本项目必须使用 TD 6.2.1，当前工具版本：$td_version" >&2
 exit 1
fi
printf '%s\n' "$td_version"
build_stamp="$(mktemp)"
trap 'rm -f "$build_stamp"' EXIT
"$td_program" build_tf_image.tcl
bit_file="TF_IMAGE_Runs/phy_1/TF_IMAGE.bit"
if [ ! -s "$bit_file" ] || [ ! "$bit_file" -nt "$build_stamp" ];then
 echo 'TD 未生成本次编译的新 bit 文件，请检查运行日志。' >&2
 exit 1
fi
timing_report="TF_IMAGE_Runs/phy_1/final_timing.rpt"
if [ ! -s "$timing_report" ] || [ ! "$timing_report" -nt "$build_stamp" ];then
 echo '缺少本次编译的最终时序报告。' >&2
 exit 1
fi
if grep -Eq '(SWNS|HWNS):[[:space:]]*-[0-9]' "$timing_report";then
 echo '最终时序存在建立或保持违例，请检查 final_timing.rpt。' >&2
 exit 1
fi
printf '已生成：%s/%s\n' "$PWD" "$bit_file"
