#!/bin/sh
# VoCat 独占 AT/QMI 端口时关闭 ModemManager；不操作热点、USB 或校准数据。
set -eu
export LANG=C.UTF-8 LC_ALL=C.UTF-8
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

usage() {
    echo '用法：ufi103s-modemmanager {disable|enable|status}' >&2
    exit 2
}

case "${1:-}" in
    status)
        printf 'ModemManager 活动状态：'
        systemctl is-active ModemManager.service || true
        printf 'ModemManager 开机状态：'
        systemctl is-enabled ModemManager.service || true
        ;;
    disable|enable)
        [ "$#" -eq 1 ] || usage
        if [ "$(id -u)" -ne 0 ]; then
            echo '请使用 sudo 运行。' >&2
            exit 1
        fi
        if [ "$1" = disable ]; then
            # 先屏蔽再停止，防止 D-Bus 在 VoCat 启动时重新拉起服务。
            systemctl mask ModemManager.service
            systemctl stop ModemManager.service
            echo 'ModemManager 已禁用；热点和 USB 网络不受此脚本控制。'
        else
            echo '恢复前请先停止 VoCat，避免两个程序同时占用 AT/QMI 端口。' >&2
            systemctl unmask ModemManager.service
            systemctl enable --now ModemManager.service
            echo 'ModemManager 已恢复。'
        fi
        ;;
    *) usage ;;
esac
