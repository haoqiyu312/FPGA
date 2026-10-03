#!/bin/bash
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/tf-loader-test.XXXXXX)"
trap 'rm -rf -- "$test_dir"' EXIT
python3 - "$project_dir/media/PIC01.BMP" "$test_dir/bmp_bytes.hex" <<'PYCODE'
import sys
from pathlib import Path
b=Path(sys.argv[1]).read_bytes()
if len(b)!=921654: raise SystemExit('PIC01.BMP文件大小错误')
Path(sys.argv[2]).write_text(''.join(f'{x:02x}\n' for x in b))
PYCODE
if command -v iverilog >/dev/null 2>&1; then
  compiler=(iverilog)
  runner=vvp
else
  tool_dir="$HOME/.local/opt/iverilog"
  compiler=("$tool_dir/bin/iverilog" -B "$tool_dir/lib/x86_64-linux-gnu/ivl")
  runner="$tool_dir/bin/vvp"
fi
"${compiler[@]}" -g2012 -s tb_fat32_bmp_loader -o "$test_dir/loader_test" "$project_dir/rtl/fat32_bmp_loader.v" "$project_dir/sim/tb_fat32_bmp_loader.v"
cd "$test_dir"
for image in 0 1 2 3; do "$runner" ./loader_test +scenario=0 +image="$image"; done
for scenario in 5 2 3 4; do "$runner" ./loader_test +scenario="$scenario" +image=3; done
