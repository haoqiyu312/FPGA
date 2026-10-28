#!/usr/bin/env python3
"""Validate the actual RVF2, BMP, WAV and AVI deliverables and audio roundtrip."""
import argparse
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


def validate(directory):
    manifest=json.loads((directory/'manifest.json').read_text())
    for name,item in manifest['files'].items():
        p=directory/name
        assert p.stat().st_size==item['bytes'],name
        assert hashlib.sha256(p.read_bytes()).hexdigest()==item['sha256'],name
    data=(directory/'sdcard/COFFEE.RV').read_bytes()
    magic,version,layout,fps,unused,width,height,count,pixels=struct.unpack_from('<4sBBBBHHII',data)
    rate,samples,audio_bytes,encoding=struct.unpack_from('<IIII',data,20)
    assert (magic,version,layout,fps,width,height,count,pixels)==(b'RVF2',2,1,3,640,480,54,307200)
    assert (rate,samples,audio_bytes,encoding)==(48000,16000,16384,1)
    assert len(data)==512+count*(pixels+audio_bytes)
    assert len(data)%512==0
    decoded=array.array('h');frame_hashes=set()
    for i in range(count):
        offset=512+i*(pixels+audio_bytes)
        frame_hashes.add(hashlib.sha256(data[offset:offset+pixels]).digest())
        block=data[offset+pixels:offset+pixels+audio_bytes]
        assert block[samples:]==b'\xff'*(audio_bytes-samples)
        for code in block[:samples]:
            u=(~code)&255
            magnitude=((132+(u&15)*8)<<((u>>4)&7))-132
            decoded.append(-magnitude if u&128 else magnitude)
    assert len(frame_hashes)>40,'camera animation is frozen'
    with wave.open(str(directory/'COFFEE_MUSIC.wav'),'rb') as f:
        assert (f.getnchannels(),f.getsampwidth(),f.getframerate(),f.getnframes())==(1,2,48000,864000)
        pcm=array.array('h',f.readframes(f.getnframes()))
    if sys.byteorder!='little':pcm.byteswap()
    assert len(decoded)==len(pcm)
    peak=max(abs(x) for x in pcm)
    assert 1000<peak<32767,'silent or clipped soundtrack'
    xx=sum(x*x for x in pcm);yy=sum(y*y for y in decoded)
    corr=sum(x*y for x,y in zip(pcm,decoded))/math.sqrt(xx*yy)
    assert corr>.995,f'audio roundtrip correlation {corr}'
    for name in ('AD01.BMP','AD02.BMP','AD03.BMP'):
        p=directory/'sdcard'/name
        bmp=p.read_bytes()
        assert bmp[:2]==b'BM'
        assert struct.unpack_from('<iiHHI',bmp,18)==(640,480,1,24,0)
        assert p.stat().st_size==921654
        with Image.open(p) as im:assert im.size==(640,480) and im.mode=='RGB'
    avi=(directory/'COFFEE_PREVIEW.avi').read_bytes()
    assert avi[:4]==b'RIFF' and avi[8:12]==b'AVI '
    assert struct.unpack_from('<I',avi,4)[0]==len(avi)-8
    pos=12;movi_start=None;movi_end=None;idx=None
    while pos+8<=len(avi):
        tag=avi[pos:pos+4];size=struct.unpack_from('<I',avi,pos+4)[0]
        if tag==b'LIST' and avi[pos+8:pos+12]==b'movi':movi_start=pos+8;movi_end=pos+8+size
        if tag==b'idx1':idx=avi[pos+8:pos+8+size]
        pos+=8+size+(size%2)
    assert pos==len(avi) and movi_start and idx
    video_count=0;audio_total=0
    for pos in range(0,len(idx),16):
        tag,flags,offset,size=struct.unpack_from('<4sIII',idx,pos)
        start=movi_start+offset
        assert avi[start:start+4]==tag
        assert struct.unpack_from('<I',avi,start+4)[0]==size
        assert start+8+size<=movi_end
        if tag==b'00dc':
            with Image.open(io.BytesIO(avi[start+8:start+8+size])) as im:
                assert im.size==(640,480);im.verify()
            video_count+=1
        elif tag==b'01wb':audio_total+=size
        else:raise AssertionError('unexpected AVI stream')
    assert video_count==432 and audio_total==864000*2
    result={'rvf2_frames':count,'duration_seconds':18,'unique_frames':len(frame_hashes),
            'posters':3,'pcm_peak':peak,'audio_roundtrip_correlation':corr,
            'avi_frames':video_count,'avi_audio_bytes':audio_total,
            'hardware_tested':False,'rtl_simulation':'not run: Icarus unavailable'}
    (directory/'media_validation.json').write_text(json.dumps(result,indent=2)+'\n')
    print('PASS',json.dumps(result))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory',type=Path)
    validate(parser.parse_args().directory)
