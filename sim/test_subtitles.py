import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from prepare_srt import prepare

class SubtitlePreparation(unittest.TestCase):
    font = (Path(__file__).resolve().parents[1]/'rtl/osd_font16.v').read_text()
    cue = '1\n00:00:00,000 --> 00:00:02,000\n今日推荐\n\n'
    def test_normalize_crlf(self):
        self.assertEqual(prepare(self.cue.replace('\n','\r\n'),self.font),self.cue)
    def test_reject_unknown_glyph(self):
        with self.assertRaisesRegex(ValueError,'缺字'):
            prepare(self.cue.replace('今日推荐','龘'),self.font)
    def test_reject_cache_overflow(self):
        data=''.join(f'{i+1}\n00:00:{i:02d},000 --> 00:00:{i+1:02d},000\nA\n\n' for i in range(17))
        with self.assertRaisesRegex(ValueError,'1–16'):
            prepare(data,self.font)
    def test_reject_overlap(self):
        with self.assertRaisesRegex(ValueError,'重叠'):
            prepare(self.cue+self.cue,self.font)
    def test_reject_long_line(self):
        with self.assertRaisesRegex(ValueError,'1–32'):
            prepare(self.cue.replace('今日推荐','A'*33),self.font)
