#!/usr/bin/env python3
"""Validate/normalize an UTF-8 SRT for the bounded FPGA subtitle cache."""
import argparse
from pathlib import Path
import re

STAMP = r'(\d{2}):(\d{2}):(\d{2})[,.](\d{3})'
TIMING = re.compile(STAMP + r'\s+-->\s+' + STAMP)

def milliseconds(fields):
    h, m, s, ms = map(int, fields)
    if m >= 60 or s >= 60:
        raise ValueError('字幕分钟、秒必须小于 60')
    result = ((h*60+m)*60+s)*1000+ms
    if result >= 14400000:
        raise ValueError('字幕时间超过当前硬件的 支持范围（4 小时以内）')
    return result

def prepare(source, font):
    blocks = re.split(r'\n[ \t]*\n', source.replace('\r\n', '\n').replace('\r', '\n').strip())
    glyphs = {int(value, 16) for value in re.findall(r"16'h([0-9a-fA-F]{4}):glyph_index=", font)}
    output = []
    previous_end = 0
    for index, block in enumerate(blocks, 1):
        lines = block.splitlines()
        if len(lines) < 3 or not lines[0].strip().isdigit():
            raise ValueError(f'第 {index} 段须为：序号、时间行、正文')
        match = TIMING.fullmatch(lines[1].strip())
        if not match:
            raise ValueError(f'第 {index} 段时间行不是标准 SRT 格式')
        start, end = milliseconds(match.groups()[:4]), milliseconds(match.groups()[4:])
        if end <= start or start < previous_end:
            raise ValueError(f'第 {index} 段时间倒置或与前一段重叠')
        previous_end = end
        text = ' '.join(line.strip() for line in lines[2:]).strip()
        if not 1 <= len(text) <= 32:
            raise ValueError(f'第 {index} 段合并多行后须为 1–32 个字符，当前 {len(text)}')
        missing = sorted({ch for ch in text if ord(ch) not in glyphs})
        if missing:
            raise ValueError(f'第 {index} 段含当前固件字库缺字：{"".join(missing)}；须扩充字库并重新编译，不能直接复制使用')
        timing = lines[1].strip().replace('.', ',')
        # Canonical spaces matter to the fixed-position hardware timestamp parser.
        timing = re.sub(r'\s+-->\s+', ' --> ', timing)
        output.append(f'{index}\n{timing}\n{text}\n')
    if not 1 <= len(output) <= 16:
        raise ValueError(f'当前缓存支持 1–16 段，实际 {len(output)} 段')
    result = '\n'.join(output) + '\n'
    if len(result.encode()) > 32768:
        raise ValueError('SRT 超过 32768 字节')
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('output', type=Path, help='same ASCII 1–8 character basename as the RV file, e.g. COFFEE.SRT')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Z0-9_]{1,8}\.SRT', args.output.name):
        parser.error('输出名应为 1–8 个大写英文字母/数字/下划线加 .SRT，与视频短文件名一致')
    root = Path(__file__).resolve().parents[1]
    try:
        result = prepare(args.input.read_text(encoding='utf-8-sig'), (root/'rtl/osd_font16.v').read_text())
    except ValueError as error:
        parser.exit(1, f'{error}\n')
    args.output.write_text(result, encoding='utf-8', newline='\n')
    print(f'已生成：{args.output}；KEY3 控制字幕，视频无匹配字幕时不显示演示文案。')

if __name__ == '__main__':
    main()
