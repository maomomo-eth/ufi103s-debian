#!/usr/bin/env python3
"""从同一台 UFI103S 的原厂全盘备份组装 Debian v2 整盘 EDL 镜像。"""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import struct
import zlib
from pathlib import Path


SECTOR = 512
DISK_BYTES = 3909091328  # 已核对的 UFI103S V02/V03 4 GB eMMC；不猜测其他容量。
DISK_SECTORS = DISK_BYTES // SECTOR
ENTRY_COUNT = 128
ENTRY_SIZE = 128
ENTRY_BYTES = ENTRY_COUNT * ENTRY_SIZE
GPT_TEMPLATE_BYTES = 3 * SECTOR + 2 * ENTRY_BYTES
CHUNK = 8 * 1024 * 1024
CALIBRATION = ("fsc", "fsg", "modemst1", "modemst2")
STOCK_PARTITIONS = {
    "modem": (131072, 262143),
    "aboot": (264192, 266239),
    "modemst1": (276480, 279551),
    "modemst2": (279552, 282623),
    "fsc": (284672, 284673),
    "fsg": (393280, 396351),
    "boot": (396384, 429151),
    "persist": (2067552, 2133087),
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def partition_entries(raw: bytes, count: int) -> dict[str, tuple[int, int]]:
    result: dict[str, tuple[int, int]] = {}
    for index in range(count):
        entry = raw[index * ENTRY_SIZE : (index + 1) * ENTRY_SIZE]
        if not any(entry[:16]):
            continue
        name = entry[56:128].decode("utf-16-le").split("\x00", 1)[0]
        first, last = struct.unpack_from("<QQ", entry, 32)
        require(name not in result and first <= last, f"分区条目异常：{name}")
        result[name] = (first, last)
    return result


def verify_header(header: bytes, entries: bytes, *, current: int, backup: int, array_lba: int) -> None:
    require(header[:8] == b"EFI PART", "GPT header 签名不正确")
    size, crc = struct.unpack_from("<II", header, 12)
    require(size == 92, "GPT header 尺寸不正确")
    header_copy = bytearray(header[:size])
    struct.pack_into("<I", header_copy, 16, 0)
    require(crc == zlib.crc32(header_copy) & 0xFFFFFFFF, "GPT header CRC 错误")
    require(struct.unpack_from("<QQ", header, 24) == (current, backup), "GPT 主备地址错误")
    require(struct.unpack_from("<Q", header, 72)[0] == array_lba, "GPT 条目地址错误")
    count, entry_size, entries_crc = struct.unpack_from("<III", header, 80)
    require(entry_size == ENTRY_SIZE and 0 < count <= ENTRY_COUNT, "GPT 条目规格错误")
    require(len(entries) >= count * entry_size, "GPT 条目长度不足")
    require(entries_crc == zlib.crc32(entries[: count * entry_size]) & 0xFFFFFFFF,
            "GPT 条目 CRC 错误")


def verify_stock(backup_dir: Path) -> None:
    original = backup_dir / "original-full-emmc.bin"
    require(original.is_file() and original.stat().st_size == DISK_BYTES,
            "原厂完整 eMMC 备份缺失或容量不匹配")
    with original.open("rb") as stream:
        primary = stream.read(34 * SECTOR)
        require(primary[450] == 0xEE, "原厂保护 MBR 不正确")
        header = primary[SECTOR : 2 * SECTOR]
        count, size = struct.unpack_from("<II", header, 80)
        require(size == ENTRY_SIZE, "原厂 GPT 条目规格不正确")
        entries = primary[2 * SECTOR : 2 * SECTOR + count * size]
        verify_header(header, entries, current=1, backup=DISK_SECTORS - 1, array_lba=2)
        stock = partition_entries(entries, count)
        for name, expected in STOCK_PARTITIONS.items():
            require(stock.get(name) == expected, f"原厂 GPT {name} 布局不匹配")
        for name in (*CALIBRATION, "persist"):
            image = backup_dir / "partitions" / f"{name}.bin"
            first, last = stock[name]
            require(image.is_file() and image.stat().st_size == (last - first + 1) * SECTOR,
                    f"同机原厂校准备份缺失或大小错误：{name}")
            stream.seek(first * SECTOR)
            require(stream.read(image.stat().st_size) == image.read_bytes(),
                    f"{name} 与完整原厂备份不一致，可能混用了其他设备的文件")


def patch_header(header: bytearray, *, current: int, backup: int, entries_lba: int,
                 last_usable: int, entries_crc: int) -> None:
    require(header[:8] == b"EFI PART", "Release GPT header 无效")
    struct.pack_into("<Q", header, 24, current)
    struct.pack_into("<Q", header, 32, backup)
    struct.pack_into("<Q", header, 40, 34)
    struct.pack_into("<Q", header, 48, last_usable)
    struct.pack_into("<Q", header, 72, entries_lba)
    # 原包只声明 16 个条目；扩展为 128 后才可校验完整的 32 扇区条目数组。
    struct.pack_into("<I", header, 80, ENTRY_COUNT)
    struct.pack_into("<I", header, 84, ENTRY_SIZE)
    struct.pack_into("<I", header, 88, entries_crc)
    struct.pack_into("<I", header, 16, 0)
    struct.pack_into("<I", header, 16, zlib.crc32(header[:92]) & 0xFFFFFFFF)


def build_gpt(template: Path) -> tuple[bytes, bytes, dict[str, tuple[int, int]]]:
    raw = template.read_bytes()
    require(len(raw) == GPT_TEMPLATE_BYTES, "v2 GPT 模板大小不正确")
    mbr = bytearray(raw[:SECTOR])
    require(mbr[450] == 0xEE and mbr[510:512] == b"\x55\xaa", "Release 保护 MBR 无效")
    struct.pack_into("<I", mbr, 454, 1)
    struct.pack_into("<I", mbr, 458, DISK_SECTORS - 1)
    entries = bytearray(raw[2 * SECTOR : 2 * SECTOR + ENTRY_BYTES])
    require(entries == raw[2 * SECTOR + ENTRY_BYTES : -SECTOR], "Release 主备 GPT 条目不同")
    last_usable = DISK_SECTORS - 34
    rootfs_index = next(
        (index for index in range(ENTRY_COUNT)
         if entries[index * ENTRY_SIZE + 56 : (index + 1) * ENTRY_SIZE]
         .decode("utf-16-le").split("\x00", 1)[0] == "rootfs"), None
    )
    require(rootfs_index is not None, "Release GPT 没有 rootfs 分区")
    struct.pack_into("<Q", entries, rootfs_index * ENTRY_SIZE + 40, last_usable)
    parts = partition_entries(entries, ENTRY_COUNT)
    require(len(parts) == 14 and parts["rootfs"][1] == last_usable,
            "Release GPT 分区数量或 rootfs 边界异常")
    occupied = sorted((first, last, name) for name, (first, last) in parts.items())
    for first, last, name in occupied:
        require(34 <= first <= last <= last_usable, f"分区越界：{name}")
    for left, right in zip(occupied, occupied[1:]):
        require(left[1] < right[0], f"分区重叠：{left[2]} 与 {right[2]}")
    crc = zlib.crc32(entries) & 0xFFFFFFFF
    primary_header = bytearray(raw[SECTOR : 2 * SECTOR])
    backup_header = bytearray(raw[-SECTOR:])
    patch_header(primary_header, current=1, backup=DISK_SECTORS - 1,
                 entries_lba=2, last_usable=last_usable, entries_crc=crc)
    patch_header(backup_header, current=DISK_SECTORS - 1, backup=1,
                 entries_lba=DISK_SECTORS - 33, last_usable=last_usable, entries_crc=crc)
    return bytes(mbr + primary_header + entries), bytes(entries + backup_header), parts


def wipe_range(stream, offset: int, size: int) -> None:
    stream.seek(offset)
    zeroes = bytes(CHUNK)
    while size:
        count = min(size, CHUNK)
        stream.write(zeroes[:count])
        size -= count


def compare_prefix(stream, position: int, image: Path) -> bool:
    stream.seek(position)
    with image.open("rb") as source:
        while chunk := source.read(CHUNK):
            if stream.read(len(chunk)) != chunk:
                return False
    return True


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backup-dir", type=Path, required=True)
    parser.add_argument("--release-dir", type=Path, required=True)
    parser.add_argument("--rootfs-raw", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    require(not args.output.exists(), "输出整盘镜像已存在，不会覆盖")
    verify_stock(args.backup_dir)
    primary, backup, parts = build_gpt(args.release_dir / "images" / "gpt_both0.bin")
    images = args.release_dir / "images"
    to_write = {
        "cdt": images / "cdt.bin", "hyp": images / "hyp.mbn",
        "rpm": images / "rpm.mbn", "sbl1": images / "sbl1.mbn",
        "tz": images / "tz.mbn", "aboot": images / "aboot.bin",
        "boot": images / "boot-debian12-6.4-ufix0x.img",
        "rootfs": args.rootfs_raw,
        **{name: args.backup_dir / "partitions" / f"{name}.bin"
           for name in CALIBRATION},
    }
    for name, image in to_write.items():
        require(name in parts and image.is_file(), f"缺少分区或镜像：{name}")
        capacity = (parts[name][1] - parts[name][0] + 1) * SECTOR
        require(0 < image.stat().st_size <= capacity, f"镜像超过分区容量：{name}")
    with (args.backup_dir / "original-full-emmc.bin").open("rb") as source, args.output.open("xb+") as target:
        shutil.copyfileobj(source, target, CHUNK)
        require(target.tell() == DISK_BYTES, "复制原厂 eMMC 长度错误")
        target.seek(0)
        target.write(primary)
        target.seek(DISK_BYTES - len(backup))
        target.write(backup)
        for name, image in to_write.items():
            first, last = parts[name]
            offset = first * SECTOR
            if name in ("boot", "rootfs", *CALIBRATION):
                wipe_range(target, offset, (last - first + 1) * SECTOR)
            target.seek(offset)
            with image.open("rb") as source:
                shutil.copyfileobj(source, target, CHUNK)
        target.flush()
        os.fsync(target.fileno())
    require(args.output.stat().st_size == DISK_BYTES, "整盘镜像大小错误")
    with args.output.open("rb") as built:
        require(built.read(len(primary)) == primary, "主 GPT 回读失败")
        built.seek(DISK_BYTES - len(backup))
        require(built.read(len(backup)) == backup, "备 GPT 回读失败")
        for header, entries, current, other, array_lba in (
            (primary[SECTOR : 2 * SECTOR], primary[2 * SECTOR:], 1, DISK_SECTORS - 1, 2),
            (backup[-SECTOR:], backup[:-SECTOR], DISK_SECTORS - 1, 1, DISK_SECTORS - 33),
        ):
            verify_header(header, entries, current=current, backup=other, array_lba=array_lba)
            require(partition_entries(entries, ENTRY_COUNT) == parts, "主备 GPT 条目不一致")
        for name, image in to_write.items():
            require(compare_prefix(built, parts[name][0] * SECTOR, image), f"镜像回读失败：{name}")
    digest = hashlib.sha256()
    with args.output.open("rb") as stream:
        while chunk := stream.read(CHUNK):
            digest.update(chunk)
    print(f"整盘镜像校验通过：{DISK_BYTES} 字节，SHA-256={digest.hexdigest()}")


if __name__ == "__main__":
    main()
