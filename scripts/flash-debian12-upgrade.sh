#!/usr/bin/env bash
set -Eeuo pipefail

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

usage() {
    cat <<'EOF'
用法：
  ./scripts/flash-debian12-upgrade.sh [--yes]

仅适用于已经正常运行兼容版 Debian 11、GPT 与 lk2nd 未改动的 UFI103S_V03。
脚本只写入 rootfs 和 boot，不触碰 GPT、启动链或校准分区。

环境变量：
  FASTBOOT=/绝对路径/fastboot
EOF
}

assume_yes=0
while (($#)); do
    case "$1" in
        --yes)
            assume_yes=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "未知参数：$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

fastboot_bin="${FASTBOOT:-fastboot}"
if ! command -v "$fastboot_bin" >/dev/null 2>&1 && [[ ! -x "$fastboot_bin" ]]; then
    echo "找不到 fastboot：$fastboot_bin" >&2
    exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
release_root="$(cd -- "$script_dir/.." && pwd)"
image_dir="$release_root/images"
boot_image="$image_dir/boot-debian12-6.4-ufix0x.img"
rootfs_image="$image_dir/rootfs-debian12-ufi103s-fixed.img"

for image in "$boot_image" "$rootfs_image"; do
    if [[ ! -s "$image" ]]; then
        echo "缺少镜像：$image" >&2
        exit 1
    fi
done

if [[ -f "$release_root/SHA256SUMS" ]]; then
    echo "校验 Release 文件……"
    (cd -- "$release_root" && sha256sum -c SHA256SUMS)
fi

mapfile -t device_lines < <("$fastboot_bin" devices | awk 'NF >= 2 {print}')
if ((${#device_lines[@]} != 1)); then
    echo "必须且只能连接一个 fastboot 设备，当前数量：${#device_lines[@]}" >&2
    exit 1
fi

product_output="$("$fastboot_bin" getvar product 2>&1 || true)"
echo "$product_output"
if [[ "$product_output" != *"LK1ST_MSM8916"* ]]; then
    echo "设备未报告 LK1ST_MSM8916，拒绝执行升级。" >&2
    exit 1
fi

echo "目标设备：${device_lines[0]}"
"$fastboot_bin" getvar partition-size:boot 2>&1 || true
"$fastboot_bin" getvar partition-size:rootfs 2>&1 || true

cat <<'EOF'

警告：下一步会清除现有 boot 和 rootfs。
仅适用于 PCB 丝印 UFI103S_V03、已经运行兼容版 Debian 11 的设备。
必须已经保存完整 eMMC 和本机校准分区备份。
EOF

if ((assume_yes == 0)); then
    read -r -p '请输入 UFI103S-DEBIAN12 继续：' confirmation
    if [[ "$confirmation" != "UFI103S-DEBIAN12" ]]; then
        echo "已取消。"
        exit 1
    fi
fi

echo "写入 Debian 12 rootfs……"
"$fastboot_bin" erase rootfs
"$fastboot_bin" -S 200m flash rootfs "$rootfs_image"

# boot 最后写入，避免 rootfs 未完成时切换到新内核。
echo "写入 Debian 12 boot……"
"$fastboot_bin" erase boot
"$fastboot_bin" flash boot "$boot_image"

cat <<'EOF'

升级写入完成，GPT、启动链和校准分区未修改。
请物理断电再上电，不要依赖 fastboot reboot。
首次启动可能需要 60–120 秒。
EOF
