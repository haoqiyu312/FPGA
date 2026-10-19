#!/usr/bin/env python3
"""Generate the browser's synchronous 8x8 ASCII ROM (Pillow, DejaVu Sans Mono)."""
import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--font', default='/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf')
parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[1] / 'rtl/browser_ascii_font.v')
args = parser.parse_args()
font = ImageFont.truetype(args.font, 9)
lines = ['// Generated 8x8 ASCII bitmap subset of DejaVu Sans Mono. See THIRD_PARTY_NOTICES.md.',
         'module browser_ascii_font(input wire clk,input wire[6:0] character,input wire[2:0] row,output reg[7:0] pixels);',
         ' reg[7:0] rom[0:1023];', ' initial begin']
for code in range(128):
    bitmap = Image.new('1', (8, 8))
    ImageDraw.Draw(bitmap).text((1, -2), chr(code) if 32 <= code < 127 else '?', font=font, fill=1)
    for row in range(8):
        bits = sum((1 << (7-col)) for col in range(8) if bitmap.getpixel((col, row)))
        lines.append(f" rom[{code*8+row}]=8'h{bits:02x};")
lines += [' end', ' always @(posedge clk)pixels<=rom[{character,row}];', 'endmodule']
args.output.write_text('\n'.join(lines) + '\n')
