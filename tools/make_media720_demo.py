#!/usr/bin/env python3
"""Build native square coffee media from repository artwork and the original jingle.
Requires Pillow; no ffmpeg. Camera movement animates a still image.
"""
import argparse
import array
import io
import json
import math
from pathlib import Path
import struct
import sys
import wave
from PIL import Image, ImageOps
from convert_image720 import convert
from convert_video import write_stream, pack_rgb332

ROOT=Path(__file__).resolve().parents[1]


def build(output, music_path):
    output=Path(output)
    output.mkdir(parents=True, exist_ok=False)
    card=output/'sdcard'
    card.mkdir()
    for index in range(1,4):
        convert(ROOT/f'media/coffee_ad/assets/poster{index:02}.png',card/f'AD{index:02}.BMP','contain')
    # Use the higher-resolution original, not the old 640x480 video frames.
    with Image.open(ROOT/'media/coffee_ad/assets/coffee_hero.png') as source:
        hero=ImageOps.exif_transpose(source).convert('RGB')
    with wave.open(str(music_path)) as music:
        if (music.getnchannels(),music.getsampwidth(),music.getframerate()) != (1,2,48000):
            raise ValueError('expected original 48 kHz mono PCM16 jingle')
        pcm=array.array('h',music.readframes(music.getnframes()))
    if sys.byteorder!='little':pcm.byteswap()
    # Box-filter before 4:1 decimation. No third-party audio packages required.
    low=array.array('h',(sum(pcm[i:i+4])//4 for i in range(0,len(pcm)-3,4)))
    seconds=min(18,len(low)//12000)
    if seconds<1:raise ValueError('music is shorter than one second')
    resample=getattr(Image,'Resampling',Image).LANCZOS
    with (output/'native.rgb').open('wb') as raw:
        for index in range(seconds):
            side=hero.height*(.94-.06*math.sin(math.pi*index/max(1,seconds-1)))
            cx=hero.width/2+40*math.sin(index/5)
            cy=hero.height/2
            frame=hero.crop((round(cx-side/2),round(cy-side/2),round(cx+side/2),round(cy+side/2))).resize((720,720),resample)
            raw.write(frame.tobytes())
            if index==0:
                packed=pack_rgb332(frame.tobytes(),720,720)
                preview=bytearray()
                for value in packed:
                    r,g,b=value>>5,(value>>2)&7,value&3
                    preview.extend(((r<<5)|(r<<2)|(r>>1),(g<<5)|(g<<2)|(g>>1),b*85))
                Image.frombytes('RGB',(720,720),bytes(preview)).save(output/'VIDEO_PREVIEW.png')
    if sys.byteorder!='little':low.byteswap()
    with (output/'native.rgb').open('rb') as raw:
        write_stream(raw,card/'COFFEE.RV',1,io.BytesIO(low.tobytes()),720,720,12000)
    (output/'native.rgb').unlink()
    record={'width':720,'height':720,'fps':1,'seconds':seconds,'video_color':'RGB332',
            'audio_hz':12000,'video_frame_bytes':518656,'audio_block_bytes':12288,
            'video_origin':'procedural camera movement over repository coffee_hero.png',
            'image_fit':'contain: preserve all poster lettering and original aspect ratio'}
    (output/'media.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
    print(f'Built {seconds} native square frames and three RGB24 posters in {card}')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'release/media720')
    parser.add_argument('--music',type=Path,default=ROOT/'release/coffee_demo/COFFEE_MUSIC.wav')
    args=parser.parse_args()
    build(args.output,args.music)
