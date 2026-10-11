#!/usr/bin/env python3
"""Inspect the manufacturer's touch overlay ZIP using only Python stdlib.

Does not execute files, extract archive paths, or modify the supplied archive.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile


def read_nodes(data):
    if len(data) < 40:
        raise ValueError("Truncated FDT header")
    magic, total, off_struct, off_strings, _, version, _, _, size_strings, size_struct = struct.unpack_from(
        ">10I", data
    )
    if magic != 0xD00DFEED or version < 17 or total > len(data):
        raise ValueError("Unsupported or invalid FDT header")
    if not (40 <= off_struct <= off_struct + size_struct <= total):
        raise ValueError("Invalid structure bounds")
    if not (40 <= off_strings <= off_strings + size_strings <= total):
        raise ValueError("Invalid strings bounds")
    strings = data[off_strings:off_strings + size_strings]
    block = data[off_struct:off_struct + size_struct]
    pos = 0
    stack = []
    nodes = {}
    while pos + 4 <= len(block):
        token = struct.unpack_from(">I", block, pos)[0]
        pos += 4
        if token == 1:
            end = block.index(0, pos)
            stack.append(block[pos:end].decode("ascii"))
            nodes["/".join(stack) or "/"] = {}
            pos = (end + 4) & ~3
        elif token == 2:
            if not stack:
                raise ValueError("Unbalanced node end")
            stack.pop()
        elif token == 3:
            if not stack or pos + 8 > len(block):
                raise ValueError("Invalid property header")
            length, name_off = struct.unpack_from(">II", block, pos)
            pos += 8
            if pos + length > len(block) or name_off >= len(strings):
                raise ValueError("Invalid property bounds")
            end = strings.index(0, name_off)
            name = strings[name_off:end].decode("ascii")
            nodes["/".join(stack) or "/"][name] = block[pos:pos + length]
            pos = (pos + length + 3) & ~3
        elif token == 4:
            continue
        elif token == 9:
            if stack:
                raise ValueError("Unclosed nodes")
            return nodes
        else:
            raise ValueError(f"Unknown FDT token {token}")
    raise ValueError("Missing FDT end token")


def cells(value):
    if len(value) % 4:
        raise ValueError("Property is not a cell array")
    return list(struct.unpack(f">{len(value) // 4}I", value))


def inspect_archive(path):
    result = {"archive_sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "overlays": []}
    with zipfile.ZipFile(path) as archive:
        for entry in sorted(archive.infolist(), key=lambda item: item.filename):
            if not entry.filename.endswith(".dtbo"):
                continue
            if entry.file_size > 1024 * 1024:
                raise ValueError("Unexpectedly large DTBO")
            data = archive.read(entry)
            nodes = read_nodes(data)
            overlay = {"file": entry.filename, "sha256": hashlib.sha256(data).hexdigest(), "touch_nodes": []}
            for node, props in nodes.items():
                compatible = props.get("compatible", b"").rstrip(b"\0").decode("ascii").split("\0")
                if "goodix,gt911" not in compatible:
                    continue
                record = {"node": node, "compatible": compatible,
                          "address": f"0x{cells(props['reg'])[0]:02x}"}
                for name in ("touchscreen-size-x", "touchscreen-size-y", "interrupts", "irq-gpios"):
                    if name in props:
                        record[name] = cells(props[name])
                overlay["touch_nodes"].append(record)
            result["overlays"].append(overlay)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    print(json.dumps(inspect_archive(args.archive), ensure_ascii=False, indent=2))
