#!/usr/bin/env python3
"""Build one native square signage poster and one RVF2 video with frame-aligned audio.
Pillow is required. Existing generated artwork is cropped from 1448x1086 originals;
all typography, layout, micro-patterns and music are rendered procedurally.
"""
import argparse
import array
import hashlib
import io
import json
import math
from pathlib import Path
import struct
import subprocess
import sys
import wave
from zipfile import ZipFile, ZIP_DEFLATED
from PIL import Image, ImageDraw, ImageFont, ImageOps
from convert_video import header, pcm16_to_ulaw

ROOT=Path(__file__).resolve().parents[1]
SIZE=720
RATE=12000
SECONDS=18
PIXELS=SIZE*SIZE
STORAGE=518656
AUDIO_BYTES=12288
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
BOLD='/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc'
RESAMPLE=getattr(Image,'Resampling',Image).LANCZOS
CREAM='#fff3d8'
GOLD='#ffda80'
GREEN='#3c6b59'
INK='#11231d'


def font(size,bold=False):return ImageFont.truetype(BOLD if bold else FONT,size,index=2)
def text(draw,xy,value,size=20,fill=CREAM,bold=False):draw.text(xy,value,font=font(size,bold),fill=fill)
def crop(hero,box,size):return ImageOps.fit(hero.crop(box),size,method=RESAMPLE)
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()


def detail_tile():
    """Native typography and high-frequency structure for a repeatable comparison."""
    tile=Image.new('RGB',(304,184),'#faf5e9');d=ImageDraw.Draw(tile)
    text(d,(12,8),'现磨 · 手冲 · 每日新鲜',17,INK,True)
    text(d,(12,37),'产地甄选 / 中度烘焙 / 风味笔记',12,INK)
    text(d,(12,59),'FLAVOR  Citrus · Cocoa · Caramel',11,INK)
    for x in range(12,292):
        if (x-12)%4<2:d.line((x,94,x,123),fill=INK,width=1)
    for y in range(139,171,2):d.line((12,y,291,y),fill=INK,width=1)
    return tile


def poster(hero):
    im=Image.new('RGB',(SIZE,SIZE),INK);d=ImageDraw.Draw(im)
    text(d,(30,19),'MORNING   /   COFFEE LAB',16,GOLD,True)
    text(d,(30,46),'把美好，磨进每一天',43,CREAM,True)
    text(d,(32,110),'现磨咖啡  ·  手作烘焙  ·  门店信息发布',17,'#c8d9cc')
    im.paste(crop(hero,(0,95,1448,975),(660,370)),(30,153))
    d=ImageDraw.Draw(im);d.rectangle((30,470,690,523),fill=INK)
    text(d,(44,480),'今日推荐',17,GOLD,True)
    text(d,(155,478),'香醇拿铁  ¥22   /   手冲咖啡  ¥26',22,CREAM,True)
    text(d,(32,542),'风味笔记',18,GOLD,True)
    text(d,(32,574),'柑橘清香  /  可可回甘  /  焦糖余韵',15,CREAM)
    text(d,(32,601),'精选咖啡豆 · 现点现磨 · 支持自带杯',13,'#c8d9cc')
    text(d,(32,627),'营业时间  08:00—20:00    欢迎到店品尝',13,'#c8d9cc')
    # A precise grind-scale graphic is naturally related to the product;
    # its one-pixel ticks and fine horizontal detail visibly soften at 640x480.
    text(d,(454,542),'GRIND / 研磨刻度',12,GOLD,True)
    for x in range(455,684,3):
        top=574 if (x-455)%15==0 else 581
        d.line((x,top,x,600),fill=CREAM,width=1)
    text(d,(454,607),'细研磨                 粗研磨',11,'#c8d9cc')
    d.line((30,663,690,663),fill=GREEN,width=1)
    text(d,(32,677),'MORNING COFFEE    /    DIGITAL SIGNAGE',12,GOLD)
    text(d,(592,677),'示例门店',12,'#c8d9cc')
    return im


SCENES=[('今日推荐','现磨咖啡，开启美好一天'),('细看品质','从咖啡豆纹理到杯沿光泽'),
        ('风味时刻','柑橘 · 可可 · 焦糖'),('细节对照','同一内容，观察细字与线纹'),
        ('门店资讯','菜单、价格与营业时间'),('欢迎到店','香醇现萃，慢享这一刻')]


