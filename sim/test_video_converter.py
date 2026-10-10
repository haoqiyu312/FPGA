import importlib.util
import io
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("convert_video", ROOT / "tools/convert_video.py")
video = importlib.util.module_from_spec(spec)
spec.loader.exec_module(video)


class VideoConverterTests(unittest.TestCase):
    def test_header_contract(self):
        h = video.header(3, 5)
        self.assertEqual(len(h), 512)
        self.assertEqual(struct.unpack("<4sBBBBHHII", h[:20]),
                         (b"RVF1", 1, 1, 5, 0, 640, 480, 3, 307200))
        self.assertEqual(h[20:], bytes(492))

    def test_rgb332_channel_order(self):
        colors = bytes([255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255])
        self.assertEqual(video.pack_rgb332(colors * (video.PIXELS // 4)),
                         bytes([0xe0, 0x1c, 3, 0xff]) * (video.PIXELS // 4))

    def test_frame_count_and_order(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / "VIDEO.RV"
            source = bytes([255, 0, 0]) * video.PIXELS + bytes([0, 0, 255]) * video.PIXELS
            self.assertEqual(video.write_stream(io.BytesIO(source), out, 2), 2)
            data = out.read_bytes()
            self.assertEqual(data[:512], video.header(2, 2))
            self.assertEqual(data[512:512+video.PIXELS], bytes([0xe0])*video.PIXELS)
            self.assertEqual(data[512+video.PIXELS:], bytes([3])*video.PIXELS)
            self.assertEqual(len(data) % 512, 0)

    def test_empty_and_truncated_streams(self):
        with tempfile.TemporaryDirectory() as directory:
            for data in (b"", b"abc", bytes(video.PIXELS*3-1)):
                with self.assertRaises(ValueError):
                    video.write_stream(io.BytesIO(data), Path(directory)/"bad.rv", 5)

    def test_short_pipe_reads(self):
        class ShortReader(io.BytesIO):
            def read(self, size=-1):
                return super().read(min(size, 997))
        frame = bytes([12, 34, 56]) * video.PIXELS
        self.assertEqual(video.read_frame(ShortReader(frame)), frame)

    def test_generated_demo(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)/"VIDEO.RV"
            subprocess.run([sys.executable, str(ROOT/"tools/make_video_demo.py"),
                            str(out), "--seconds", "1", "--fps", "3"],
                           check=True, capture_output=True)
            data = out.read_bytes()
            self.assertEqual(data[:512], video.header(3, 3))
            self.assertEqual(len(data), 512+3*video.PIXELS)
            self.assertNotEqual(data[512:512+video.PIXELS], data[512+video.PIXELS:512+2*video.PIXELS])

    def test_limits(self):
        for count, fps in [(0, 5), (video.MAX_FRAMES+1, 5), (1, 0), (1, 6)]:
            with self.assertRaises(ValueError):
                video.header(count, fps)
        self.assertEqual(len(video.header(video.MAX_FRAMES, 1)), 512)

    def test_cli_preserves_output_on_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            src, out = Path(directory)/"raw.rgb", Path(directory)/"VIDEO.RV"
            src.write_bytes(b"bad")
            out.write_bytes(b"keep")
            result = subprocess.run([sys.executable, str(ROOT/"tools/convert_video.py"),
                                     str(src), str(out), "--raw-rgb24"], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(out.read_bytes(), b"keep")
            self.assertEqual(list(Path(directory).glob(".video-*")), [])


if __name__ == "__main__":
    unittest.main()
