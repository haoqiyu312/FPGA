#!/usr/bin/env python3
"""Assemble the validated coffee-signage firmware and SD-card demonstration."""
import hashlib
import json
from pathlib import Path
import shutil
import zipfile
from validate_coffee_ad import validate

root=Path(__file__).resolve().parents[1]
folder=root/'release/coffee_demo'
validate(folder)
firmware=root/'release/TF_MEDIA_COFFEE.bit'
record=root/'release/TF_MEDIA_COFFEE.json'
meta=json.loads(record.read_text())
digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert digest(firmware)==meta['sha256'],'firmware checksum mismatch'
assert all(digest(root/p)==h for p,h in meta['inputs_sha256'].items()),'firmware sources changed after build'
assert all(value>=0 for value in meta['timing'].values())
for source in (firmware,record):shutil.copyfile(source,folder/source.name)
shutil.copyfile(root/'media/coffee_ad/prompts.json',folder/'artwork_prompts.json')
manifest=json.loads((folder/'manifest.json').read_text())
manifest['source_artwork_sha256']={p.name:digest(p) for p in sorted((root/'media/coffee_ad/assets').glob('*.png'))}
manifest['generator_sha256']=digest(root/'tools/make_coffee_ad.py')
manifest['firmware_sha256']=meta['sha256']
manifest['firmware_timing']=meta['timing']
manifest['computer_preview_validation']='GStreamer discovered 18 s 640x480/24fps VP8 + 48kHz mono Vorbis; full audio/video decode completed'
(folder/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
(folder/'README_ZH.md').write_text('''# 咖啡数字广告牌演示包

本包采用 image_gen 生成的咖啡画面、自制音乐及慢速镜头运动，不是从素材网站下载的实拍视频。提示词见 artwork_prompts.json。营业时间是虚构演示信息。

## 先在电脑上看

打开 COFFEE_PREVIEW.webm（带音乐，18 秒）；也可用支持 AVI 的播放器打开 COFFEE_PREVIEW.avi。
COFFEE_RGB332.gif 是开发板视频实际 256 色 / 3fps 像素预览，无声。电脑预览不含 FPGA 的独立字幕和频谱。

## 烧录与复制

1. BitWriter 使用包内 TF_MEDIA_COFFEE.bit 做 SRAM 下载。尚未实际替你烧录。
2. 将 sdcard 目录里面的 COFFEE.RV、AD01.BMP、AD02.BMP、AD03.BMP 直接复制到 FAT32 卡根目录。不要只复制整个 sdcard 文件夹。
3. 卡需安全弹出，开发板断电插卡。菜单中 KEY2/KEY3 选择文件，KEY4 打开。

## 演示顺序

- 打开 AD01.BMP，KEY2/KEY3 切换三张海报，观察渐亮、横向擦除、棋盘分区转场；同时按 KEY2+KEY3 切换 100% / 50% / 200% 缩放。
- 长按 KEY4 约 1 秒回菜单，再打开 COFFEE.RV。通过 HDMI 显示器音频输出听音乐，观察右上角频谱；短按 KEY2 开关频谱。
- 底部三个促销字幕每约 3 秒切换，短按 KEY3 开关字幕，展示它与底图独立叠加。
- 短按 KEY4 暂停 / 继续画面、声音和字幕时间，长按 KEY4 返回菜单。

## 验证

媒体格式与音轨检查通过；WebM 音视频完整解码通过。固件完整综合、布局布线及最终时序通过，报告见 TF_MEDIA_COFFEE.json。
当前环境缺少 Icarus，RTL 仿真未执行；尚未实板验证。校验值见 checksums.json，不能把电脑预览或时序通过当作实板验收。

全部文件只保存在本地，未提交或上传 GitHub。
''')
files=sorted(p for p in folder.rglob('*') if p.is_file() and p.name!='checksums.json')
checksums={str(p.relative_to(folder)):digest(p) for p in files}
(folder/'checksums.json').write_text(json.dumps(checksums,ensure_ascii=False,indent=2)+'\n')
archive=root/'release/COFFEE_DEMO.zip'
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for p in sorted(folder.rglob('*')):
        if p.is_file():z.write(p,'COFFEE_DEMO/'+str(p.relative_to(folder)))
with zipfile.ZipFile(archive) as z:assert z.testzip() is None
assert all(digest(folder/p)==h for p,h in checksums.items())
print(json.dumps({'archive':str(archive),'bytes':archive.stat().st_size,'sha256':digest(archive),
                  'sdcard_files':[p.name for p in sorted((folder/'sdcard').iterdir())]},ensure_ascii=False))
