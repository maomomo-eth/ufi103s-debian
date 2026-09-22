#!/usr/bin/env bash
set -Eeuo pipefail

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

usage() {
    cat <<'EOF'
用法：
  ./tools/build-debian12-rootfs.sh \
    --source /路径/原始-rootfs.img \
    --firmware-dir /路径/已验证-mpss \
    --output /路径/rootfs-debian12-ufi103s-fixed.img

输入 rootfs 必须是 Android sparse ext4。脚本会补入 UFI103S MPSS firmware，
安装仓库中的 SIM 修复脚本、清除预生成身份并输出新的 sparse image。
需要 root 或 sudo 挂载 loop，并需要 zerofree 清理已释放块。

环境变量：
  ZEROFREE=/绝对路径/zerofree
EOF
}

source_image=""
firmware_dir=""
output_image=""

while (($#)); do
    case "$1" in
        --source)
            source_image="${2:-}"
            shift 2
            ;;
        --firmware-dir)
            firmware_dir="${2:-}"
            shift 2
            ;;
        --output)
            output_image="${2:-}"
            shift 2
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

if [[ -z "$source_image" || -z "$firmware_dir" || -z "$output_image" ]]; then
    usage >&2
    exit 2
fi

for command_name in mount umount mountpoint install find truncate uv; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "缺少命令：$command_name" >&2
        exit 1
    fi
done

e2fsck_bin="$(command -v e2fsck 2>/dev/null || true)"
if [[ -z "$e2fsck_bin" && -x /usr/sbin/e2fsck ]]; then
    e2fsck_bin=/usr/sbin/e2fsck
fi
if [[ -z "$e2fsck_bin" ]]; then
    echo "缺少命令：e2fsck" >&2
    exit 1
fi

tune2fs_bin="$(command -v tune2fs 2>/dev/null || true)"
if [[ -z "$tune2fs_bin" && -x /usr/sbin/tune2fs ]]; then
    tune2fs_bin=/usr/sbin/tune2fs
fi
if [[ -z "$tune2fs_bin" ]]; then
    echo "缺少命令：tune2fs" >&2
    exit 1
fi

zerofree_bin="${ZEROFREE:-$(command -v zerofree 2>/dev/null || true)}"
if [[ -z "$zerofree_bin" && -x /usr/sbin/zerofree ]]; then
    zerofree_bin=/usr/sbin/zerofree
fi
if [[ -z "$zerofree_bin" || ! -x "$zerofree_bin" ]]; then
    echo "缺少 zerofree；可安装 zerofree 包，或通过 ZEROFREE 指定绝对路径。" >&2
    exit 1
fi

if [[ ! -s "$source_image" ]]; then
    echo "原始 rootfs 不存在或为空：$source_image" >&2
    exit 1
fi
if [[ ! -d "$firmware_dir" ]]; then
    echo "firmware 目录不存在：$firmware_dir" >&2
    exit 1
fi
if [[ -e "$output_image" ]]; then
    echo "输出文件已存在，为避免覆盖而退出：$output_image" >&2
    exit 1
fi
if [[ ! -d "$(dirname -- "$output_image")" ]]; then
    echo "输出目录不存在：$(dirname -- "$output_image")" >&2
    exit 1
fi

firmware_files=(
    mba.mbn modem.mdt
    modem.b00 modem.b01 modem.b02 modem.b03 modem.b04 modem.b05 modem.b08
    modem.b10 modem.b11 modem.b13 modem.b14 modem.b15 modem.b16 modem.b17
    modem.b18 modem.b19 modem.b22 modem.b23 modem.b24 modem.b25
)
for name in "${firmware_files[@]}"; do
    if [[ ! -s "$firmware_dir/$name" ]]; then
        echo "缺少 MPSS 文件：$firmware_dir/$name" >&2
        exit 1
    fi
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
sim_script="$script_dir/openstick-sim-changer.sh"
sparse_tool="$script_dir/android_sparse.py"
usb_ssh_assets="$script_dir/../assets/usb-ssh"
if [[ ! -s "$sim_script" ]]; then
    echo "缺少 SIM 修复脚本：$sim_script" >&2
    exit 1
fi
if [[ ! -s "$sparse_tool" ]]; then
    echo "缺少 sparse 转换工具：$sparse_tool" >&2
    exit 1
