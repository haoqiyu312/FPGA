#!/usr/bin/env python3
"""Generate a moving RGB332 test clip without ffmpeg or third-party packages."""
import argparse
import os
import math
import struct
from pathlib import Path
import tempfile
from convert_video import WIDTH, HEIGHT, header, audio_layout, pcm16_to_ulaw


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--seconds", type=int, default=5)
    parser.add_argument("--fps", type=int, choices=range(1, 6), default=3)
    parser.add_argument("--audio", action="store_true", help="RVF2 with a quiet 440 Hz test tone")
    args = parser.parse_args()
    count = args.seconds * args.fps
    h = header(count, args.fps, args.audio)
    samples, audio_bytes = audio_layout(args.fps) if args.audio else (0, 0)
    fd, temporary = tempfile.mkstemp(prefix=".demo-", dir=args.output.parent)
    try:
        with os.fdopen(fd, "wb") as out:
            out.write(h)
            colors = [0xff, 0xe0, 0xfc, 0x1c, 0x1f, 3, 0xe3, 0]
            row = bytes(colors[min(7, x*8//WIDTH)] for x in range(WIDTH))
            for frame in range(count):
                pixels = bytearray(row * HEIGHT)
                x = (frame * 24) % (WIDTH - 64)
                y = (frame * 12) % (HEIGHT - 64)
                for line in range(y, y+64):
                    pixels[line*WIDTH+x:line*WIDTH+x+64] = bytes([0xff])*64
                out.write(pixels)
                if args.audio:
                    values = []
                    for offset in range(samples):
                        tick = frame * samples + offset
                        value = int(4096 * math.sin(2 * math.pi * 440 * tick / 48000)) if tick % 48000 < 24000 else 0
                        values.append(value)
                    pcm = struct.pack(f"<{samples}h", *values)
                    out.write(pcm16_to_ulaw(pcm).ljust(audio_bytes, b"\xff"))
        os.replace(temporary, args.output)
        print(f"Wrote {count} moving test frames at {args.fps} fps: {args.output}")
    finally:
        Path(temporary).unlink(missing_ok=True)


if __name__ == "__main__":
    main()
