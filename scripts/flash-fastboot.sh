#!/usr/bin/env bash
set -Eeuo pipefail

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

usage() {
    cat <<'EOF'
用法：
  ./scripts/flash-fastboot.sh --calibration-dir /绝对路径/校准备份 [--yes]

环境变量：
  FASTBOOT=/绝对路径/fastboot
EOF
}

calibration_dir=""
assume_yes=0
while (($#)); do
    case "$1" in
        --calibration-dir)
            calibration_dir="${2:-}"
            shift 2
            ;;
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

if [[ -z "$calibration_dir" ]]; then
    echo "必须通过 --calibration-dir 指定目标设备自己的校准备份。" >&2
    exit 2
fi

fastboot_bin="${FASTBOOT:-fastboot}"
if ! command -v "$fastboot_bin" >/dev/null 2>&1 && [[ ! -x "$fastboot_bin" ]]; then
    echo "找不到 fastboot：$fastboot_bin" >&2
    exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
release_root="$(cd -- "$script_dir/.." && pwd)"
image_dir="$release_root/images"

required_images=(
    gpt_both0.bin
    cdt.bin
    hyp.mbn
    rpm.mbn
    sbl1.mbn
    tz.mbn
    aboot.bin
    boot-1.2-modem-fixed.img
    rootfs.img
)
calibration_images=(fsc.bin fsg.bin modemst1.bin modemst2.bin)

for name in "${required_images[@]}"; do
    if [[ ! -s "$image_dir/$name" ]]; then
        echo "缺少镜像：$image_dir/$name" >&2
        exit 1
    fi
done

for name in "${calibration_images[@]}"; do
    if [[ ! -s "$calibration_dir/$name" ]]; then
        echo "缺少本机校准文件：$calibration_dir/$name" >&2
        exit 1
    fi
done

if [[ -f "$release_root/SHA256SUMS" ]]; then
    echo "校验 Release 镜像……"
    (cd -- "$release_root" && sha256sum -c SHA256SUMS)
fi

mapfile -t device_lines < <("$fastboot_bin" devices | awk 'NF >= 2 {print}')
if ((${#device_lines[@]} != 1)); then
    echo "必须且只能连接一个 fastboot 设备，当前数量：${#device_lines[@]}" >&2
    exit 1
fi

echo "目标设备：${device_lines[0]}"
"$fastboot_bin" getvar product 2>&1 || true
"$fastboot_bin" getvar secure 2>&1 || true

cat <<EOF

警告：下一步会重建目标设备 GPT，并清除现有系统。
校准数据来源：$calibration_dir
仅可用于 PCB 丝印为 UFI103S_V03 的设备。
EOF

if ((assume_yes == 0)); then
    read -r -p '请输入 UFI103S 继续：' confirmation
    if [[ "$confirmation" != "UFI103S" ]]; then
        echo "已取消。"
        exit 1
    fi
fi

echo "写入 GPT……"
"$fastboot_bin" flash partition "$image_dir/gpt_both0.bin"
"$fastboot_bin" getvar partition-size:rootfs 2>&1

echo "写入启动链……"
"$fastboot_bin" flash cdt "$image_dir/cdt.bin"
"$fastboot_bin" flash hyp "$image_dir/hyp.mbn"
"$fastboot_bin" flash rpm "$image_dir/rpm.mbn"
"$fastboot_bin" flash sbl1 "$image_dir/sbl1.mbn"
"$fastboot_bin" flash tz "$image_dir/tz.mbn"

echo "恢复本机校准分区……"
for name in "${calibration_images[@]}"; do
    partition="${name%.bin}"
    "$fastboot_bin" flash "$partition" "$calibration_dir/$name"
done

echo "写入 Debian boot 与 rootfs……"
"$fastboot_bin" erase boot
"$fastboot_bin" erase rootfs
"$fastboot_bin" flash boot "$image_dir/boot-1.2-modem-fixed.img"
"$fastboot_bin" -S 200m flash rootfs "$image_dir/rootfs.img"

# 最后写 aboot，避免传输 rootfs 期间断电后误进入不完整系统。
"$fastboot_bin" flash aboot "$image_dir/aboot.bin"

cat <<'EOF'

刷写完成。
请物理断电再上电，不要依赖 fastboot reboot。
启动后热点为 4G-WIFI，默认密码 12345678；Debian 用户 user，默认密码 1。
EOF

