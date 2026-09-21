#!/bin/sh
# 撤销持久禁用并立即启用 NetworkManager。
set -eu
export LANG=C.UTF-8 LC_ALL=C.UTF-8
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

if [ "$(id -u)" -ne 0 ]; then
    echo '请以 root 运行：sudo ufi103s-nm-enable' >&2
    exit 1
fi

systemctl disable --now ufi103s-local-network.service
systemctl unmask NetworkManager.service
systemctl enable --now NetworkManager.service
echo '独立热点/DHCP 已退出；NetworkManager 已恢复开机启动并已启动。'
