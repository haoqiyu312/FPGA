#!/usr/bin/env python3
"""Build an original coffee-signage demo from generated artwork, without ffmpeg.
Pillow is required. VIDEO.RV is RGB332/RVF2; AVI is MJPEG+PCM for PC preview.
Camera movement is procedural animation of a generated still, not live footage.
"""
import argparse
import array
import hashlib
import io
import json
import math
from pathlib import Path
import random
import shutil
import subprocess
import struct
import sys
import wave
from PIL import Image, ImageDraw, ImageFont
from convert_video import WIDTH, HEIGHT, header, audio_layout, pcm16_to_ulaw

RATE, FPS, PREVIEW_FPS, SECONDS = 48000, 3, 24, 18
RESAMPLE = getattr(Image, 'Resampling', Image).LANCZOS
FONT = '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'


def music():
    """An original 30-beat cafe jingle; no imported music or recording."""
    notes = [72,76,79,81,79,76,74,72,76,79,83,81,79,76,74,
             72,74,76,79,76,74,72,67,72,76,79,81,79,76,72]
    rng = random.Random(261026)
    samples = array.array('h')
    for n in range(RATE * SECONDS):
        t = n / RATE
        beat = min(29, int(t / .6))
        u = t - beat * .6
        freq = 440 * 2 ** ((notes[beat] - 69) / 12)
        env = min(1, u / .012) * math.exp(-4 * u)
        tone = sum(a * math.sin(2*math.pi*freq*k*t) for k,a in
                   ((1,.30),(2,.13),(3,.07),(4,.035),(6,.025),(8,.015))) * env
        bass = .13 * math.sin(2*math.pi*(130.8128 if beat%8<4 else 174.614)*t) * math.exp(-6*u)
        kick = .18 * math.sin(2*math.pi*(55*u + 22*(1-math.exp(-35*u))/35)) * math.exp(-24*u)
        hat_phase = (t % .3)
        hat = .055 * (rng.random()*2-1) * math.exp(-100*hat_phase)
        # Sparkling high-frequency accents exercise the analyzer's upper bins.
        sparkle = sum(.015*math.sin(2*math.pi*f*t) for f in (3000,4500,6000,9000,12000))
        sparkle *= math.exp(-35*u) * (1 if beat%4==0 else .25)
        fade = min(1, t/.08, (SECONDS-t)/.22)
        value = round(30000 * fade * (tone+bass+kick+hat+sparkle))
        if abs(value) > 32767:
            raise ValueError('music clipping')
        samples.append(value)
    if sys.byteorder != 'little':
        samples.byteswap()
    return samples.tobytes()


def fitted(image, zoom=1.0, pan=0.0):
    # This is video camera framing, not regeneration or alteration of the artwork.
    w,h = image.size
    crop_w = min(w, h*WIDTH/HEIGHT) / zoom
    crop_h = crop_w*HEIGHT/WIDTH
    cx=w/2 + pan*(w-crop_w)/2
    cy=h/2
    return image.crop((cx-crop_w/2,cy-crop_h/2,cx+crop_w/2,cy+crop_h/2)).resize((WIDTH,HEIGHT),RESAMPLE)


def camera_frame(hero, frame):
    t=frame/PREVIEW_FPS
    # Smooth periodic camera move gives a clean loop; source artwork stays fixed.
    zoom=1.035 + .035*math.sin(2*math.pi*t/SECONDS-math.pi/2)
    picture=fitted(hero, zoom, .5*math.sin(2*math.pi*t/SECONDS)).convert('RGB')
    draw=ImageDraw.Draw(picture)
    title=ImageFont.truetype(FONT,36,index=2)
    small=ImageFont.truetype(FONT,15,index=2)
    draw.text((32,49),'现磨咖啡',font=title,fill='#fff0cf',stroke_width=1,stroke_fill='#51351d')
    draw.text((35,98),'FRESHLY BREWED · COFFEE MOMENTS',font=small,fill='#dfb980')
    # All promotional captions at y=376..400 are rendered by FPGA, not this movie.
    return picture


