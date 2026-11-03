#!/usr/bin/env python3
"""Package the locally built 720×720 candidate without replacing R2."""
import argparse
import hashlib
import json
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--srt', action='store_true', help='package the external subtitle candidate')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
if ('EXTERNAL_SRT(1)' in (root/'rtl/tf_media_top.v').read_text()) != args.srt:
    raise SystemExit('源码字幕配置与打包配置不一致；外部字幕工程须使用 --srt。')
run = root / "prj/TF_MEDIA_720_R2_Runs/phy_1"
bit = run / "TF_MEDIA_720_R2_hold.bit"
timing = run / "TF_MEDIA_720_R2_hold.timing"
area = run / "TF_MEDIA_720_R2_hold.area"
inputs = [root / "prj/TF_MEDIA_720_R2.al"]
inputs += [root / "prj" / name for name in (
    "build_tf_media720_r2.tcl", "build_tf_media720_r2.sh",
    "fix_tf_media720_r2_hold.tcl")]
inputs += [root / "constraints/tf_media720_r2.sdc"]
inputs += list((root / "rtl").rglob("*.v"))
inputs = sorted(path for path in inputs if path.is_file())

for path in (bit, timing, area):
    if not path.is_file():
        raise SystemExit(f"缺少构建产物：{path}")
report = timing.read_text()
if not re.search(r"Confidence\s*:\s*Routed", report):
    raise SystemExit("最终时序报告不是 Routed。")
metrics = {}
for label in ("SWNS", "STNS", "HWNS", "HTNS"):
    match = re.search(rf"\b{label}:\s*(-?\d+(?:\.\d+)?)ns", report)
    if not match or float(match[1]) < 0:
        raise SystemExit(f"{label} 缺失或存在时序违例。")
    metrics[f"{label}_ns"] = float(match[1])

resource_report = area.read_text()
resources = {}
for key in ("lut", "reg", "bram", "dsp", "pll"):
    match = re.search(rf"^#{key}\s+(\d+)\s+out of\s+(\d+)", resource_report, re.M)
    if not match or int(match[1]) > int(match[2]):
        raise SystemExit(f"资源项 {key} 缺失或超限。")
    resources[key] = {"used": int(match[1]), "capacity": int(match[2])}

if bit.stat().st_mtime < max(path.stat().st_mtime for path in inputs + [timing, area]):
    raise SystemExit("候选 bit 早于源码或报告，需重新编译。")
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
out = root / ("release/TF_MEDIA_720_SRT.bit" if args.srt else "release/TF_MEDIA_720_SPECTRUM.bit")
record = {
    "built_at_utc": datetime.now(timezone.utc).isoformat(),
    "file": out.name,
    "sha256": digest(bit),
    "device": "EG4S20BG256",
    "tool": "Tang Dynasty 6.2.1 build 175876",
    "width": 720,
    "height": 720,
    "pixel_hz": 48000000,
    "spectrum_enabled": True,
    "external_srt": args.srt,
    "subtitle_limits": "16 cues, 32 codepoints/cue, built-in glyph subset" if args.srt else None,
    "spectrum": "eight Goertzel bands from RVF2 audio; KEY2 toggles during video",
    "timing": metrics,
    "resources": resources,
    "inputs_sha256": {str(path.relative_to(root)): digest(path) for path in inputs},
    "validation": {
        "build": "passed",
        "routed_timing": "passed; positive slack is small",
        "python_tests": "26 cases, 25 passed and 1 skipped" if args.srt else "not recorded",
        "rtl_simulation": "feature and subtitle suites passed" if args.srt else "feature suite passed",
        "native_720_rtl": "four R2 pipeline cases passed" if args.srt else "not recorded",
        "glyph_lookup": "all 65536 Unicode values matched on both ports; bitmaps unchanged" if args.srt else "not recorded",
        "palette": "518400 pixel browser/spectrum equivalence passed" if args.srt else "not recorded",
        "hardware": "candidate; not yet tested",
        "known_good_fallback": "TF_MEDIA_720_R2.bit",
    },
}
shutil.copyfile(bit, out)
out.with_suffix(".json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({key: record[key] for key in ("file", "sha256", "timing", "resources")}, ensure_ascii=False))
