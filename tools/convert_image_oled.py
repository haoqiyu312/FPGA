#!/usr/bin/env python3
"""Convert images to 720x720 RGB24 bottom-up BMP for the OLED player. Requires Pillow.
Use /usr/bin/python3 on the development machine.
"""
import argparse
import os
from pathlib import Path
import tempfile
from PIL import Image, ImageOps


def convert(source, destination, fit='contain'):
    source, destination = Path(source), Path(destination)
    if source.resolve() == destination.resolve():
        raise ValueError('input and output must differ')
    if destination.suffix.lower() != '.bmp':
        raise ValueError('output must use .BMP or .bmp extension')
    resample = getattr(Image, 'Resampling', Image).LANCZOS
    with Image.open(source) as im:
        im = ImageOps.exif_transpose(im).convert('RGB')
        if im.height > im.width:
            im = im.rotate(-90, expand=True)
        if fit == 'cover':
            result = ImageOps.fit(im, (720, 720), method=resample)
        else:
            result = Image.new('RGB', (720, 720), 'black')
            content = ImageOps.contain(im, (720, 720), method=resample)
            result.paste(content, ((720-content.width)//2, (720-content.height)//2))
        fd, temporary = tempfile.mkstemp(prefix='.image-oled-', dir=destination.parent)
        os.close(fd)
        try:
            result.save(temporary, format='BMP')
            os.replace(temporary, destination)
        finally:
            Path(temporary).unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--fit', choices=('contain', 'cover'), default='contain')
    args = parser.parse_args()
    convert(args.input, args.output, args.fit)
    print(f'Wrote OLED 720x720 RGB24 BMP: {args.output}')


if __name__ == '__main__':
    main()
