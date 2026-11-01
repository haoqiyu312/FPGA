"""Native square media contract, sector padding, audio and atomic conversion."""
import importlib.util
import io
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('convert_video', ROOT/'tools/convert_video.py')
video = importlib.util.module_from_spec(spec)
spec.loader.exec_module(video)
PIXELS, STORAGE = 720*720, 518656


class SquareVideoTests(unittest.TestCase):
    def test_header_and_sector_padding(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)/'VIDEO.RV'
            rgb = bytes([255, 0, 0])*PIXELS + bytes([0, 0, 255])*PIXELS
            self.assertEqual(video.write_stream(io.BytesIO(rgb), out, 1, width=720, height=720), 2)
            data = out.read_bytes()
            self.assertEqual(struct.unpack('<4sBBBBHHII', data[:20]),
                             (b'RVF1', 1, 1, 1, 0, 720, 720, 2, STORAGE))
            self.assertEqual(len(data), 512+2*STORAGE)
            self.assertEqual(data[512:512+PIXELS], bytes([0xe0])*PIXELS)
            self.assertEqual(data[512+PIXELS:512+STORAGE], bytes(256))
            self.assertEqual(data[512+STORAGE:512+STORAGE+PIXELS], bytes([3])*PIXELS)

    def test_low_rate_audio_layout_all_fps(self):
        for fps in range(1, 6):
            samples, padded = video.audio_layout(fps, 12000)
            self.assertEqual(samples*fps, 12000)
            self.assertLessEqual(samples, 16384)
            self.assertEqual(padded%512, 0)
            header = video.header(2, fps, True, 720, 720, 12000)
            self.assertEqual(struct.unpack('<IIII', header[20:36]), (12000, samples, padded, 1))
        with self.assertRaises(ValueError):
            video.audio_layout(1, 48000)

    def test_audio_starts_after_padded_picture(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)/'VIDEO.RV'
            video.write_stream(io.BytesIO(bytes([255, 255, 255])*PIXELS), out, 1,
                               io.BytesIO(bytes(12000*2)), 720, 720, 12000)
            data = out.read_bytes()
            self.assertEqual(data[512+PIXELS:512+STORAGE], bytes(256))
            self.assertEqual(data[512+STORAGE:], bytes([255])*12288)
            self.assertEqual(len(data)%512, 0)

    def test_profile_cli_and_atomic_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            source, out = Path(folder)/'frame.rgb', Path(folder)/'VIDEO.RV'
            source.write_bytes(bytes(PIXELS*3))
            command = [sys.executable, str(ROOT/'tools/convert_media720.py'), str(source), str(out), '--raw-rgb24']
            subprocess.run(command, check=True, capture_output=True)
            original = out.read_bytes()
            self.assertEqual(original[6], 1)
            self.assertEqual(struct.unpack('<HH', original[8:12]), (720, 720))
            source.write_bytes(b'partial frame')
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            self.assertEqual(out.read_bytes(), original)


try:
    from PIL import Image
except ImportError:
    Image = None


@unittest.skipIf(Image is None, 'Pillow unavailable in this interpreter')
class SquareImageTests(unittest.TestCase):
    def test_image_geometry_bmp_contract_and_preserved_source(self):
        spec = importlib.util.spec_from_file_location('image720', ROOT/'tools/convert_image720.py')
        image720 = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(image720)
        with tempfile.TemporaryDirectory() as folder:
            source, out = Path(folder)/'source.png', Path(folder)/'IMAGE.BMP'
            im = Image.new('RGB', (640,480), 'red')
            im.save(source)
            original = source.read_bytes()
            image720.convert(source, out)
            raw = out.read_bytes()
            offset = struct.unpack_from('<I', raw, 10)[0]
            self.assertEqual(struct.unpack_from('<iiHHI', raw, 18), (720,720,1,24,0))
            self.assertEqual(len(raw)-offset, PIXELS*3)
            with Image.open(out) as actual:
                self.assertEqual(actual.getpixel((360,0)), (0,0,0))
                self.assertEqual(actual.getpixel((360,360)), (255,0,0))
            image720.convert(source, out, 'cover')
            with Image.open(out) as actual:
                self.assertEqual(actual.getpixel((0,0)), (255,0,0))
            self.assertEqual(source.read_bytes(), original)


if __name__ == '__main__':
    unittest.main()