fi
for name in usb.nmconnection 20-ufi103s-usb.conf ufi103s-wifi.conf ufi103s-usb-ssh-init.service \
    10-ufi103s-init.conf ufi103s-usb-ssh-init.sh ufi103s-modem-test.sh \
    ufi103s-modemmanager.sh; do
    if [[ ! -s "$usb_ssh_assets/$name" ]]; then
        echo "缺少 USB/SSH 初始化资产：$usb_ssh_assets/$name" >&2
        exit 1
    fi
done

privilege=()
if ((EUID != 0)); then
    if ! command -v sudo >/dev/null 2>&1; then
        echo "挂载 rootfs 需要 root 或 sudo。" >&2
        exit 1
    fi
    privilege=(sudo)
fi

work_dir="$(mktemp -d --tmpdir ufi103s-debian12.XXXXXX)"
mount_dir="$work_dir/mnt"
raw_image="$work_dir/rootfs.raw.img"
output_tmp="$output_image.tmp.$$"
mkdir -- "$mount_dir"

cleanup() {
    if mountpoint -q "$mount_dir"; then
        "${privilege[@]}" umount -- "$mount_dir" || true
    fi
    rm -f -- "$output_tmp"
    rm -r -- "$work_dir"
}
trap cleanup EXIT

echo "转换 sparse rootfs……"
uv run python "$sparse_tool" to-raw "$source_image" "$raw_image"

echo "修复 ext4 journal……"
set +e
"${privilege[@]}" "$e2fsck_bin" -fy "$raw_image"
fsck_status=$?
set -e
if ((fsck_status > 1)); then
    echo "e2fsck 无法修复原始 rootfs，退出码：$fsck_status" >&2
    exit 1
fi

echo "安装 MPSS firmware 与 SIM 修复……"
"${privilege[@]}" mount -o loop,rw -- "$raw_image" "$mount_dir"
if [[ -L "$mount_dir/etc/systemd/system/NetworkManager.service" ]]; then
    echo '源镜像屏蔽了 NetworkManager，拒绝构建。' >&2
    exit 1
fi
# 重用旧镜像作为输入时，也不让曾经的 NM 开关或热点接管服务进入新镜像。
for obsolete in \
    /usr/local/sbin/ufi103s-nm-stop \
    /usr/local/sbin/ufi103s-nm-disable \
    /usr/local/sbin/ufi103s-nm-enable \
    /usr/local/sbin/ufi103s-local-network \
    /etc/systemd/system/ufi103s-local-network.service \
    /etc/systemd/system/multi-user.target.wants/ufi103s-local-network.service; do
    "${privilege[@]}" rm -f -- "$mount_dir$obsolete"
done
for name in "${firmware_files[@]}"; do
    "${privilege[@]}" install -m 0644 -- "$firmware_dir/$name" "$mount_dir/lib/firmware/$name"
done
"${privilege[@]}" install -m 0755 -- "$sim_script" "$mount_dir/usr/sbin/openstick-sim-changer.sh"

echo "启用 USB 网络与首启 SSH 主机密钥生成……"
"${privilege[@]}" install -D -m 0600 -- "$usb_ssh_assets/usb.nmconnection" \
    "$mount_dir/etc/NetworkManager/system-connections/usb.nmconnection"
"${privilege[@]}" install -D -m 0755 -- "$usb_ssh_assets/ufi103s-usb-ssh-init.sh" \
    "$mount_dir/usr/local/sbin/ufi103s-usb-ssh-init"
"${privilege[@]}" install -D -m 0755 -- "$usb_ssh_assets/ufi103s-modem-test.sh" \
    "$mount_dir/usr/local/sbin/ufi103s-modem-test"
"${privilege[@]}" install -D -m 0755 -- "$usb_ssh_assets/ufi103s-modemmanager.sh" \
    "$mount_dir/usr/local/sbin/ufi103s-modemmanager"
"${privilege[@]}" install -D -m 0644 -- "$usb_ssh_assets/ufi103s-wifi.conf" \
    "$mount_dir/etc/modules-load.d/ufi103s-wifi.conf"
"${privilege[@]}" install -D -m 0644 -- "$usb_ssh_assets/ufi103s-usb-ssh-init.service" \
    "$mount_dir/etc/systemd/system/ufi103s-usb-ssh-init.service"
"${privilege[@]}" install -D -m 0644 -- "$usb_ssh_assets/10-ufi103s-init.conf" \
    "$mount_dir/etc/systemd/system/ssh.service.d/10-ufi103s-init.conf"
