#!/usr/bin/env python3
"""Convert a movie (ffmpeg) or RGB24 stream to sector-aligned VIDEO.RV.

Uses no Python third-party packages. RGB332 layout is RRR GGG BB, top-down.
Writes atomically; failed conversion leaves the destination intact.
"""
import argparse
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

WIDTH, HEIGHT = 640, 480
PIXELS = WIDTH * HEIGHT
MAX_FRAMES = (0xFFFFFFFF - 512) // PIXELS


def header(frame_count, fps):
    if not 1 <= frame_count <= MAX_FRAMES or not 1 <= fps <= 5:
        raise ValueError("frame count or fps outside RVF1/FAT32 limits")
    return struct.pack("<4sBBBBHHII", b"RVF1", 1, 1, fps, 0,
                       WIDTH, HEIGHT, frame_count, PIXELS).ljust(512, b"\0")


def pack_rgb332(rgb):
    if len(rgb) != PIXELS * 3:
        raise ValueError("incomplete 640x480 RGB24 frame")
    return bytes((rgb[i] & 0xE0) | ((rgb[i+1] >> 3) & 0x1C) | (rgb[i+2] >> 6)
                 for i in range(0, len(rgb), 3))


def read_frame(stream):
    data = bytearray()
    while len(data) < PIXELS * 3:
        chunk = stream.read(PIXELS * 3 - len(data))
        if not chunk:
            break
        data.extend(chunk)
    return bytes(data)


def write_stream(stream, destination, fps):
    count = 0
    with open(destination, "wb") as out:
        out.write(bytes(512))
        while True:
            rgb = read_frame(stream)
            if not rgb:
                break
            if count == MAX_FRAMES:
                raise ValueError("video exceeds FAT32 4 GiB file limit; split the input")
            out.write(pack_rgb332(rgb))
            count += 1
        out.seek(0)
        out.write(header(count, fps))
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path, help="copy to FAT32 card root as VIDEO.RV")
    parser.add_argument("--fps", type=int, choices=range(1, 6), default=3)
    parser.add_argument("--raw-rgb24", action="store_true", help="input is 640x480 RGB24 frames")
    args = parser.parse_args()
    if args.input.resolve() == args.output.resolve():
        parser.error("input and output must differ")
    if not args.raw_rgb24 and not shutil.which("ffmpeg"):
        parser.error("ffmpeg is required for movie conversion")
    fd, temporary = tempfile.mkstemp(prefix=".video-", dir=args.output.parent)
    os.close(fd)
    process = None
    try:
        if args.raw_rgb24:
            with args.input.open("rb") as stream:
                count = write_stream(stream, temporary, args.fps)
        else:
            filters = (f"fps={args.fps},scale=640:480:force_original_aspect_ratio=decrease,"
                       "pad=640:480:(ow-iw)/2:(oh-ih)/2:black,setsar=1")
            process = subprocess.Popen(["ffmpeg", "-nostdin", "-v", "error", "-i", str(args.input),
                                        "-map", "0:v:0", "-an", "-vf", filters,
                                        "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"],
                                       stdout=subprocess.PIPE)
            with process.stdout:
                count = write_stream(process.stdout, temporary, args.fps)
            if process.wait() != 0:
                raise ValueError("ffmpeg conversion failed")
        os.replace(temporary, args.output)
        print(f"Wrote {count} frames at {args.fps} fps: {args.output} ({512+count*PIXELS} bytes)")
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            process.wait()
        Path(temporary).unlink(missing_ok=True)


if __name__ == "__main__":
    main()
