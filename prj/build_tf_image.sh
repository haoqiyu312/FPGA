#!/bin/bash
set -eu
cd "$(dirname "$0")"
if [ -n "${TD_BIN:-}" ];then
 td_program="$TD_BIN"
elif command -v td.sh >/dev/null 2>&1;then
 td_program="$(command -v td.sh)"
else
 td_program="$HOME/.local/opt/TD_Release_2026.2_NL/bin/td.sh"
fi
if [ ! -x "$td_program" ];then
 echo '找不到 TD 编译工具。请设置 TD_BIN=/你的TD安装目录/bin/td.sh' >&2
 exit 1
fi
exec "$td_program" build_tf_image.tcl
