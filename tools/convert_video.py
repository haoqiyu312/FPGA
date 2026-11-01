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


def audio_layout(fps, audio_rate=48000):
    if audio_rate not in (12000,48000) or fps not in ((1,2,3,4,5) if audio_rate==12000 else (3,4,5)):
        raise ValueError("RVF2 audio requires 1–5 fps at 12 kHz, or 3–5 fps at 48 kHz")
    samples = audio_rate // fps
    return samples, (samples + 511) // 512 * 512


def header(frame_count, fps, with_audio=False, width=WIDTH, height=HEIGHT, audio_rate=48000):
    pixels=width*height
    storage_bytes=(pixels+511)//512*512
    if (width,height) not in ((640,480),(720,720)):
        raise ValueError("supported sizes: 640x480, 720x720")
    samples, audio_bytes = audio_layout(fps,audio_rate) if with_audio else (0, 0)
    limit = (0xFFFFFFFF - 512) // (storage_bytes + audio_bytes)
    if not 1 <= frame_count <= limit or not 1 <= fps <= 5:
        raise ValueError("frame count or fps outside RVF1/FAT32 limits")
    h = struct.pack("<4sBBBBHHII", b"RVF2" if with_audio else b"RVF1",
                    2 if with_audio else 1, 1, fps, 0, width, height, frame_count, storage_bytes)
    if with_audio:
        h += struct.pack("<IIII", audio_rate, samples, audio_bytes, 1)
    return h.ljust(512, b"\0")


def pcm16_to_ulaw(pcm):
    """Mono S16LE to mu-law; no deprecated audioop dependency."""
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


def pack_rgb332(rgb, width=WIDTH, height=HEIGHT):
    if len(rgb) != width*height * 3:
        raise ValueError("incomplete RGB24 frame")
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


def read_frame(stream, width=WIDTH, height=HEIGHT):
    return read_bytes(stream, width*height * 3)


def write_stream(stream, destination, fps, pcm_stream=None, width=WIDTH, height=HEIGHT, audio_rate=48000):
    pixels=width*height
    storage_bytes=(pixels+511)//512*512
    with_audio = pcm_stream is not None
    samples, audio_bytes = audio_layout(fps,audio_rate) if with_audio else (0, 0)
    limit = (0xFFFFFFFF - 512) // (storage_bytes + audio_bytes)
    count = 0
    with open(destination, "wb") as out:
        out.write(bytes(512))
        while True:
            rgb = read_frame(stream,width,height)
            if not rgb:
                break
            if count == limit:
                raise ValueError("video exceeds FAT32 4 GiB file limit; split the input")
            out.write(pack_rgb332(rgb,width,height))
            out.write(bytes(storage_bytes-pixels))
            if with_audio:
                pcm = read_bytes(pcm_stream, samples * 2)
                if len(pcm) % 2:
                    raise ValueError("incomplete PCM16 sample")
                encoded = pcm16_to_ulaw(pcm.ljust(samples * 2, b"\0"))
                out.write(encoded.ljust(audio_bytes, b"\xff"))
            count += 1
        out.seek(0)
        out.write(header(count, fps, with_audio,width,height,audio_rate))
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path, help="copy to FAT32 card root as VIDEO.RV")
    parser.add_argument("--size", choices=("640x480","720x720"), default="640x480")
    parser.add_argument("--audio-rate", type=int, choices=(12000,48000), default=48000)
    parser.add_argument("--fit", choices=("contain","cover"), default="contain", help="preserve aspect ratio: pad or crop")
    parser.add_argument("--fps", type=int, choices=range(1, 6), default=3)
    parser.add_argument("--raw-rgb24", action="store_true", help="input is RGB24 frames at --size")
    parser.add_argument("--audio", action="store_true", help="RVF2 mono soundtrack from movie at --audio-rate")
    parser.add_argument("--pcm16", type=Path, help="RVF2 soundtrack from raw mono S16LE at --audio-rate")
    args = parser.parse_args()
    width,height=map(int,args.size.split("x"))
    if args.input.resolve() == args.output.resolve():
        parser.error("input and output must differ")
    if args.pcm16 and args.pcm16.resolve() == args.output.resolve():
        parser.error("PCM input and output must differ")
    if args.audio and (args.raw_rgb24 or args.pcm16):
        parser.error("--audio requires a movie; use --pcm16 with raw input")
    if (args.audio or args.pcm16) and args.fps not in ((1,2,3,4,5) if args.audio_rate==12000 else (3,4,5)):
        parser.error("48 kHz audio requires --fps 3, 4 or 5; use --audio-rate 12000 for lower fps")
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
                                "-map", "0:a:0", "-vn", "-ac", "1", "-ar", str(args.audio_rate),
                                "-af", f"aresample={args.audio_rate}:async=1:first_pts=0",
                                "-f", "s16le", "pipe:1"], stdout=audio_temp, check=True)
            else:
                print("No audio track; RVF2 soundtrack will be silence")
            audio_temp.seek(0)
            audio_stream = audio_temp
        elif args.pcm16:
            audio_stream = args.pcm16.open("rb")
        if args.raw_rgb24:
            with args.input.open("rb") as stream:
                count = write_stream(stream, temporary, args.fps, audio_stream,width,height,args.audio_rate)
        else:
            aspect = "decrease" if args.fit == "contain" else "increase"
            fit = (f"pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:black" if args.fit == "contain"
                   else f"crop={width}:{height}")
            filters = f"fps={args.fps}:start_time=0,scale={width}:{height}:force_original_aspect_ratio={aspect},{fit},setsar=1"
            process = subprocess.Popen(["ffmpeg", "-nostdin", "-v", "error", "-i", str(args.input),
                                        "-map", "0:v:0", "-an", "-vf", filters,
                                        "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"],
                                       stdout=subprocess.PIPE)
            with process.stdout:
                count = write_stream(process.stdout, temporary, args.fps, audio_stream,width,height,args.audio_rate)
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
