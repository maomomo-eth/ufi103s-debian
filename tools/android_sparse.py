#!/usr/bin/env python3
"""在 Android sparse image 与 raw image 之间转换。"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


SPARSE_MAGIC = 0xED26FF3A
CHUNK_RAW = 0xCAC1
CHUNK_FILL = 0xCAC2
CHUNK_DONT_CARE = 0xCAC3
CHUNK_CRC32 = 0xCAC4
FILE_HEADER = struct.Struct("<I4H4I")
CHUNK_HEADER = struct.Struct("<2H2I")


def read_exact(stream, size: int) -> bytes:
    data = stream.read(size)
    if len(data) != size:
        raise ValueError(f"镜像意外结束，需要 {size} 字节，实际 {len(data)} 字节")
    return data


def sparse_to_raw(source: Path, output: Path) -> None:
    if output.exists():
        raise FileExistsError(f"输出文件已存在：{output}")

    with source.open("rb") as src, output.open("xb") as dst:
        header_data = read_exact(src, FILE_HEADER.size)
        (
            magic,
            major,
            _minor,
            file_header_size,
            chunk_header_size,
            block_size,
            total_blocks,
            total_chunks,
            _checksum,
        ) = FILE_HEADER.unpack(header_data)
        if magic != SPARSE_MAGIC or major != 1:
            raise ValueError("输入不是受支持的 Android sparse image")
        if file_header_size < FILE_HEADER.size or chunk_header_size < CHUNK_HEADER.size:
            raise ValueError("sparse header 大小无效")
        src.seek(file_header_size - FILE_HEADER.size, 1)

        written_blocks = 0
        for _ in range(total_chunks):
            chunk_data = read_exact(src, CHUNK_HEADER.size)
            chunk_type, _reserved, chunk_blocks, total_size = CHUNK_HEADER.unpack(chunk_data)
            if total_size < chunk_header_size:
                raise ValueError("chunk 大小无效")
            src.seek(chunk_header_size - CHUNK_HEADER.size, 1)
            payload_size = total_size - chunk_header_size
            output_size = chunk_blocks * block_size

            if chunk_type == CHUNK_RAW:
                if payload_size != output_size:
                    raise ValueError("RAW chunk 长度不匹配")
                remaining = payload_size
                while remaining:
                    data = read_exact(src, min(4 * 1024 * 1024, remaining))
                    dst.write(data)
                    remaining -= len(data)
            elif chunk_type == CHUNK_FILL:
                if payload_size != 4 or block_size % 4:
                    raise ValueError("FILL chunk 无效")
                word = read_exact(src, 4)
                fill_block = word * (block_size // 4)
                for _ in range(chunk_blocks):
                    dst.write(fill_block)
            elif chunk_type == CHUNK_DONT_CARE:
                if payload_size:
                    raise ValueError("DONT_CARE chunk 带有意外数据")
                dst.seek(output_size, 1)
            elif chunk_type == CHUNK_CRC32:
                if payload_size != 4:
                    raise ValueError("CRC32 chunk 无效")
                read_exact(src, 4)
            else:
                raise ValueError(f"未知 sparse chunk 类型：0x{chunk_type:04x}")

            written_blocks += chunk_blocks

        if written_blocks != total_blocks:
            raise ValueError(
                f"输出 block 数量不匹配：预期 {total_blocks}，实际 {written_blocks}"
            )
        dst.truncate(total_blocks * block_size)


def raw_to_sparse(source: Path, output: Path, block_size: int = 4096) -> None:
    if output.exists():
        raise FileExistsError(f"输出文件已存在：{output}")
    source_size = source.stat().st_size
    if source_size == 0 or source_size % block_size:
        raise ValueError(f"raw image 大小必须是 {block_size} 的正整数倍")

    total_blocks = source_size // block_size
    max_raw_blocks = 4096
    zero_block = bytes(block_size)

    with source.open("rb") as src, output.open("xb+") as dst:
        dst.write(
            FILE_HEADER.pack(
                SPARSE_MAGIC,
                1,
                0,
                FILE_HEADER.size,
                CHUNK_HEADER.size,
                block_size,
                total_blocks,
                0,
                0,
            )
        )

        total_chunks = 0
        current_type: int | None = None
        current_blocks = 0
        raw_data = bytearray()

        def flush_chunk() -> None:
            nonlocal total_chunks, current_type, current_blocks, raw_data
            if current_type is None or current_blocks == 0:
                return
            if current_type == CHUNK_RAW:
                dst.write(
                    CHUNK_HEADER.pack(
                        CHUNK_RAW,
                        0,
                        current_blocks,
                        CHUNK_HEADER.size + len(raw_data),
                    )
                )
                dst.write(raw_data)
            else:
                dst.write(
                    CHUNK_HEADER.pack(
                        CHUNK_DONT_CARE,
                        0,
                        current_blocks,
                        CHUNK_HEADER.size,
                    )
                )
            total_chunks += 1
            current_type = None
            current_blocks = 0
            raw_data = bytearray()

        for _ in range(total_blocks):
            block = read_exact(src, block_size)
            block_type = CHUNK_DONT_CARE if block == zero_block else CHUNK_RAW
            if current_type is not None and (
                block_type != current_type
                or (current_type == CHUNK_RAW and current_blocks >= max_raw_blocks)
            ):
                flush_chunk()
            if current_type is None:
                current_type = block_type
            current_blocks += 1
            if block_type == CHUNK_RAW:
                raw_data.extend(block)

        flush_chunk()
        dst.seek(0)
        dst.write(
            FILE_HEADER.pack(
                SPARSE_MAGIC,
                1,
                0,
                FILE_HEADER.size,
                CHUNK_HEADER.size,
                block_size,
                total_blocks,
                total_chunks,
                0,
            )
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    to_raw = subparsers.add_parser("to-raw", help="将 sparse image 转为 raw image")
    to_raw.add_argument("source", type=Path)
    to_raw.add_argument("output", type=Path)

    to_sparse = subparsers.add_parser("to-sparse", help="将 raw image 转为 sparse image")
    to_sparse.add_argument("source", type=Path)
    to_sparse.add_argument("output", type=Path)
    to_sparse.add_argument("--block-size", type=int, default=4096)

    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.command == "to-raw":
        sparse_to_raw(args.source, args.output)
    else:
        raw_to_sparse(args.source, args.output, args.block_size)


if __name__ == "__main__":
    main()
