#!/usr/bin/env bash
set -Eeuo pipefail

export LANG=C.UTF-8 LC_ALL=C.UTF-8 PYTHONUTF8=1 PYTHONIOENCODING=utf-8
export PATH="/usr/sbin:/sbin:$PATH"

usage() {
    cat <<'EOF'
用法：tools/rebuild-vocat-rootfs.sh --source 已实测rootfs.img --source-sha256 SHA256 --output 新rootfs.img

从已经实测的 Android sparse rootfs 构建 VoCat 用候选镜像：
保留 NetworkManager、USB/Wi-Fi/SSH，删除旧的 NetworkManager 开关，内置 ModemManager 开关。
输入和输出必须是不同路径；输出父目录须事先创建，已有输出一律拒绝覆盖。
EOF
}

source_image= source_hash= output_image=
while (($#)); do
    case "$1" in
        --source) source_image="${2:-}"; shift 2 ;;
        --source-sha256) source_hash="${2:-}"; shift 2 ;;
        --output) output_image="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "未知参数：$1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ -z "$source_image" || ! "$source_hash" =~ ^[[:xdigit:]]{64}$ || -z "$output_image" ]]; then
    usage >&2
    exit 2
fi
for name in uv debugfs e2fsck sha256sum mktemp rg realpath; do
    command -v "$name" >/dev/null || { echo "缺少命令：$name" >&2; exit 1; }
done
[[ -s "$source_image" ]] || { echo '源 rootfs 不存在或为空。' >&2; exit 1; }
[[ -d "$(dirname -- "$output_image")" && ! -e "$output_image" ]] || {
    echo '输出目录不存在或镜像已存在，拒绝覆盖。' >&2; exit 1;
}
source_image="$(realpath -e -- "$source_image")"
output_parent="$(realpath -e -- "$(dirname -- "$output_image")")"
output_image="$output_parent/$(basename -- "$output_image")"
[[ "$source_image" != "$output_image" ]] || { echo '不允许覆盖输入镜像。' >&2; exit 1; }
actual_hash="$(sha256sum -- "$source_image")"
[[ "${actual_hash%% *}" == "${source_hash,,}" ]] || {
    echo '源镜像 SHA-256 不符，拒绝构建。' >&2; exit 1;
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
asset="$script_dir/../assets/usb-ssh/ufi103s-modemmanager.sh"
wifi_asset="$script_dir/../assets/usb-ssh/ufi103s-wifi.conf"
[[ -s "$asset" ]] || { echo '缺少 ModemManager 管理脚本。' >&2; exit 1; }
[[ -s "$wifi_asset" ]] || { echo '缺少 Wi-Fi 模块开机加载配置。' >&2; exit 1; }
scratch="$(mktemp -d -p "$output_parent" .vocat-rootfs.XXXXXX)"
raw="$scratch/rootfs.raw.img"
candidate="$scratch/rootfs.img"
cleanup() { rm -r -- "$scratch"; }
trap cleanup EXIT

echo '转换经过 SHA-256 核对的实测 rootfs……'
uv run python "$script_dir/android_sparse.py" to-raw "$source_image" "$raw"

check_fs() {
    local status=0
    e2fsck -fy "$raw" || status=$?
    if ((status > 1)); then
        echo "ext4 校验失败：$status" >&2
        exit 1
    fi
}
has_inode() {
    debugfs -R "stat $1" "$raw" 2>/dev/null | rg -q '^Inode:'
}
remove_inode() {
    if has_inode "$1"; then
        debugfs -w -R "rm $1" "$raw" >/dev/null 2>&1
    fi
}

check_fs
has_inode /usr/local/sbin/ufi103s-usb-ssh-init || { echo '源镜像没有 USB/SSH 初始化程序。' >&2; exit 1; }
has_inode /usr/local/sbin/ufi103s-modem-test || { echo '源镜像没有 modem 测试程序。' >&2; exit 1; }
has_inode /etc/NetworkManager/system-connections/WIFI.nmconnection || {
    echo '源镜像没有 Wi-Fi 热点配置。' >&2; exit 1;
}
has_inode /etc/systemd/system/multi-user.target.wants/NetworkManager.service || {
    echo '源镜像没有启用 NetworkManager；拒绝构建。' >&2; exit 1;
}
if has_inode /etc/systemd/system/NetworkManager.service; then
    echo '源镜像可能屏蔽了 NetworkManager；拒绝构建。' >&2
    exit 1
fi
if has_inode /usr/local/sbin/ufi103s-modemmanager; then
    echo '源镜像已有 ModemManager 管理脚本；请用原始实测镜像构建。' >&2
    exit 1
fi

echo '删除旧的 NetworkManager 开关和独立热点接管服务……'
for old in \
    /usr/local/sbin/ufi103s-nm-stop \
    /usr/local/sbin/ufi103s-nm-disable \
    /usr/local/sbin/ufi103s-nm-enable \
    /usr/local/sbin/ufi103s-local-network \
    /etc/systemd/system/ufi103s-local-network.service \
    /etc/systemd/system/multi-user.target.wants/ufi103s-local-network.service; do
    remove_inode "$old"
done

echo '安装 ModemManager 管理命令……'
debugfs -w -R "write $asset /usr/local/sbin/ufi103s-modemmanager" "$raw" >/dev/null 2>&1
debugfs -w -R 'sif /usr/local/sbin/ufi103s-modemmanager mode 0100755' "$raw" >/dev/null 2>&1
if has_inode /etc/modules-load.d/ufi103s-wifi.conf; then
    echo '源镜像已有 Wi-Fi 模块开机加载配置；请使用原始实测镜像构建。' >&2
    exit 1
fi
debugfs -w -R "write $wifi_asset /etc/modules-load.d/ufi103s-wifi.conf" "$raw" >/dev/null 2>&1
debugfs -w -R 'sif /etc/modules-load.d/ufi103s-wifi.conf mode 0100644' "$raw" >/dev/null 2>&1
check_fs

for old in ufi103s-nm-stop ufi103s-nm-disable ufi103s-nm-enable ufi103s-local-network; do
    if has_inode "/usr/local/sbin/$old"; then
        echo "旧程序没有清理干净：$old" >&2; exit 1
    fi
done
has_inode /usr/local/sbin/ufi103s-modemmanager || { echo '新程序安装失败。' >&2; exit 1; }
has_inode /etc/modules-load.d/ufi103s-wifi.conf || { echo 'Wi-Fi 模块开机加载配置安装失败。' >&2; exit 1; }
has_inode /etc/systemd/system/multi-user.target.wants/NetworkManager.service || {
    echo 'NetworkManager 服务未保留。' >&2; exit 1;
}
if debugfs -R 'ls -p /etc/ssh' "$raw" 2>/dev/null | rg -q 'ssh_host_.*_key'; then
    echo '镜像中发现预生成的 SSH 主机密钥，拒绝输出。' >&2; exit 1
fi
if ! debugfs -R 'stat /etc/machine-id' "$raw" 2>/dev/null | rg -q 'Size: 0\b'; then
    echo 'machine-id 非空，拒绝输出。' >&2; exit 1
fi

echo '生成独立的新 sparse rootfs……'
uv run python "$script_dir/android_sparse.py" to-sparse "$raw" "$candidate"
[[ ! -e "$output_image" ]] || { echo '构建过程中目标文件被占用，拒绝覆盖。' >&2; exit 1; }
mv -n -- "$candidate" "$output_image"
sha256sum -- "$output_image"
echo "构建完成：$output_image"
