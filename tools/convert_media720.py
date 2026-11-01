#!/usr/bin/env python3
"""Convert video for the native 720x720 firmware (1 fps, 12 kHz audio).

Movie conversion requires ffmpeg/ffprobe. Raw RGB24 and optional raw 12 kHz
mono S16LE audio are also supported. --fit cover crops to fill the square.
"""
import sys
from convert_video import main

if __name__ == '__main__':
    # Fix the media contract of this firmware; do not accept conflicting options.
    for flag in ('--size', '--audio-rate'):
        if any(arg == flag or arg.startswith(flag+'=') for arg in sys.argv[1:]):
            raise SystemExit(f'{flag} is fixed by the 720 firmware profile')
    sys.argv.extend(['--size', '720x720', '--audio-rate', '12000'])
    if not any(arg == '--fps' or arg.startswith('--fps=') for arg in sys.argv[1:]):
        sys.argv.extend(['--fps', '1'])
    main()
