#!/bin/bash
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/tf-catalog-test.XXXXXX)"
trap 'rm -rf -- "$test_dir"' EXIT
python3 - "$project_dir/media/PIC01.BMP" "$test_dir/bmp_bytes.hex" <<'PYCODE'
import sys
from pathlib import Path
b=Path(sys.argv[1]).read_bytes()
if len(b)!=921654:raise SystemExit('PIC01.BMP文件大小错误')
Path(sys.argv[2]).write_text(''.join(f'{x:02x}\n' for x in b))
PYCODE
if command -v iverilog >/dev/null 2>&1; then
 compiler=(iverilog);runner=vvp
else
 tool_dir="$HOME/.local/opt/iverilog"
 compiler=("$tool_dir/bin/iverilog" -B "$tool_dir/lib/x86_64-linux-gnu/ivl")
 runner="$tool_dir/bin/vvp"
fi
"${compiler[@]}" -g2012 -s tb_catalog -o "$test_dir/catalog" "$project_dir/rtl/fat32_bmp_loader.v" "$project_dir/sim/tb_catalog.v"
cd "$test_dir"
for image in 0 1 2 3 31;do "$runner" ./catalog +image="$image";done
for scenario in 1 2;do "$runner" ./catalog +scenario="$scenario";done
"$runner" ./catalog +scenario=3 +image=31
"${compiler[@]}" -g2012 -s tb_loader_timeout -o timeout "$project_dir/rtl/fat32_bmp_loader.v" "$project_dir/sim/tb_loader_timeout.v"
"$runner" ./timeout
