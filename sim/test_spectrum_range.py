"""Bound the Goertzel recurrence for every possible full-scale 64-sample block."""
import re
import unittest
from pathlib import Path

class SpectrumRange(unittest.TestCase):
    def test_full_scale_state_bound(self):
        source=(Path(__file__).resolve().parents[1]/'rtl/audio_spectrum.v').read_text()
        coefficients=list(map(int,re.findall(r'coefficient=16\'sd(\d+)',source)))
        self.assertEqual(len(coefficients),8)
        for coefficient in coefficients:
            # q[n] is a convolution of PCM and the recurrence impulse response.
            # Each fixed-point truncation contributes less than one extra unit.
            previous,current=0.0,1.0
            gain=0.0
            for _ in range(64):
                gain+=abs(current)
                previous,current=current,coefficient/16384*current-previous
            self.assertLess(32769*gain,2**24, f'25-bit signed state overflows for coefficient {coefficient}')
