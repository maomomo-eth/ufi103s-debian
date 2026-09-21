#!/usr/bin/env bash
# 在发布版 sparse rootfs 的副本中安装 USB/Wi-Fi 密码 SSH 与诊断脚本。
set -Eeuo pipefail
export LANG=C.UTF-8 LC_ALL=C.UTF-8 PYTHONUTF8=1 PYTHONIOENCODING=utf-8
PATH="/usr/sbin:/sbin:$PATH"
export PATH

usage() {
    echo '用法：enable-usb-wifi-ssh-rootfs.sh --source 原版-rootfs.img --output 仓库外/新rootfs.img'
}

source_image=""
output_image=""
while (($#)); do
    case "$1" in
        --source) source_image="${2:-}"; shift 2 ;;
        --output) output_image="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
if [[ ! -s "$source_image" || -z "$output_image" || -e "$output_image" || ! -d "$(dirname -- "$output_image")" ]]; then
    echo '输入必须存在，输出文件不得存在，输出目录须事先创建。' >&2
    usage >&2
    exit 2
fi

# 只接受仓库 v2.0.0 已清理过的发布原版，避免把设备回读、私有 Wi-Fi 配置打进新镜像。
expected_source_sha256=e4f56e1b4ccb93f4847788c3429a898fa343130281337634251a45fd9c5462ef
source_sha256="$(sha256sum -- "$source_image")"
source_sha256="${source_sha256%% *}"
if [[ "$source_sha256" != "$expected_source_sha256" ]]; then
    echo '源镜像 SHA-256 与干净的 v2.0.0 发布版不一致，拒绝构建。' >&2
    exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
assets="$script_dir/../assets/usb-ssh"
for name in usb.nmconnection 20-ufi103s-usb.conf ufi103s-usb-ssh-init.service \
    10-ufi103s-init.conf ufi103s-usb-ssh-init.sh ufi103s-modem-test.sh \
    ufi103s-nm-stop.sh ufi103s-nm-disable.sh ufi103s-nm-enable.sh; do
    [[ -s "$assets/$name" ]] || { echo "缺少构建资源：$assets/$name" >&2; exit 1; }
done
for name in uv debugfs e2fsck sha256sum rg; do
    command -v "$name" >/dev/null 2>&1 || { echo "缺少命令：$name" >&2; exit 1; }
done

work_dir="$(mktemp -d --tmpdir ufi103s-usb-ssh.XXXXXX)"
raw="$work_dir/rootfs.raw.img"
output_tmp="$output_image.tmp.$$"
cleanup() {
    # 仅删除脚本自己创建的临时文件，绝不操作源镜像或已存在的输出。
    if [[ -e "$output_tmp" ]]; then rm -- "$output_tmp"; fi
    if [[ -d "$work_dir" ]]; then rm -r -- "$work_dir"; fi
}
trap cleanup EXIT

echo '转换原始 sparse 镜像到私有临时副本……'
uv run python "$script_dir/android_sparse.py" to-raw "$source_image" "$raw"
if ! debugfs -R 'cat /etc/passwd' "$raw" 2>/dev/null | rg -q '^user:' \
    || ! debugfs -R 'cat /etc/ssh/sshd_config' "$raw" 2>/dev/null | rg -q '^Include /etc/ssh/sshd_config.d/\*\.conf' \
    || ! debugfs -R 'cat /etc/NetworkManager/system-connections/WIFI.nmconnection' "$raw" 2>/dev/null | rg -q '^ssid=4G-WIFI$'; then
    echo '源镜像不是预期的 UFI103S Debian 12 基础系统，拒绝修改。' >&2
    exit 1
fi

