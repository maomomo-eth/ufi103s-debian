#!/bin/sh
# 只读检查 MPSS、RMTFS、ModemManager 和注册状态；不抢占 AT/QMI 端口。
set -eu
export LANG=C.UTF-8 LC_ALL=C.UTF-8
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

echo '== 固件 / MPSS =='
for device in /sys/class/remoteproc/remoteproc*; do
    [ -r "$device/name" ] || continue
    name=$(cat "$device/name")
    case "$name" in
        *4080000*|*mpss*|*modem*)
            printf '%s: ' "$name"
            cat "$device/state"
            ;;
    esac
done

echo '== 系统服务 =='
for service in rmtfs ModemManager NetworkManager; do
    printf '%s: ' "$service"
    systemctl is-active "$service" 2>/dev/null || true
done

echo '== ModemManager =='
if ! command -v mmcli >/dev/null 2>&1; then
    echo '未安装 mmcli。' >&2
    exit 1
fi
mmcli -L || exit 1
# 只筛选运行状态，避免将 IMEI、SIM 标识或号码输出到测试记录。
mmcli -m any -K 2>/dev/null | awk -F ':' '
    {
        key = $1
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
        if (key == "modem.generic.state" ||
            key == "modem.generic.access-technologies" ||
            key == "modem.3gpp.registration-state") print
    }
' || true

echo '== 网络设备 =='
ip -brief link show dev wwan0 2>/dev/null || echo '当前没有 wwan0。'
