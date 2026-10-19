#!/usr/bin/env python3
"""Package a routed and timing-clean local TF_MEDIA browser bitstream."""
import hashlib
import json
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path

root = Path(__file__).resolve().parents[1]
run = root / 'prj/TF_MEDIA_Runs/phy_1'
bit = run / 'TF_MEDIA_hold.bit'
timing = run / 'TF_MEDIA_hold.timing'
area = run / 'TF_MEDIA_hold.area'
report = timing.read_text()
if 'Confidence          : Routed' not in report:
    raise SystemExit('最终时序报告不是 Routed。')
metrics = {}
for label in ('SWNS', 'STNS', 'HWNS', 'HTNS'):
    match = re.search(r'\b' + label + r':\s*(-?\d+(?:\.\d+)?)ns', report)
    if match is None or float(match.group(1)) < 0:
        raise SystemExit(f'{label} 未通过；不发布候选 bit。')
    metrics[label + '_ns'] = float(match.group(1))
if not bit.is_file() or not area.is_file() or bit.stat().st_mtime < timing.stat().st_mtime:
    raise SystemExit('缺少本次编译的 bit 或面积报告。')
resources = {}
for key in ('lut', 'reg', 'bram', 'pll'):
    match = re.search(r'^#' + key + r'\s+(\d+)\s+out of\s+(\d+)', area.read_text(), re.M)
    if match is None:
        raise SystemExit(f'缺少资源项 {key}')
    resources[key] = {'used': int(match.group(1)), 'capacity': int(match.group(2))}
out = root / 'release/TF_MEDIA_BROWSER.bit'
shutil.copyfile(bit, out)
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
inputs = [root / p for p in (
    'prj/TF_MEDIA.al', 'prj/build_tf_media.sh', 'prj/build_tf_media.tcl',
    'prj/fix_tf_media_hold.tcl', 'constraints/tf_media.sdc',
    'constraints/tf_media.adc', 'rtl/tf_media_top.v', 'rtl/fat32_media_catalog.v',
    'rtl/vendor/tf_reference/SD/sd_card_sec_read_write.v',
    'rtl/touch_file_browser.v', 'rtl/file_browser_overlay.v',
    'rtl/audio_spectrum.v', 'rtl/audio_spectrum_overlay.v',
    'rtl/browser_ascii_font.v', 'rtl/image_status_osd.v', 'rtl/osd_font16.v',
    'rtl/tf_image_top.v', 'tools/generate_osd_font.py', 'rtl/fat32_bmp_loader.v',
    'rtl/fat32_video_reader.v', 'rtl/touch_player_frontend.v',
    'rtl/image_key_control.v', 'rtl/media_key_control.v',
    'sim/run_browser_tests.sh', 'sim/tb_audio_spectrum.v', 'sim/tb_media_catalog.v', 'sim/tb_browser_render.v',
    'sim/tb_file_browser.v', 'sim/tb_browser_open.v', 'sim/tb_osd.v')]
record = {
    'built_at_utc': datetime.now(timezone.utc).isoformat(),
    'tool': 'Tang Dynasty 6.2.1 build 175876',
    'device': 'EG4S20BG256',
    'test_status': 'browser, scrolling list, Chinese glyph UI and keyboard controls RTL simulated; audio files listed only; display touch unsupported',
    'file': out.name, 'sha256': digest(out), 'timing': metrics,
    'resources': resources,
    'inputs_sha256': {str(p.relative_to(root)): digest(p) for p in inputs},
}
(root / 'release/TF_MEDIA_BROWSER.json').write_text(
    json.dumps(record, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'bit': str(out), 'sha256': record['sha256'], 'timing': metrics,
                  'resources': resources}, ensure_ascii=False))
