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


def audio_layout(fps):
    if fps not in (3, 4, 5):
        raise ValueError("RVF2 audio requires 3, 4 or 5 fps")
    samples = 48000 // fps
    return samples, (samples + 511) // 512 * 512


def header(frame_count, fps, with_audio=False):
    samples, audio_bytes = audio_layout(fps) if with_audio else (0, 0)
    limit = (0xFFFFFFFF - 512) // (PIXELS + audio_bytes)
    if not 1 <= frame_count <= limit or not 1 <= fps <= 5:
        raise ValueError("frame count or fps outside RVF1/FAT32 limits")
    h = struct.pack("<4sBBBBHHII", b"RVF2" if with_audio else b"RVF1",
                    2 if with_audio else 1, 1, fps, 0, WIDTH, HEIGHT, frame_count, PIXELS)
    if with_audio:
        h += struct.pack("<IIII", 48000, samples, audio_bytes, 1)
    return h.ljust(512, b"\0")


def pcm16_to_ulaw(pcm):
    """48 kHz mono S16LE to mu-law; no deprecated audioop dependency."""
    if len(pcm) % 2:
        raise ValueError("incomplete PCM16 sample")
    result = bytearray()
    for (sample,) in struct.iter_unpack("<h", pcm):
        value = sample >> 2
        mask = 0x7F if value < 0 else 0xFF
        magnitude = abs(value) + 33
        segment = max(0, magnitude.bit_length() - 6)
        result.append((0x7F if segment >= 8 else
                       (segment << 4) | ((magnitude >> (segment + 1)) & 15)) ^ mask)
    return bytes(result)


def pack_rgb332(rgb):
    if len(rgb) != PIXELS * 3:
        raise ValueError("incomplete 640x480 RGB24 frame")
    return bytes((rgb[i] & 0xE0) | ((rgb[i+1] >> 3) & 0x1C) | (rgb[i+2] >> 6)
                 for i in range(0, len(rgb), 3))


def read_bytes(stream, size):
    data = bytearray()
    while len(data) < size:
        chunk = stream.read(size - len(data))
        if not chunk:
            break
        data.extend(chunk)
    return bytes(data)


def read_frame(stream):
    return read_bytes(stream, PIXELS * 3)


def write_stream(stream, destination, fps, pcm_stream=None):
    with_audio = pcm_stream is not None
    samples, audio_bytes = audio_layout(fps) if with_audio else (0, 0)
    limit = (0xFFFFFFFF - 512) // (PIXELS + audio_bytes)
    count = 0
    with open(destination, "wb") as out:
        out.write(bytes(512))
        while True:
            rgb = read_frame(stream)
            if not rgb:
                break
            if count == limit:
                raise ValueError("video exceeds FAT32 4 GiB file limit; split the input")
            out.write(pack_rgb332(rgb))
            if with_audio:
                pcm = read_bytes(pcm_stream, samples * 2)
                if len(pcm) % 2:
                    raise ValueError("incomplete PCM16 sample")
                encoded = pcm16_to_ulaw(pcm.ljust(samples * 2, b"\0"))
                out.write(encoded.ljust(audio_bytes, b"\xff"))
            count += 1
        out.seek(0)
        out.write(header(count, fps, with_audio))
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path, help="copy to FAT32 card root as VIDEO.RV")
    parser.add_argument("--fps", type=int, choices=range(1, 6), default=3)
    parser.add_argument("--raw-rgb24", action="store_true", help="input is 640x480 RGB24 frames")
    parser.add_argument("--audio", action="store_true", help="RVF2 soundtrack from movie (48 kHz mono)")
    parser.add_argument("--pcm16", type=Path, help="RVF2 soundtrack from raw 48 kHz mono S16LE")
    args = parser.parse_args()
    if args.input.resolve() == args.output.resolve():
        parser.error("input and output must differ")
    if args.pcm16 and args.pcm16.resolve() == args.output.resolve():
        parser.error("PCM input and output must differ")
    if args.audio and (args.raw_rgb24 or args.pcm16):
        parser.error("--audio requires a movie; use --pcm16 with raw input")
    if (args.audio or args.pcm16) and args.fps not in (3, 4, 5):
        parser.error("RVF2 audio requires --fps 3, 4 or 5")
    if not args.raw_rgb24 and not shutil.which("ffmpeg"):
        parser.error("ffmpeg is required for movie conversion")
    if args.audio and not shutil.which("ffprobe"):
        parser.error("ffprobe is required to inspect the movie audio track")
    fd, temporary = tempfile.mkstemp(prefix=".video-", dir=args.output.parent)
    os.close(fd)
    process = None
    audio_stream = None
    audio_temp = None
    try:
        if args.audio:
            probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0",
                                    "-show_entries", "stream=index", "-of", "csv=p=0", str(args.input)],
                                   check=True, capture_output=True, text=True)
            audio_temp = tempfile.TemporaryFile()
            if probe.stdout.strip():
                subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", str(args.input),
                                "-map", "0:a:0", "-vn", "-ac", "1", "-ar", "48000",
                                "-af", "aresample=48000:async=1:first_pts=0",
                                "-f", "s16le", "pipe:1"], stdout=audio_temp, check=True)
            else:
                print("No audio track; RVF2 soundtrack will be silence")
            audio_temp.seek(0)
            audio_stream = audio_temp
        elif args.pcm16:
            audio_stream = args.pcm16.open("rb")
        if args.raw_rgb24:
            with args.input.open("rb") as stream:
                count = write_stream(stream, temporary, args.fps, audio_stream)
        else:
            filters = (f"fps={args.fps}:start_time=0,scale=640:480:force_original_aspect_ratio=decrease,"
                       "pad=640:480:(ow-iw)/2:(oh-ih)/2:black,setsar=1")
            process = subprocess.Popen(["ffmpeg", "-nostdin", "-v", "error", "-i", str(args.input),
                                        "-map", "0:v:0", "-an", "-vf", filters,
                                        "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"],
                                       stdout=subprocess.PIPE)
            with process.stdout:
                count = write_stream(process.stdout, temporary, args.fps, audio_stream)
            if process.wait() != 0:
                raise ValueError("ffmpeg conversion failed")
        os.replace(temporary, args.output)
        print(f"Wrote {count} frames at {args.fps} fps: {args.output} ({args.output.stat().st_size} bytes)")
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            process.wait()
        Path(temporary).unlink(missing_ok=True)
        if audio_stream is not None:
            audio_stream.close()
        if audio_temp is not None and not audio_temp.closed:
            audio_temp.close()


if __name__ == "__main__":
    main()
