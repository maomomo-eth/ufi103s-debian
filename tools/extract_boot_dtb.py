#!/usr/bin/env python3
"""从 Android boot image 的 kernel 尾部提取单个 DTB。"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


FDT_MAGIC = bytes.fromhex("d00dfeed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    image = args.source.read_bytes()
    if image[:8] != b"ANDROID!":
        raise ValueError("源文件不是 Android boot image")

    kernel_size = struct.unpack_from("<I", image, 8)[0]
    page_size = struct.unpack_from("<I", image, 36)[0]
    kernel_offset = page_size
    kernel_end = kernel_offset + kernel_size

    candidates: list[tuple[int, int]] = []
    offset = kernel_offset
    while True:
        offset = image.find(FDT_MAGIC, offset, kernel_end)
        if offset < 0:
            break
        size = struct.unpack_from(">I", image, offset + 4)[0]
        if 40 <= size <= kernel_end - offset:
            candidates.append((offset, size))
        offset += 1

    tail_candidates = [item for item in candidates if item[0] + item[1] == kernel_end]
    if len(tail_candidates) != 1:
        raise ValueError(f"无法唯一确定 kernel 尾部 DTB：{tail_candidates}")

    dtb_offset, dtb_size = tail_candidates[0]
    args.output.write_bytes(image[dtb_offset : dtb_offset + dtb_size])
    print(f"dtb_offset={dtb_offset}")
    print(f"dtb_size={dtb_size}")


if __name__ == "__main__":
    main()

