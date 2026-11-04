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


class AudioVideoConverterTests(unittest.TestCase):
    def test_audio_header_and_size_limits(self):
        for fps, samples, block in [(3, 4000, 4096), (4, 3000, 3072), (5, 2400, 2560)]:
            h = video.header(2, fps, True)
            self.assertEqual(h[:4], b"RVF2")
            self.assertEqual(h[4:7], bytes([2, 1, fps]))
            self.assertEqual(struct.unpack_from("<IIII", h, 20), (12000, samples, block, 1))
            frame_storage = (video.PIXELS+511)//512*512
            limit = (0xFFFFFFFF - 512) // (frame_storage + block)
            with self.assertRaises(ValueError):
                video.header(limit + 1, fps, True)
        for fps in (0, 6):
            with self.assertRaises(ValueError):
                video.header(1, fps, True)

    def test_reference_audio_vectors(self):
        pcm = struct.pack("<9h", -32768, -32124, -1000, -1, 0, 1, 1000, 32124, 32767)
        self.assertEqual(video.pcm16_to_ulaw(pcm), bytes.fromhex("00 00 4e 7e ff ff ce 80 80"))
        with self.assertRaises(ValueError):
            video.pcm16_to_ulaw(b"x")

    def test_all_pcm_values_against_independent_reference(self):
        try:
            import audioop
        except ImportError:
            self.skipTest("optional CPython audioop reference unavailable")
        pcm = struct.pack("<65536h", *range(-32768, 32768))
        self.assertEqual(video.pcm16_to_ulaw(pcm), audioop.lin2ulaw(pcm, 2))

    def test_interleaving_padding_and_audio_tail(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / "VIDEO.RV"
            rgb = bytes([255, 0, 0]) * video.PIXELS + bytes([0, 0, 255]) * video.PIXELS
            # One full audio frame followed by a short tail, padded with silence.
            pcm = struct.pack("<h", 1000) * 4000 + struct.pack("<h", -1000) * 17
            self.assertEqual(video.write_stream(io.BytesIO(rgb), out, 3, io.BytesIO(pcm)), 2)
            data = out.read_bytes()
            frame_storage = (video.PIXELS+511)//512*512
            stride = frame_storage + 4096
            self.assertEqual(data[:512], video.header(2, 3, True))
            self.assertEqual(len(data), 512 + 2 * stride)
            self.assertEqual(data[512:512+video.PIXELS], bytes([0xE0])*video.PIXELS)
            first = 512 + frame_storage
            self.assertEqual(data[first:first+4096], bytes([0xCE])*4000 + bytes([255])*96)
            second = 512 + stride
            self.assertEqual(data[second:second+video.PIXELS], bytes([3])*video.PIXELS)
            second += frame_storage
            self.assertEqual(data[second:], bytes([0x4E])*17 + bytes([255])*(4096-17))

    def test_short_audio_pipe_reads(self):
        class ShortReader(io.BytesIO):
            def read(self, size=-1):
                return super().read(min(size, 17))
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)/"VIDEO.RV"
            pcm = struct.pack("<h", 1000)*2400
            rgb = bytes(video.PIXELS*3)
            video.write_stream(ShortReader(rgb), out, 5, ShortReader(pcm))
            frame_storage = (video.PIXELS+511)//512*512
            audio = out.read_bytes()[512+frame_storage:]
            self.assertEqual(audio, bytes([0xCE])*2400 + bytes([255])*160)

    def test_cli_preserves_output_on_bad_audio(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            src, pcm, out = directory/"raw.rgb", directory/"raw.pcm", directory/"VIDEO.RV"
            src.write_bytes(bytes(video.PIXELS*3));pcm.write_bytes(b"x");out.write_bytes(b"keep")
            result = subprocess.run([sys.executable, str(ROOT/"tools/convert_video.py"),
                                     str(src), str(out), "--raw-rgb24", "--pcm16", str(pcm)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(out.read_bytes(), b"keep")
            self.assertEqual(list(directory.glob(".video-*")), [])


if __name__ == "__main__":
    unittest.main()
