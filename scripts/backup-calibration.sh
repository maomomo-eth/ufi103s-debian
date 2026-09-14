#!/usr/bin/env bash
set -Eeuo pipefail

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

if (($# != 1)); then
    echo "用法：$0 /绝对路径/新备份目录" >&2
    exit 2
fi

target_dir="$1"
fastboot_bin="${FASTBOOT:-fastboot}"

if ! command -v "$fastboot_bin" >/dev/null 2>&1 && [[ ! -x "$fastboot_bin" ]]; then
    echo "找不到 fastboot：$fastboot_bin" >&2
    exit 1
fi

if [[ -e "$target_dir" ]]; then
    echo "目标已存在，为避免覆盖而退出：$target_dir" >&2
    exit 1
fi

mapfile -t device_lines < <("$fastboot_bin" devices | awk 'NF >= 2 {print}')
if ((${#device_lines[@]} != 1)); then
    echo "必须且只能连接一个 fastboot 设备。" >&2
    exit 1
fi

mkdir -m 700 -- "$target_dir"

dump_partition() {
    local partition="$1"
    local output="$target_dir/$partition.bin"

    echo "备份 $partition……"
    if ! "$fastboot_bin" oem dump "$partition"; then
        "$fastboot_bin" oem read-partition "$partition"
    fi
    "$fastboot_bin" get_staged "$output"
    if [[ ! -s "$output" ]]; then
        echo "$partition 备份为空。" >&2
        exit 1
    fi
    chmod 600 -- "$output"
}

for partition in fsc fsg modemst1 modemst2; do
    dump_partition "$partition"
done

(cd -- "$target_dir" && sha256sum fsc.bin fsg.bin modemst1.bin modemst2.bin > SHA256SUMS)
chmod 600 -- "$target_dir/SHA256SUMS"
(cd -- "$target_dir" && sha256sum -c SHA256SUMS)

echo "校准分区已保存到：$target_dir"
echo "请勿公开或与其他设备混用。"

