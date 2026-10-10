#!/usr/bin/env python3
"""Generate a moving RGB332 test clip without ffmpeg or third-party packages."""
import argparse
import os
from pathlib import Path
import tempfile
from convert_video import WIDTH, HEIGHT, header


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--seconds", type=int, default=5)
    parser.add_argument("--fps", type=int, choices=range(1, 6), default=3)
    args = parser.parse_args()
    count = args.seconds * args.fps
    h = header(count, args.fps)
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
        os.replace(temporary, args.output)
        print(f"Wrote {count} moving test frames at {args.fps} fps: {args.output}")
    finally:
        Path(temporary).unlink(missing_ok=True)


if __name__ == "__main__":
    main()