"${privilege[@]}" install -D -m 0644 -- "$usb_ssh_assets/20-ufi103s-usb.conf" \
    "$mount_dir/etc/ssh/sshd_config.d/20-ufi103s-usb.conf"
if ! "${privilege[@]}" grep -Fqx 'Include /etc/ssh/sshd_config.d/*.conf' \
    "$mount_dir/etc/ssh/sshd_config"; then
    echo "源镜像 sshd_config 未加载配置目录，拒绝构建。" >&2
    exit 1
fi
"${privilege[@]}" install -d -m 0755 -- "$mount_dir/etc/systemd/system/multi-user.target.wants"
"${privilege[@]}" ln -s -- /etc/systemd/system/ufi103s-usb-ssh-init.service \
    "$mount_dir/etc/systemd/system/multi-user.target.wants/ufi103s-usb-ssh-init.service"
"${privilege[@]}" ln -s -- /lib/systemd/system/ssh.service \
    "$mount_dir/etc/systemd/system/multi-user.target.wants/ssh.service"
# 原镜像启用了 ssh.socket（双栈监听）；不能让它绕过仅 IPv4 的接口限制。
"${privilege[@]}" rm -f -- "$mount_dir/etc/systemd/system/sockets.target.wants/ssh.socket"
"${privilege[@]}" ln -s -- /dev/null "$mount_dir/etc/systemd/system/ssh.socket"
for obsolete in mobian-setup-usb-network.service mobian-ssh-keygen.service mobian-usb-gadget.service; do
    old_link="$mount_dir/etc/systemd/system/multi-user.target.wants/$obsolete"
    if [[ -L "$old_link" && ! -e "$old_link" ]]; then
        "${privilege[@]}" rm -- "$old_link"
    fi
done

echo "清理基础镜像中的预生成身份和历史记录……"
"${privilege[@]}" rm -f -- "$mount_dir"/etc/ssh/ssh_host_*_key "$mount_dir"/etc/ssh/ssh_host_*_key.pub
"${privilege[@]}" rm -f -- "$mount_dir/root/.bash_history" "$mount_dir/var/lib/dbus/machine-id" "$mount_dir/var/lib/systemd/random-seed"
"${privilege[@]}" find "$mount_dir/home" -mindepth 2 -maxdepth 2 -name .bash_history -type f -delete
"${privilege[@]}" find "$mount_dir/var/log" -type f -exec truncate -s 0 -- {} +
"${privilege[@]}" find "$mount_dir/etc/NetworkManager/system-connections" -maxdepth 1 -type f \
    ! -name WIFI.nmconnection ! -name modem.nmconnection ! -name usb.nmconnection -delete
"${privilege[@]}" truncate -s 0 -- "$mount_dir/etc/machine-id"
"${privilege[@]}" chmod 0444 -- "$mount_dir/etc/machine-id"

if ! "${privilege[@]}" grep -Fqx 'ssid=4G-WIFI' "$mount_dir/etc/NetworkManager/system-connections/WIFI.nmconnection" \
    || ! "${privilege[@]}" grep -Fqx 'psk=12345678' "$mount_dir/etc/NetworkManager/system-connections/WIFI.nmconnection"; then
    echo "默认热点配置与预期不符，拒绝生成发布镜像。" >&2
    exit 1
fi
sync
"${privilege[@]}" umount -- "$mount_dir"

echo "复核 ext4……"
set +e
"${privilege[@]}" "$e2fsck_bin" -fy "$raw_image"
fsck_status=$?
set -e
if ((fsck_status > 1)); then
    echo "e2fsck 复核失败，退出码：$fsck_status" >&2
    exit 1
fi

echo "清零 ext4 已释放块，避免删除内容残留在发布镜像中……"
"${privilege[@]}" "$tune2fs_bin" -O ^has_journal "$raw_image"
"${privilege[@]}" "$e2fsck_bin" -fy "$raw_image"
"${privilege[@]}" "$tune2fs_bin" -j "$raw_image"
"${privilege[@]}" "$e2fsck_bin" -fy "$raw_image"
"${privilege[@]}" "$zerofree_bin" "$raw_image"

echo "生成 sparse rootfs……"
uv run python "$sparse_tool" to-sparse "$raw_image" "$output_tmp"
mv -- "$output_tmp" "$output_image"
sha256sum "$output_image"
echo "构建完成：$output_image"
