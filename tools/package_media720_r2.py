#!/usr/bin/env python3
"""Package the local square-player deliverable after routed timing and media checks."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import xml.etree.ElementTree as ET
from zipfile import ZipFile, ZIP_DEFLATED

ROOT=Path(__file__).resolve().parents[1]
RUN=ROOT/'prj/TF_MEDIA_720_R2_Runs'
BIT=RUN/'phy_1/TF_MEDIA_720_R2_hold.bit'
TIMING=BIT.with_suffix('.timing')
AREA=BIT.with_suffix('.area')
MEDIA=ROOT/'release/media720'
STEM=ROOT/'release/TF_MEDIA_720_R2'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_media():
    result={}
    for path in sorted((MEDIA/'sdcard').iterdir()):
        raw=path.read_bytes()
        if path.suffix.upper()=='.BMP':
            offset=struct.unpack_from('<I',raw,10)[0]
            if raw[:2]!=b'BM' or struct.unpack_from('<iiHHI',raw,18)!=(720,720,1,24,0):
                raise ValueError(f'invalid square BMP: {path}')
            if len(raw)-offset!=720*720*3:raise ValueError(f'truncated BMP: {path}')
        elif path.suffix.upper()=='.RV':
            magic,version,format_,fps,_,w,h,frames,padded=struct.unpack_from('<4sBBBBHHII',raw)
            if (magic,version,format_,w,h,padded)!=(b'RVF2',2,1,720,720,518656) or fps!=1 or frames<1:
                raise ValueError('unexpected square demo video contract')
            if struct.unpack_from('<IIII',raw,20)!=(12000,12000,12288,1):
                raise ValueError('unexpected square audio contract')
            stride=padded+12288
            if len(raw)!=512+frames*stride:raise ValueError('video length mismatch')
            for index in range(frames):
                base=512+index*stride
                if raw[base+518400:base+padded]!=bytes(256):raise ValueError('picture sector padding mismatch')
                if raw[base+padded+12000:base+stride]!=bytes([255])*288:raise ValueError('audio sector padding mismatch')
        else:
            raise ValueError(f'unexpected SD file: {path}')
        result[path.name]={'bytes':len(raw),'sha256':sha(path)}
    if len(result)!=4:raise ValueError('expected three BMP files and one RV file')
    return result


def main():
    metrics={}
    report=TIMING.read_text()
    if not re.search(r'Confidence\s*:\s*Routed',report):raise ValueError('final routed report required')
    for label in ('SWNS','STNS','HWNS','HTNS'):
        match=re.search(r'\b'+label+r':\s*(-?\d+(?:\.\d+)?)ns',report)
        if not match or float(match[1])<0:raise ValueError(f'{label} missing or violated')
        metrics[label+'_ns']=float(match[1])
    resources={}
    for key in ('lut','reg','bram','pll'):
        match=re.search(r'^#'+key+r'\s+(\d+)\s+out of\s+(\d+)',AREA.read_text(),re.M)
        if not match or int(match[1])>int(match[2]):raise ValueError(f'{key} missing or over capacity')
        resources[key]={'used':int(match[1]),'capacity':int(match[2])}
    project=ROOT/'prj/TF_MEDIA_720_R2.al'
    inputs={project,ROOT/'prj/build_tf_media720_r2.tcl',ROOT/'prj/fix_tf_media720_r2_hold.tcl'}
    # TD writes the legacy UsedInP&R attribute without XML escaping.
    project_xml=ET.fromstring(project.read_text().replace('UsedInP&R','UsedInP&amp;R'))
    for entry in project_xml.iter('File'):
        if 'Path' in entry.attrib:inputs.add((project.parent/entry.attrib['Path']).resolve())
    inputs.update(ROOT/'tools'/name for name in ('convert_video.py','convert_image720.py','convert_media720.py','make_media720_demo.py'))
    inputs={path for path in inputs if path.is_file()}
    gate=RUN/'syn_1/TF_MEDIA_720_R2_gate.db'
    if any(path.stat().st_mtime>gate.stat().st_mtime for path in inputs if path.suffix in ('.v','.adc')):
        raise ValueError('synthesis is older than RTL/constraints')
    if BIT.stat().st_mtime<max(path.stat().st_mtime for path in (gate,TIMING,AREA)):
        raise ValueError('bitstream is older than its implementation/reports')
    if any(path.stat().st_mtime>TIMING.stat().st_mtime for path in inputs if path.suffix=='.sdc'):
        raise ValueError('final timing is older than current SDC')
    sd=validate_media()
    record={'file':STEM.with_suffix('.bit').name,'sha256':sha(BIT),'device':'EG4S20BG256',
            'tool':'Tang Dynasty 6.2.1 SP1 build 178840','width':720,'height':720,
            'pixel_hz':48000000,'memory_hz':50000000,'display_refresh_hz':48000000/(940*768),
            'panel_timing_source':'https://docs.waveshare.net/4inch_HDMI_LCD_C_/',
            'panel_identity':'inferred from prior user specifications; not yet confirmed by model/EDID',
            'recommended_video_fps':1,'audio_hz':12000,
            'spectrum_enabled':False,'feature_limit':'recovery candidate temporarily disables the spectrum layer to fit physical resources','timing':metrics,'resources':resources,
            'validation':{'build':'passed','routed_timing':'passed','python_tests':'20 passed',
                          'rtl_simulation':'not run: iverilog/vvp unavailable',
                          'hardware':'candidate not board tested; first 25MHz 720 release was reported black',
                          'storage_clock':'new 50MHz / 162 degree (9ns) SDRAM clock requires board confirmation'},
            'sources_sha256':{str(p.relative_to(ROOT)):sha(p) for p in sorted(inputs)},
            'sdcard':sd,'reports_sha256':{p.name:sha(p) for p in (TIMING,AREA)}}
    for source,suffix in ((BIT,'.bit'),(TIMING,'.timing'),(AREA,'.area')):
        shutil.copyfile(source,STEM.with_suffix(suffix))
    STEM.with_suffix('.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
    readme=ROOT/'docs/720方屏使用说明.md'
    with ZipFile(STEM.with_suffix('.zip'),'w',ZIP_DEFLATED) as bundle:
        for suffix in ('.bit','.json','.timing','.area'):
            path=STEM.with_suffix(suffix);bundle.write(path,path.name)
        bundle.write(readme,'使用说明.md')
        bundle.write(MEDIA/'VIDEO_PREVIEW.png','VIDEO_PREVIEW.png')
        bundle.write(MEDIA/'media.json','media.json')
        for path in sorted((MEDIA/'sdcard').iterdir()):bundle.write(path,'sdcard/'+path.name)
    print(json.dumps({key:record[key] for key in ('file','sha256','timing','resources')},ensure_ascii=False,indent=2))
    print(STEM.with_suffix('.zip'))


if __name__=='__main__':
    main()