debug() {
    debugfs -w -R "$1" "$raw" >/dev/null 2>&1
}
exists() {
    debugfs -R "stat $1" "$raw" 2>/dev/null | rg -q '^Inode:'
}
ensure_dir() {
    if ! exists "$1"; then debug "mkdir $1"; fi
    exists "$1" || { echo "无法创建镜像目录：$1" >&2; exit 1; }
}
write_asset() {
    local source="$1" destination="$2" mode="$3"
    if exists "$destination"; then debug "rm $destination"; fi
    debug "write $source $destination"
    debug "sif $destination mode $mode"
    exists "$destination" || { echo "无法写入镜像文件：$destination" >&2; exit 1; }
}
enable_link() {
    local destination="$1" target="$2"
    if exists "$destination"; then
        echo "目标 service 链接已存在，不覆盖：$destination" >&2
        exit 1
    fi
    debug "symlink $destination $target"
    exists "$destination" || { echo "无法启用 service：$destination" >&2; exit 1; }
}

echo '向 rootfs 副本写入网络、SSH、modem 测试和 NetworkManager 管理脚本……'
ensure_dir /etc/systemd/system/ssh.service.d
ensure_dir /usr/local/sbin
write_asset "$assets/usb.nmconnection" /etc/NetworkManager/system-connections/usb.nmconnection 0100600
write_asset "$assets/20-ufi103s-usb.conf" /etc/ssh/sshd_config.d/20-ufi103s-usb.conf 0100644
write_asset "$assets/ufi103s-usb-ssh-init.service" /etc/systemd/system/ufi103s-usb-ssh-init.service 0100644
write_asset "$assets/10-ufi103s-init.conf" /etc/systemd/system/ssh.service.d/10-ufi103s-init.conf 0100644
write_asset "$assets/ufi103s-usb-ssh-init.sh" /usr/local/sbin/ufi103s-usb-ssh-init 0100755
write_asset "$assets/ufi103s-modem-test.sh" /usr/local/sbin/ufi103s-modem-test 0100755
write_asset "$assets/ufi103s-nm-stop.sh" /usr/local/sbin/ufi103s-nm-stop 0100755
write_asset "$assets/ufi103s-nm-disable.sh" /usr/local/sbin/ufi103s-nm-disable 0100755
write_asset "$assets/ufi103s-nm-enable.sh" /usr/local/sbin/ufi103s-nm-enable 0100755
ensure_dir /etc/systemd/system/multi-user.target.wants
enable_link /etc/systemd/system/multi-user.target.wants/ufi103s-usb-ssh-init.service /etc/systemd/system/ufi103s-usb-ssh-init.service
enable_link /etc/systemd/system/multi-user.target.wants/ssh.service /lib/systemd/system/ssh.service

# 这三个预置链接指向不存在的 Mobian 服务；只在私有镜像副本内移除。
for obsolete in mobian-setup-usb-network.service mobian-ssh-keygen.service mobian-usb-gadget.service; do
    path="/etc/systemd/system/multi-user.target.wants/$obsolete"
    if exists "$path"; then debug "rm $path"; fi
done

echo '检查 ext4 一致性……'
set +e
e2fsck -fy "$raw" >/dev/null
fsck_status=$?
set -e
if ((fsck_status > 1)); then
    echo "镜像 ext4 检查失败，退出码 $fsck_status。" >&2
    exit 1
fi
if ! debugfs -R 'cat /etc/ssh/sshd_config.d/20-ufi103s-usb.conf' "$raw" 2>/dev/null | rg -q '^PasswordAuthentication yes$' \
    || ! exists /usr/local/sbin/ufi103s-modem-test \
    || ! exists /usr/local/sbin/ufi103s-nm-stop \
    || ! exists /usr/local/sbin/ufi103s-nm-disable \
    || ! exists /usr/local/sbin/ufi103s-nm-enable; then
    echo '镜像内安装内容复核失败。' >&2
    exit 1
fi
echo '生成新 sparse 镜像……'
uv run python "$script_dir/android_sparse.py" to-sparse "$raw" "$output_tmp"
mv -- "$output_tmp" "$output_image"
sha256sum "$output_image"
echo "本地改版生成完成（尚未实机验证）：$output_image"
