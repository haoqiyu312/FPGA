#!/usr/bin/env python3
"""Publish the local R2 candidate only when its final routed timing passes."""
import hashlib
import json
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path

root = Path(__file__).resolve().parents[1]
project = root / 'prj'
bit = project / 'SW4_R2_candidate.bit'
timing = project / 'SW4_R2_final.timing'
area = project / 'SW4_R2_final.area'
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
report = timing.read_text()
if not re.search(r'Confidence\s*:\s*Routed', report):
    raise SystemExit('需要完整布线后的 Routed 时序报告。')
metrics = {}
for label in ('SWNS', 'STNS', 'HWNS', 'HTNS'):
    match = re.search(r'\b' + label + r':\s*(-?\d+(?:\.\d+)?)ns', report)
    if match is None or float(match[1]) < 0:
        raise SystemExit(f'{label} 缺失或存在违例，不发布 R2 固件。')
    metrics[label + '_ns'] = float(match[1])
inputs = sorted(list((root / 'rtl').rglob('*.v'))
                + list((root / 'constraints').glob('tf_media.*'))
                + [project / 'implement_sw4_r2.tcl', project / 'resume_sw4_r2.tcl',
                   project / 'TF_MEDIA.al'])
gate = project / 'TF_MEDIA_Runs/syn_1/TF_MEDIA_gate.db'
if gate.stat().st_mtime < max(p.stat().st_mtime for p in inputs if p.suffix == '.v'):
    raise SystemExit('综合结果早于 RTL，需重新综合。')
if bit.stat().st_mtime < max(p.stat().st_mtime for p in inputs + [gate, timing, area]):
    raise SystemExit('候选 bit 早于源码或报告，需重新构建。')
resources = {}
for key in ('lut', 'reg', 'bram', 'pll'):
    match = re.search(r'^#' + key + r'\s+(\d+)\s+out of\s+(\d+)', area.read_text(), re.M)
    if match is None or int(match[1]) > int(match[2]):
        raise SystemExit(f'资源项 {key} 缺失或超限。')
    resources[key] = {'used': int(match[1]), 'capacity': int(match[2])}
stem = root / 'release/TF_MEDIA_SW4_R2'
record = {
    'built_at_utc': datetime.now(timezone.utc).isoformat(),
    'file': stem.with_suffix('.bit').name, 'sha256': digest(bit),
    'tool': 'Tang Dynasty 6.2.1 SP1 build 178840',
    'device': 'EG4S20BG256', 'timing': metrics, 'resources': resources,
    'sw4': 'up hides playback OSD; down shows it; browser stays visible',
    'validation': {'build': 'passed', 'routed_timing': 'passed',
                   'rtl_simulation': 'not run: Icarus unavailable',
                   'hardware': 'not tested; previous SW4 release regressed on board'},
    'inputs_sha256': {str(p.relative_to(root)): digest(p) for p in inputs},
    'synthesis_db_sha256': digest(gate),
    'reports_sha256': {p.name: digest(p) for p in (timing, area)},
}
for source, suffix in ((bit, '.bit'), (timing, '.timing'), (area, '.area')):
    shutil.copyfile(source, stem.with_suffix(suffix))
stem.with_suffix('.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({k: record[k] for k in ('file', 'sha256', 'timing', 'resources')}, ensure_ascii=False))
