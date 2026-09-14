#!/usr/bin/env python3
"""在不移动 ramdisk 的前提下替换 Android boot image 尾部 DTB。"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


FDT_MAGIC = bytes.fromhex("d00dfeed")


def align(value: int, alignment: int) -> int:
    return (value + alignment - 1) // alignment * alignment


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("dtb", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    image = bytearray(args.source.read_bytes())
    new_dtb = args.dtb.read_bytes()
    if image[:8] != b"ANDROID!":
        raise ValueError("源文件不是 Android boot image")
    if new_dtb[:4] != FDT_MAGIC:
        raise ValueError("替换文件不是有效 DTB")
    if struct.unpack_from(">I", new_dtb, 4)[0] != len(new_dtb):
        raise ValueError("DTB totalsize 与文件大小不一致")

    kernel_size = struct.unpack_from("<I", image, 8)[0]
    page_size = struct.unpack_from("<I", image, 36)[0]
    kernel_offset = page_size
    kernel_end = kernel_offset + kernel_size
    ramdisk_offset = align(kernel_end, page_size)

    fdt_offset = image.find(FDT_MAGIC, kernel_offset, kernel_end)
    if fdt_offset < 0:
        raise ValueError("kernel 尾部未找到 DTB")
    old_dtb_size = struct.unpack_from(">I", image, fdt_offset + 4)[0]
    if fdt_offset + old_dtb_size != kernel_end:
        raise ValueError("旧 DTB 不在 kernel 数据尾部")

    new_kernel_size = fdt_offset - kernel_offset + len(new_dtb)
    new_kernel_end = kernel_offset + new_kernel_size
    if align(new_kernel_end, page_size) != ramdisk_offset:
        raise ValueError("新 DTB 超出原有对齐空隙，会移动 ramdisk")

    image[fdt_offset:ramdisk_offset] = bytes(ramdisk_offset - fdt_offset)
    image[fdt_offset : fdt_offset + len(new_dtb)] = new_dtb
    struct.pack_into("<I", image, 8, new_kernel_size)

    args.output.write_bytes(image)
    print(f"old_kernel_size={kernel_size}")
    print(f"new_kernel_size={new_kernel_size}")
    print(f"old_dtb_size={old_dtb_size}")
    print(f"new_dtb_size={len(new_dtb)}")
    print(f"fdt_offset={fdt_offset}")
    print(f"ramdisk_offset={ramdisk_offset}")
    print(f"output_size={len(image)}")


if __name__ == "__main__":
    main()

