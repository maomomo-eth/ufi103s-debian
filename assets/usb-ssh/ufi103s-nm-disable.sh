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

echo '将持久禁用 NetworkManager 和蜂窝联网；Wi-Fi 热点与 USB DHCP 切换至独立服务，连接可能短暂中断。' >&2
# 先 mask 再 stop，避免通过 SSH 执行时断线造成“已停但未持久禁用”。
systemctl mask NetworkManager.service
systemctl stop NetworkManager.service
if ! systemctl enable --now ufi103s-local-network.service; then
    echo '独立热点/DHCP 启动失败，正在恢复 NetworkManager。' >&2
    systemctl disable --now ufi103s-local-network.service || true
    systemctl unmask NetworkManager.service
    systemctl enable --now NetworkManager.service
    exit 1
fi
echo 'NetworkManager 和蜂窝联网已停用；Wi-Fi 热点、USB DHCP 继续运行。'
