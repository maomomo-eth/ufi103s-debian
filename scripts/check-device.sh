#!/usr/bin/env bash
set -Eeuo pipefail

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

usage() {
    cat <<'EOF'
用法：
  ./scripts/check-device.sh [--network-test]

选项：
  --network-test  强制通过 wwan0 测试 IPv4 和 IPv6

环境变量：
  ADB=/绝对路径/adb
EOF
}

network_test=0
while (($#)); do
    case "$1" in
        --network-test)
            network_test=1
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

adb_bin="${ADB:-adb}"
if ! command -v "$adb_bin" >/dev/null 2>&1 && [[ ! -x "$adb_bin" ]]; then
    echo "找不到 adb：$adb_bin" >&2
    exit 1
fi

"$adb_bin" devices -l
"$adb_bin" shell 'uname -a; cat /etc/os-release; df -hT /'

echo "核心服务："
"$adb_bin" shell 'for unit in rmtfs ModemManager NetworkManager qrtr-ns linux-adbd-utils; do printf "%s=" "$unit"; systemctl is-active "$unit" || true; done'

echo "remoteproc："
"$adb_bin" shell 'for rp in /sys/class/remoteproc/remoteproc*; do [ -e "$rp/state" ] || continue; printf "%s=" "$(basename "$rp")"; cat "$rp/state"; done'

echo "网络设备："
"$adb_bin" shell 'nmcli -t -f DEVICE,TYPE,STATE device status; ip -brief address; ip route'

echo "modem 脱敏状态："
"$adb_bin" shell 'mmcli -L; mmcli -m 0 2>/dev/null | grep -E "state:|power state:|signal quality:|access tech:|registration:|operator name:" || true'

echo "失败单元："
"$adb_bin" shell 'systemctl --failed --no-pager --plain || true'

if ((network_test == 1)); then
    echo "通过 wwan0 测试 IPv4："
    "$adb_bin" shell 'ping -4 -I wwan0 -c 3 -W 5 deb.debian.org'

    echo "通过 wwan0 测试 IPv6："
    "$adb_bin" shell 'ping -6 -I wwan0 -c 3 -W 5 deb.debian.org'
fi