def frame_image(hero,n):
    scene=n//3;step=n%3
    im=Image.new('RGB',(720,720),INK);d=ImageDraw.Draw(im)
    text(d,(30,18),'MORNING / COFFEE LAB',16,GOLD,True)
    text(d,(30,52),SCENES[scene][0],42,CREAM,True)
    text(d,(32,111),SCENES[scene][1],18,'#c8d9cc')
    if scene in (0,1,2,5):
        if scene==1:
            boxes=[(0,280,850,1080),(260,160,1110,1010),(510,180,1360,1030)]
            photo=crop(hero,boxes[step],(660,425))
        else:
            side=1030-step*30
            cx=724+step*12;cy=550
            photo=crop(hero,(cx-side/2,cy-side/2,cx+side/2,cy+side/2),(660,425))
        im.paste(photo,(30,153));d=ImageDraw.Draw(im)
        d.rectangle((30,510,690,578),fill=INK)
        if scene==2:
            for i,label in enumerate(('柑橘清香','可可回甘','焦糖余韵')):
                x=45+i*214;fill=GOLD if i==step else '#738d79'
                text(d,(x,526),label,22,fill,True)
        else:
            caption=('好咖啡，源于每一颗好豆' if scene==1 else '现磨拿铁 ¥22   ·   手冲咖啡 ¥26' if scene==0 else '08:00—20:00    欢迎到店品尝')
            text(d,(46,529),caption,22,CREAM,True)
    elif scene==3:
        tile=detail_tile()
        degraded=tile.resize((270,123),RESAMPLE).resize(tile.size,RESAMPLE)
        text(d,(34,176),'原生 720 细节',20,GOLD,True)
        text(d,(380,176),'模拟旧版缩放',20,'#c8d9cc',True)
        im.paste(tile,(32,224));im.paste(degraded,(384,224));d=ImageDraw.Draw(im)
        d.line((360,176,360,560),fill=GREEN,width=1)
        text(d,(33,447),'看细字笔画、竖线间隔与水平细纹',23,CREAM,True)
        text(d,(33,489),'右侧为数字缩放模拟，并非旧固件实板截图',13,'#c8d9cc')
        text(d,(33,523),'高清信息发布，让重要细节清楚可见',19,GOLD)
    else:
        rows=[('香醇拿铁','丝滑奶香 / 双份浓缩','¥22'),('手冲咖啡','中度烘焙 / 柑橘与可可','¥26'),('咖啡可颂组合','现磨咖啡 / 手作烘焙','¥32')]
        for i,(name,description,price) in enumerate(rows):
            y=167+i*124
            d.rounded_rectangle((30,y,690,y+105),radius=12,fill='#254537' if i==step else '#192f25')
            text(d,(48,y+12),name,27,CREAM,True);text(d,(48,y+59),description,14,'#c8d9cc')
            text(d,(585,y+23),price,30,GOLD,True)
        text(d,(33,560),'营业时间 08:00—20:00  /  支持自带杯',16,CREAM)
    # Keep y=616..639 clear for the firmware's coffee subtitle layer.
    d.rectangle((30,650,690,707),fill='#1c382c')
    for i in range(6):
        x=46+i*105;d.rounded_rectangle((x,666,x+78,674),radius=3,fill=GOLD if i==scene else '#446b55')
    text(d,(47,683),f'画面节拍 {n+1:02d} / {SECONDS}   ·   音乐随画面同步',11,CREAM)
    # The lit beat mark starts with the audio cue at this frame's first sample.
    d.ellipse((661,682,673,694),fill=GOLD)
    return im


