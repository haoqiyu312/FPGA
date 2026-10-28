#!/usr/bin/env python3
"""Package the local extensions build only after routed timing passes."""
import argparse
import hashlib
import json
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output-stem', default='TF_MEDIA_FEATURES', choices=['TF_MEDIA_FEATURES', 'TF_MEDIA_COFFEE'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
run = root / 'prj/TF_MEDIA_Runs/phy_1'
bit = run / 'TF_MEDIA_hold.bit'
timing = run / 'TF_MEDIA_hold.timing'
area = run / 'TF_MEDIA_hold.area'
report = timing.read_text()
if not re.search(r'Confidence\s*:\s*Routed', report):
    raise SystemExit('需要本次完整布线的 Routed 时序报告。')
metrics = {}
for label in ('SWNS', 'STNS', 'HWNS', 'HTNS'):
    match = re.search(r'\b' + label + r':\s*(-?\d+(?:\.\d+)?)ns', report)
    if match is None or float(match[1]) < 0:
        raise SystemExit(f'{label} 缺失或存在违例，不发布 bit。')
    metrics[label + '_ns'] = float(match[1])
resources = {}
for key in ('lut', 'reg', 'bram', 'pll'):
    match = re.search(r'^#' + key + r'\s+(\d+)\s+out of\s+(\d+)', area.read_text(), re.M)
    if match is None or int(match[1]) > int(match[2]):
        raise SystemExit(f'资源项 {key} 缺失或超限。')
    resources[key] = {'used': int(match[1]), 'capacity': int(match[2])}
inputs = [root / 'prj/TF_MEDIA.al']
inputs += list((root / 'rtl').rglob('*.v'))
inputs += list((root / 'constraints').glob('tf_media.*'))
inputs += list((root / 'prj/al_ip/video_pll').glob('*'))
inputs += [root / 'prj' / name for name in ('build_tf_media.sh', 'build_tf_media.tcl', 'fix_tf_media_hold.tcl')]
inputs = sorted(p for p in inputs if p.is_file())
if not bit.is_file() or bit.stat().st_mtime < max(p.stat().st_mtime for p in inputs + [timing, area]):
    raise SystemExit('bit 早于源码或最终报告，需重新编译。')
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
out = root / 'release' / (args.output_stem + '.bit')
record = {
    'built_at_utc': datetime.now(timezone.utc).isoformat(),
    'device': 'EG4S20BG256',
    'tool': 'Tang Dynasty 6.2.1 SP1 build 178840',
    'file': out.name, 'sha256': digest(bit), 'timing': metrics,
    'profile': 'coffee commercial signage' if args.output_stem == 'TF_MEDIA_COFFEE' else 'extensions',
    'resources': resources,
    'features': ['built-in Chinese subtitle layer', 'three image reveals',
                 '50/100/200 percent image scaling', 'RVF2 eight-band audio spectrum'],
    'validation': {'build': 'passed', 'routed_timing': 'passed',
                   'rtl_simulation': 'not run: Icarus unavailable', 'hardware': 'not tested'},
    'inputs_sha256': {str(p.relative_to(root)): digest(p) for p in inputs},
}
shutil.copyfile(bit, out)
out.with_suffix('.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({k: record[k] for k in ('file', 'sha256', 'timing', 'resources')}, ensure_ascii=False))
