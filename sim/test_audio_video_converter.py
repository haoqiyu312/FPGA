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
        for fps, samples, block in [(3, 16000, 16384), (4, 12000, 12288), (5, 9600, 9728)]:
            h = video.header(2, fps, True)
            self.assertEqual(h[:4], b"RVF2")
            self.assertEqual(h[4:7], bytes([2, 1, fps]))
            self.assertEqual(struct.unpack_from("<IIII", h, 20), (48000, samples, block, 1))
            limit = (0xFFFFFFFF - 512) // (video.PIXELS + block)
            with self.assertRaises(ValueError):
                video.header(limit + 1, fps, True)
        for fps in (0, 1, 2, 6):
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
            pcm = struct.pack("<h", 1000) * 16000 + struct.pack("<h", -1000) * 17
            self.assertEqual(video.write_stream(io.BytesIO(rgb), out, 3, io.BytesIO(pcm)), 2)
            data = out.read_bytes()
            stride = video.PIXELS + 16384
            self.assertEqual(data[:512], video.header(2, 3, True))
            self.assertEqual(len(data), 512 + 2 * stride)
            self.assertEqual(data[512:512+video.PIXELS], bytes([0xE0])*video.PIXELS)
            first = 512 + video.PIXELS
            self.assertEqual(data[first:first+16384], bytes([0xCE])*16000 + bytes([255])*384)
            second = 512 + stride
            self.assertEqual(data[second:second+video.PIXELS], bytes([3])*video.PIXELS)
            second += video.PIXELS
            self.assertEqual(data[second:], bytes([0x4E])*17 + bytes([255])*(16384-17))

    def test_short_audio_pipe_reads(self):
        class ShortReader(io.BytesIO):
            def read(self, size=-1):
                return super().read(min(size, 17))
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)/"VIDEO.RV"
            pcm = struct.pack("<h", 1000)*9600
            rgb = bytes(video.PIXELS*3)
            video.write_stream(ShortReader(rgb), out, 5, ShortReader(pcm))
            audio = out.read_bytes()[512+video.PIXELS:]
            self.assertEqual(audio, bytes([0xCE])*9600 + bytes([255])*128)

    def test_generated_audible_demo(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)/"VIDEO.RV"
            subprocess.run([sys.executable, str(ROOT/"tools/make_video_demo.py"), str(out),
                            "--seconds", "1", "--fps", "3", "--audio"], check=True, capture_output=True)
            data = out.read_bytes()
            self.assertEqual(data[:512], video.header(3, 3, True))
            self.assertEqual(len(data), 512+3*(video.PIXELS+16384))
            audio = b"".join(data[512+i*(video.PIXELS+16384)+video.PIXELS:]
                             [:16000] for i in range(3))
            self.assertGreater(len(set(audio[:24000])), 30)
            self.assertEqual(audio[24000:], bytes([255])*24000)

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
