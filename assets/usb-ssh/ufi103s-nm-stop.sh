#!/bin/sh
# 临时停止网络管理；不 disable 服务，重启后仍可自动恢复。
set -eu
export LANG=C.UTF-8 LC_ALL=C.UTF-8
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

if [ "$(id -u)" -ne 0 ]; then
    echo '请以 root 运行：sudo ufi103s-nm-stop' >&2
    exit 1
fi
echo '即将停止 NetworkManager：Wi-Fi 热点、USB DHCP 和蜂窝联网可能立即断开；ADB 不受此命令控制。' >&2
systemctl stop NetworkManager.service
echo 'NetworkManager 已停止；重启后将恢复，或运行 systemctl start NetworkManager。'
