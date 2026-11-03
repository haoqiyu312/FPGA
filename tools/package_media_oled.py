#!/usr/bin/env python3
"""Package only a fresh OLED/keypad implementation with passing routed timing."""
import hashlib
import json
from pathlib import Path
import re
import shutil
from datetime import datetime, timezone

root=Path(__file__).resolve().parents[1]
project=root/'prj/TF_MEDIA_OLED.al'
run=root/'prj/TF_MEDIA_OLED_Runs/phy_1'
bit=run/'TF_MEDIA_OLED_hold.bit'
timing=run/'TF_MEDIA_OLED_hold.timing'
area=run/'TF_MEDIA_OLED_hold.area'
inputs=[project]+[root/'prj'/name for name in ('build_tf_media_oled.sh','build_tf_media_oled.tcl','fix_tf_media_oled_hold.tcl')]
subtitle_sample=root/'media/COFFEE.SRT'
for name in re.findall(r'<File Path="([^"]+)"',project.read_text()):
    path=(root/'prj'/name).resolve()
    if path not in inputs:inputs.append(path)
for path in inputs+[bit,timing,area]:
    if not path.is_file():raise SystemExit(f'缺少文件：{path}')
if bit.stat().st_mtime<max(p.stat().st_mtime for p in inputs+[timing,area]):
    raise SystemExit('bit 早于源码、工程、约束或报告，不能打包。')
report=timing.read_text()
if not re.search(r'Confidence\s*:\s*Routed',report):raise SystemExit('需要完整 Routed 时序。')
metrics={}
for key in ('SWNS','STNS','HWNS','HTNS'):
    m=re.search(rf'\b{key}:\s*(-?\d+(?:\.\d+)?)ns',report)
    if not m or float(m[1])<0:raise SystemExit(f'{key} 缺失或有违例，不打包。')
    metrics[key+'_ns']=float(m[1])
resources={}
for key in ('lut','reg','bram','pll','dsp'):
    m=re.search(rf'^#{key}\s+(\d+)\s+out of\s+(\d+)',area.read_text(),re.M)
    if not m or int(m[1])>int(m[2]):raise SystemExit(f'{key} 缺失或超限。')
    resources[key]={'used':int(m[1]),'capacity':int(m[2])}
digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
out=root/'release/TF_MEDIA_OLED.bit'
record={
 'packaged_at_utc':datetime.now(timezone.utc).isoformat(),
 'file':out.name,'sha256':digest(bit),'tool':'Tang Dynasty 6.2.1 build 175876','device':'EG4S20BG256',
 'display':{'hdmi':'720x720 at 48 MHz','oled':'SSD1306 128x64 I2C, 0x3C/0x3D automatic fallback','oled_framebuffer_in_fpga':False},
 'input':'4x4 open-drain matrix, debounced single-key events; D software reset/rescan; KEY1 emergency reset retained',
 'features':['OLED Chinese file menu and playback settings','HDMI output is black while the OLED file menu is open','HDMI image/video/audio','same-name bounded SRT','audio spectrum','slideshow with 1-20 second interval and image scaling'],
 'subtitle_sample':{'asset':'media/COFFEE.SRT','sd_root_filename':'COFFEE.SRT','paired_video':'COFFEE.RV','sha256':digest(subtitle_sample)},
 'limits':['FAT32 root only; FAT 8.3 names','audio files listed but no standalone decoding','SRT 16 cues, 32 glyphs/cue, built-in font subset'],
 'timing':metrics,'resources':resources,
 'validation':{'build':'passed','routed_timing':'passed','rtl':'not rerun for this revision','hardware':'not yet tested'},
 'inputs_sha256':{str(p.relative_to(root)):digest(p) for p in sorted(inputs)},
 'fallback':'TF_MEDIA_720_R2.bit',
}
shutil.copyfile(bit,out)
out.with_suffix('.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:record[k] for k in ('file','sha256','timing','resources')},ensure_ascii=False))
