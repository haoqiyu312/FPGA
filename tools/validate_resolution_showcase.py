#!/usr/bin/env python3
"""Validate native square media, frame/audio pairing, previews and source fidelity."""
import array
import hashlib
import io
import json
import math
from pathlib import Path
import struct
import sys
import wave
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
FOLDER=ROOT/'release/resolution_showcase720'


def validate(folder=FOLDER):
    meta=json.loads((folder/'manifest.json').read_text())
    assert sorted(p.name for p in (folder/'sdcard').iterdir())==['AD720.BMP','AV720.RV']
    bmp=(folder/'sdcard/AD720.BMP').read_bytes()
    assert bmp[:2]==b'BM'
    assert struct.unpack_from('<iiHHI',bmp,18)==(720,720,1,24,0)
    offset=struct.unpack_from('<I',bmp,10)[0]
    assert len(bmp)==offset+720*720*3
    with Image.open(folder/'sdcard/AD720.BMP') as im:
        assert im.size==(720,720) and im.mode=='RGB'
        with Image.open(folder/'图片预览.png') as preview:assert im.tobytes()==preview.tobytes()
    raw=(folder/'sdcard/AV720.RV').read_bytes()
    assert struct.unpack_from('<4sBBBBHHII',raw)==(b'RVF2',2,1,1,0,720,720,18,518656)
    assert struct.unpack_from('<IIII',raw,20)==(12000,12000,12288,1)
    stride=518656+12288
    assert len(raw)==512+18*stride and len(raw)%512==0
    decoded=array.array('h');hashes=set();audio_banks=[]
    for n in range(18):
        start=512+n*stride;pic=raw[start:start+518400]
        assert len(pic)==518400
        hashes.add(hashlib.sha256(pic).hexdigest())
        assert raw[start+518400:start+518656]==bytes(256)
        sound=raw[start+518656:start+stride]
        assert sound[12000:]==bytes([255])*288
        samples=[]
        for c in sound[:12000]:
            u=(~c)&255;v=((132+(u&15)*8)<<((u>>4)&7))-132
            samples.append(-v if u&128 else v)
        assert sum(v*v for v in samples)/12000>100000,'silent audio frame'
        decoded.extend(samples);audio_banks.append(samples)
    assert len(hashes)==18==meta['unique_frames']
    assert len(decoded)==18*12000
    with wave.open(str(folder/'配乐试听.wav')) as w:
        assert (w.getnchannels(),w.getsampwidth(),w.getframerate(),w.getnframes())==(1,2,12000,216000)
        reference=array.array('h',w.readframes(w.getnframes()))
    if sys.byteorder!='little':reference.byteswap()
    corr=sum(a*b for a,b in zip(reference,decoded))/math.sqrt(sum(a*a for a in reference)*sum(b*b for b in decoded))
    assert corr>.995
    assert 1000<max(abs(v) for v in decoded)<32767
    # Check every video audio block against exactly the corresponding second,
    # not merely total duration. Adjacent-second mismatch must correlate less.
    for i,samples in enumerate(audio_banks):
        correct=reference[i*12000:(i+1)*12000]
        wrong=reference[((i+1)%18)*12000:(((i+1)%18)+1)*12000]
        def similarity(a,b):return sum(x*y for x,y in zip(a,b))/math.sqrt(sum(x*x for x in a)*sum(y*y for y in b))
        assert similarity(samples,correct)>.995
        assert similarity(samples,correct)>similarity(samples,wrong)
    avi=(folder/'视频预览.avi').read_bytes()
    assert avi[:4]==b'RIFF' and avi[8:12]==b'AVI '
    assert struct.unpack_from('<I',avi,4)[0]==len(avi)-8
    pos=12;index=None;movi=None;movi_end=None
    while pos+8<=len(avi):
        tag=avi[pos:pos+4];size=struct.unpack_from('<I',avi,pos+4)[0]
        if tag==b'LIST' and avi[pos+8:pos+12]==b'movi':movi=pos+8;movi_end=pos+8+size
        if tag==b'idx1':index=avi[pos+8:pos+8+size]
        pos+=8+size+size%2
    assert pos==len(avi) and movi and index
    pictures=0;preview_audio=array.array('h')
    for p in range(0,len(index),16):
        tag,flags,off,size=struct.unpack_from('<4sIII',index,p)
        start=movi+off
        assert avi[start:start+4]==tag and struct.unpack_from('<I',avi,start+4)[0]==size
        assert start+8+size<=movi_end
        data=avi[start+8:start+8+size]
        if tag==b'00dc':
            with Image.open(io.BytesIO(data)) as im:assert im.size==(720,720);im.verify()
            pictures+=1
        elif tag==b'01wb':preview_audio.frombytes(data)
        else:raise AssertionError('unexpected stream')
    if sys.byteorder!='little':preview_audio.byteswap()
    assert pictures==18 and preview_audio==decoded
    assert hashlib.sha256((ROOT/'media/coffee_ad/assets/coffee_hero.png').read_bytes()).hexdigest()==meta['source_artwork_sha256']
    assert hashlib.sha256((ROOT/'tools/make_resolution_showcase.py').read_bytes()).hexdigest()==meta['generator_sha256']
    result={'image_format':'passed: native 720x720 RGB24 bottom-up BMP',
            'video_format':'passed: 18 unique native 720x720 RGB332 frames at 1 fps',
            'picture_and_audio_padding':'passed: 18 frames',
            'audio_pairing':'passed: every frame contains the correct second of the soundtrack',
            'audio_samples':len(decoded),'audio_duration_seconds':len(decoded)/12000,
            'audio_peak':max(abs(v) for v in decoded),'audio_roundtrip_correlation':corr,
            'avi_picture_and_audio_length':'passed: 18 pictures and exact decoded audio',
            'hardware_tested':False}
    (folder/'validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(result,ensure_ascii=False,indent=2))
    return result


if __name__=='__main__':validate()