# Ordered quantization uses the same RGB332 wire format, while distributing
# quantization error spatially to preserve photographic gradients.
BAYER=(0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5)
QUANT7=[bytes(min(7,(c*7*16+b*255)//4080) for c in range(256)) for b in BAYER]
QUANT3=[bytes(min(3,(c*3*16+b*255)//4080) for c in range(256)) for b in BAYER]

def pack_dithered_rgb332(rgb):
    packed=bytearray(WIDTH*HEIGHT)
    for y in range(HEIGHT):
        phase=(y&3)*4
        for x in range(WIDTH):
            i=y*WIDTH+x;j=i*3;q=phase+(x&3)
            packed[i]=(QUANT7[q][rgb[j]]<<5)|(QUANT7[q][rgb[j+1]]<<2)|QUANT3[q][rgb[j+2]]
    return bytes(packed)


def rgb332_preview(packed):
    raw=bytearray(len(packed)*3)
    for i,c in enumerate(packed):
        r,g,b=c>>5,(c>>2)&7,c&3
        raw[3*i:3*i+3]=bytes(((r<<5)|(r<<2)|(r>>1),(g<<5)|(g<<2)|(g>>1),(b<<6)|(b<<4)|(b<<2)|b))
    return Image.frombytes('RGB',(WIDTH,HEIGHT),bytes(raw))


def chunk(tag,data):
    return tag+struct.pack('<I',len(data))+data+(b'\0' if len(data)%2 else b'')


def avi_header():
    total=SECONDS*PREVIEW_FPS
    avih=struct.pack('<14I',round(1000000/PREVIEW_FPS),0,0,0x10,total,0,2,1000000,WIDTH,HEIGHT,0,0,0,0)
    vstrh=struct.pack('<4s4sIHH8I4h',b'vids',b'MJPG',0,0,0,0,1,PREVIEW_FPS,0,total,1000000,0xffffffff,0,0,0,WIDTH,HEIGHT)
    vstrf=struct.pack('<IiiHH4sIiiII',40,WIDTH,HEIGHT,1,24,b'MJPG',WIDTH*HEIGHT*3,0,0,0,0)
    astrh=struct.pack('<4s4sIHH8I4h',b'auds',bytes(4),0,0,0,0,2,RATE*2,0,SECONDS*RATE,RATE*2,0xffffffff,2,0,0,0,0)
    astrf=struct.pack('<HHIIHH',1,1,RATE,RATE*2,2,16)
    return chunk(b'LIST',b'hdrl'+chunk(b'avih',avih)+chunk(b'LIST',b'strl'+chunk(b'strh',vstrh)+chunk(b'strf',vstrf))+chunk(b'LIST',b'strl'+chunk(b'strh',astrh)+chunk(b'strf',astrf)))


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--assets',type=Path,default=Path(__file__).resolve().parents[1]/'media/coffee_ad/assets')
    ap.add_argument('--output',type=Path,default=Path(__file__).resolve().parents[1]/'release/coffee_ad')
    args=ap.parse_args()
    assets=args.assets;out=args.output;sd=out/'sdcard'
    sd.mkdir(parents=True,exist_ok=True)
    targets=[out/'COFFEE_PREVIEW.avi',out/'COFFEE_MUSIC.wav',sd/'COFFEE.RV',out/'manifest.json']
    targets += [sd/f'AD0{i}.BMP' for i in range(1,4)]
    targets += [out/'COFFEE_RGB332.gif']+[out/f'RV_FRAME_{i:02}.png' for i in (0,18,36)]
    if (out/'COFFEE_PREVIEW.webm').exists():ap.error('preview output already exists')
    if any(p.exists() for p in targets):
        ap.error('output exists; choose another directory to preserve prior deliverables')
    hero=Image.open(assets/'coffee_hero.png').convert('RGB')
    for i in range(1,4):
        poster=Image.open(assets/f'poster0{i}.png').convert('RGB')
        fitted(poster).save(sd/f'AD0{i}.BMP',format='BMP')
    pcm=music()
    with wave.open(str(out/'COFFEE_MUSIC.wav'),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(RATE);f.writeframes(pcm)
    samples,audio_bytes=audio_layout(FPS)
    previews=[];index=[]
    with (sd/'COFFEE.RV').open('wb') as rv,(out/'COFFEE_PREVIEW.avi').open('w+b') as avi:
        rv.write(header(SECONDS*FPS,FPS,True))
        avi.write(b'RIFF'+bytes(4)+b'AVI '+avi_header())
        movi_start=avi.tell();avi.write(b'LIST'+bytes(4)+b'movi');movi_base=movi_start+8
        for frame in range(SECONDS*PREVIEW_FPS):
            image=camera_frame(hero,frame)
            jpeg=io.BytesIO();image.save(jpeg,'JPEG',quality=85)
            payload=jpeg.getvalue();offset=avi.tell()-movi_base
            avi.write(chunk(b'00dc',payload));index.append(struct.pack('<4sIII',b'00dc',0x10,offset,len(payload)))
            start=frame*(RATE//PREVIEW_FPS)*2
            block=pcm[start:start+(RATE//PREVIEW_FPS)*2];offset=avi.tell()-movi_base
            avi.write(chunk(b'01wb',block));index.append(struct.pack('<4sIII',b'01wb',0,offset,len(block)))
            if frame%(PREVIEW_FPS//FPS)==0:
                f=frame//(PREVIEW_FPS//FPS)
                packed=pack_dithered_rgb332(image.tobytes());rv.write(packed)
                audio=pcm[f*samples*2:(f+1)*samples*2]
                rv.write(pcm16_to_ulaw(audio).ljust(audio_bytes,b'\xff'))
                reduced=rgb332_preview(packed)
                previews.append(reduced)
                if f in (0,18,36):reduced.save(out/f'RV_FRAME_{f:02}.png')
            if frame%PREVIEW_FPS==0:print(f'Building {frame//PREVIEW_FPS+1}/{SECONDS} s',flush=True)
        end_movi=avi.tell();avi.write(chunk(b'idx1',b''.join(index)));end=avi.tell()
        avi.seek(movi_start+4);avi.write(struct.pack('<I',end_movi-movi_start-8))
        avi.seek(4);avi.write(struct.pack('<I',end-8))
    previews[0].save(out/'COFFEE_RGB332.gif',save_all=True,append_images=previews[1:],duration=round(1000/FPS),loop=0)
    if shutil.which('gst-launch-1.0'):
        required=('vp8enc','vorbisenc','webmmux','jpegdec','avidemux')
        if all(subprocess.run(['gst-inspect-1.0',p],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0 for p in required):
            webm=out/'COFFEE_PREVIEW.webm'
            subprocess.run(['gst-launch-1.0','-e','-q','filesrc','location='+str(out/'COFFEE_PREVIEW.avi'),'!',
                'avidemux','name=d','webmmux','name=m','!','filesink','location='+str(webm),
                'd.video_0','!','queue','!','jpegdec','!','videoconvert','!',
                'vp8enc','deadline=1','target-bitrate=1200000','!','queue','!','m.video_0',
                'd.audio_0','!','queue','!','audioconvert','!','audioresample','!','vorbisenc','!','queue','!','m.audio_0'],check=True)
            targets.append(webm)
    digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    manifest={'title':'Coffee digital signage demo','duration_seconds':SECONDS,'fps':FPS,'frames':SECONDS*FPS,
              'quantization':'RGB332 with 4x4 ordered dithering',
              'resolution':[WIDTH,HEIGHT],'format':'RVF2 RGB332, 48 kHz mono mu-law',
              'artwork_origin':'Generated with built-in image_gen; not downloaded live-action footage',
              'video_origin':'Procedural slow camera movement on generated still artwork',
              'music_origin':'Original synthesized cafe jingle; no third-party recording',
              'subtitle_origin':'Independent FPGA layer; not baked into video',
              'captions':['今日推荐：现磨咖啡','香醇现萃，每一口都是好时光','新品上市，欢迎到店品尝'],
              'firmware':'TF_MEDIA_COFFEE.bit','hardware_tested':False,
              'source_artwork_sha256':{p.name:digest(p) for p in sorted(assets.glob('*.png'))},
              'generator_sha256':digest(Path(__file__)),
              'files':{str(p.relative_to(out)):{'bytes':p.stat().st_size,'sha256':digest(p)} for p in targets if p.name!='manifest.json'}}
    (out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(manifest,ensure_ascii=False,indent=2))


if __name__=='__main__':main()
