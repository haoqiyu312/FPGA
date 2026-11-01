#!/usr/bin/env python3
"""Generate the same-content 640x480 control for the previous R2 firmware."""
import array
import json
from pathlib import Path
import sys
import wave
from PIL import Image
from convert_video import header,pack_rgb332,pcm16_to_ulaw
from make_resolution_showcase import ROOT,RESAMPLE,frame_image

folder=ROOT/'release/resolution_showcase720'
control=folder/'旧版R2对照'/'sdcard'
control.mkdir(parents=True,exist_ok=False)
with Image.open(folder/'sdcard/AD720.BMP') as im:
    im.resize((640,480),RESAMPLE).save(control/'AD640.BMP')
with Image.open(ROOT/'media/coffee_ad/assets/coffee_hero.png') as f:hero=f.convert('RGB')
with wave.open(str(folder/'配乐试听.wav')) as w:source=array.array('h',w.readframes(w.getnframes()))
if sys.byteorder!='little':source.byteswap()
with (control/'AV640.RV').open('wb') as out:
    out.write(header(54,3,True))
    for second in range(18):
        packed=pack_rgb332(frame_image(hero,second).resize((640,480),RESAMPLE).tobytes())
        upsampled=array.array('h')
        for value in source[second*12000:(second+1)*12000]:upsampled.extend([value]*4)
        if sys.byteorder!='little':upsampled.byteswap()
        audio=pcm16_to_ulaw(upsampled.tobytes())
        for subframe in range(3):
            out.write(packed);out.write(audio[subframe*16000:(subframe+1)*16000].ljust(16384,b'\xff'))
record={'firmware':'TF_MEDIA_SW4_R2.bit','width':640,'height':480,'fps':3,'frames':54,'duration_seconds':18,
        'audio_hz':48000,'content':'same poster and same per-second scene progression as native demo',
        'timing':'each one-second scene is repeated for three old-format frames; audio has equal nominal duration',
        'purpose':'physical before/after comparison, not a screen capture of the old board',
        'notes':'quantization differs: new photo region uses dithering; comparisons of spatial detail should focus on text/line scene'}
(folder/'旧版R2对照'/'格式说明.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
print('Generated same-content old R2 image and video control')