BAYER=(0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5)
Q7=[bytes(min(7,(c*7*16+b*255)//4080) for c in range(256)) for b in BAYER]
Q3=[bytes(min(3,(c*3*16+b*255)//4080) for c in range(256)) for b in BAYER]

def pack_and_decode(im,photo=False):
    rgb=im.tobytes();packed=bytearray(PIXELS);out=bytearray(PIXELS*3)
    for i in range(PIXELS):
        r,g,b=rgb[3*i:3*i+3]
        x,y=i%720,i//720
        if photo and 30<=x<690 and 153<=y<510:
            q=(y&3)*4+(x&3);v=(Q7[q][r]<<5)|(Q7[q][g]<<2)|Q3[q][b]
        else:v=(r&224)|((g>>3)&28)|(b>>6)
        packed[i]=v
        r,g,b=v>>5,(v>>2)&7,v&3
        out[3*i:3*i+3]=bytes(((r<<5)|(r<<2)|(r>>1),(g<<5)|(g<<2)|(g>>1),b*85))
    return bytes(packed),Image.frombytes('RGB',(720,720),bytes(out))


def soundtrack():
    notes=[60,64,67,69,67,64,62,65,69,72,69,65,64,67,71,72,67,60]
    out=array.array('h')
    for n in range(SECONDS*RATE):
        t=n/RATE;sec=n//RATE;u=(n%RATE)/RATE;frequency=440*2**((notes[sec]-69)/12)
        envelope=(1-math.exp(-u*70))*math.exp(-u*2.8)
        note=(math.sin(2*math.pi*frequency*t)+.24*math.sin(4*math.pi*frequency*t))*envelope
        bass=.16*math.sin(2*math.pi*130.8128*t)*(1-math.exp(-u*30))*math.exp(-u*2)
        cue=.3*math.sin(2*math.pi*(1046.502 if sec%3==0 else 783.991)*u)*math.exp(-u*65)
        fade=min(1,(SECONDS-t)/.12)
        value=round((note*.3+bass+cue)*20000*fade)
        if abs(value)>32767:raise ValueError('audio clipping')
        out.append(value)
    if sys.byteorder!='little':out.byteswap()
    return out.tobytes()


def chunk(tag,data):return tag+struct.pack('<I',len(data))+data+(b'\0' if len(data)%2 else b'')
def avi_header():
    avih=struct.pack('<14I',1000000,0,0,0x10,SECONDS,0,2,1000000,720,720,0,0,0,0)
    vs=struct.pack('<4s4sIHH8I4h',b'vids',b'MJPG',0,0,0,0,1,1,0,SECONDS,1000000,0xffffffff,0,0,0,720,720)
    vf=struct.pack('<IiiHH4sIiiII',40,720,720,1,24,b'MJPG',PIXELS*3,0,0,0,0)
    aus=struct.pack('<4s4sIHH8I4h',b'auds',bytes(4),0,0,0,0,2,RATE*2,0,SECONDS*RATE,RATE*2,0xffffffff,2,0,0,0,0)
    auf=struct.pack('<HHIIHH',1,1,RATE,RATE*2,2,16)
    return chunk(b'LIST',b'hdrl'+chunk(b'avih',avih)+chunk(b'LIST',b'strl'+chunk(b'strh',vs)+chunk(b'strf',vf))+chunk(b'LIST',b'strl'+chunk(b'strh',aus)+chunk(b'strf',auf)))


def build(folder):
    folder.mkdir(parents=True,exist_ok=False);sd=folder/'sdcard';sd.mkdir()
    with Image.open(ROOT/'media/coffee_ad/assets/coffee_hero.png') as f:hero=f.convert('RGB')
    if hero.width<720 or hero.height<720:raise ValueError('source artwork too small')
    still=poster(hero);still.save(sd/'AD720.BMP');still.save(folder/'图片预览.png')
    still.resize((640,480),RESAMPLE).save(folder/'旧版对照_640x480.BMP')
    comparison=Image.new('RGB',(1440,760),'#11231d');comparison.paste(still,(0,40))
    comparison.paste(still.resize((640,480),RESAMPLE).resize((720,720),RESAMPLE),(720,40))
    d=ImageDraw.Draw(comparison);text(d,(20,5),'原生 720×720',20,GOLD,True)
    text(d,(740,5),'模拟 640×480 后再铺满方屏（非实板截图）',18,GOLD,True)
    comparison.save(folder/'图片细节对比.png')
    pcm=soundtrack()
    with wave.open(str(folder/'配乐试听.wav'),'wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(RATE);w.writeframes(pcm)
    decoded=array.array('h');frame_hashes=[];index=[];previews=[]
    with (sd/'AV720.RV').open('wb') as rv,(folder/'视频预览.avi').open('w+b') as avi:
        rv.write(header(SECONDS,1,True,720,720,RATE))
        avi.write(b'RIFF'+bytes(4)+b'AVI '+avi_header());movi=avi.tell();avi.write(b'LIST'+bytes(4)+b'movi');base=movi+8
        for n in range(SECONDS):
            packed,preview=pack_and_decode(frame_image(hero,n),photo=n//3 in (0,1,2,5));frame_hashes.append(hashlib.sha256(packed).hexdigest())
            block=pcm[n*RATE*2:(n+1)*RATE*2];audio=pcm16_to_ulaw(block)
            rv.write(packed+bytes(256));rv.write(audio.ljust(AUDIO_BYTES,b'\xff'))
            # Use the actual RVF2 quantized picture and decoded audio in PC previews.
            samples=array.array('h')
            for c in audio:
                code=(~c)&255;v=((132+(code&15)*8)<<((code>>4)&7))-132
                samples.append(-v if code&128 else v)
            decoded.extend(samples)
            if sys.byteorder!='little':samples.byteswap()
            image=io.BytesIO();preview.save(image,'JPEG',quality=96,subsampling=0)
            for tag,payload in ((b'00dc',image.getvalue()),(b'01wb',samples.tobytes())):
                off=avi.tell()-base;avi.write(chunk(tag,payload));index.append(struct.pack('<4sIII',tag,0x10 if tag==b'00dc' else 0,off,len(payload)))
            if n in (0,9,12):preview.save(folder/f'视频实际像素_{n:02d}.png')
            previews.append(preview.resize((360,360),RESAMPLE))
        end=avi.tell();avi.write(chunk(b'idx1',b''.join(index)));total=avi.tell()
        avi.seek(movi+4);avi.write(struct.pack('<I',end-movi-8));avi.seek(4);avi.write(struct.pack('<I',total-8))
    previews[0].save(folder/'视频无声预览.gif',save_all=True,append_images=previews[1:],duration=1000,loop=0)
    # Original synthesized source and mu-law output have equal length and matching timing.
    reference=array.array('h',pcm)
    if sys.byteorder!='little':reference.byteswap()
    corr=sum(a*b for a,b in zip(reference,decoded))/math.sqrt(sum(a*a for a in reference)*sum(b*b for b in decoded))
    record={'application':'digital signage / commercial exhibitions / information publishing',
            'theme':'fictional coffee shop advertising and menu information',
            'artwork_source':'repository AI-generated 1448x1086 coffee_hero.png; reused at native detail',
            'source_artwork_sha256':digest(ROOT/'media/coffee_ad/assets/coffee_hero.png'),
            'width':720,'height':720,'fps':1,'frames':SECONDS,'duration_seconds':SECONDS,'unique_frames':len(set(frame_hashes)),
            'color':'image RGB24; video RGB332, photo region uses 4x4 ordered dithering','audio_hz':RATE,'audio_samples':len(decoded),
            'audio_peak':max(abs(v) for v in decoded),'audio_roundtrip_correlation':corr,
            'audio_source':'original synthesized melody, no external recording',
            'audio_alignment':'12000 samples per picture, cue starts at sample 0 of every frame',
            'picture_bytes':PIXELS,'picture_padding_bytes':256,'audio_padded_bytes':AUDIO_BYTES,
            'hardware_tested':False,'scenes':[{'start_seconds':i*3,'title':p[0]} for i,p in enumerate(SCENES)],
            'generator_sha256':digest(Path(__file__))}
    (folder/'manifest.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(record,ensure_ascii=False,indent=2),flush=True)
    # Optional browser-friendly preview, generated locally from the exact-content AVI.
    if subprocess.run(['gst-inspect-1.0','webmmux'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0:
        subprocess.run(['gst-launch-1.0','-e','-q','filesrc','location='+str(folder/'视频预览.avi'),'!',
          'avidemux','name=d','webmmux','name=m','!','filesink','location='+str(folder/'视频预览.webm'),
          'd.video_0','!','queue','!','jpegdec','!','videoconvert','!','vp8enc','deadline=1','target-bitrate=1800000','!',
          'queue','!','m.video_0','d.audio_0','!','queue','!','audioconvert','!','audioresample','!',
          'vorbisenc','!','queue','!','m.audio_0'],check=True,timeout=90)


if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',type=Path,default=ROOT/'release/resolution_showcase720')
    build(ap.parse_args().output)
