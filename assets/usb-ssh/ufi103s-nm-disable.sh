#!/bin/sh
# 持久禁用 NetworkManager，阻止 D-Bus/其他服务重新拉起。
set -eu
export LANG=C.UTF-8 LC_ALL=C.UTF-8
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

if [ "$(id -u)" -ne 0 ]; then
    echo '请以 root 运行：sudo ufi103s-nm-disable' >&2
    exit 1
fi

echo '将持久禁用 NetworkManager：Wi-Fi 热点、USB DHCP、蜂窝联网及当前 SSH 可能立即断开。请先确认 ADB 或串口可用于恢复。' >&2
# 先 mask 再 stop，避免通过 SSH 执行时断线造成“已停但未持久禁用”。
systemctl mask NetworkManager.service
systemctl stop NetworkManager.service
echo 'NetworkManager 已持久禁用；通过 ADB/串口执行 ufi103s-nm-enable 可恢复。'
