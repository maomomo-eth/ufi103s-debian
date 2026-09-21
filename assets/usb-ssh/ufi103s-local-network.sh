#!/bin/sh
# NetworkManager 停用期间独立维持原热点和 USB DHCP；不启动蜂窝数据连接。
set -eu
export LANG=C.UTF-8 LC_ALL=C.UTF-8
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

run_dir=/run/ufi103s-local-network
wifi_profile=/etc/NetworkManager/system-connections/WIFI.nmconnection

stop_services() {
    for name in dnsmasq wpa; do
        pid_file="$run_dir/$name.pid"
        if [ -s "$pid_file" ]; then
            pid=$(cat "$pid_file")
            case "$pid" in
                *[!0-9]*|'') echo "无效的 $name PID，拒绝停止其他进程。" >&2; return 1 ;;
            esac
            if [ -r "/proc/$pid/cmdline" ] && tr '\0' ' ' < "/proc/$pid/cmdline" | grep -Fq "$run_dir"; then
                kill "$pid" 2>/dev/null || true
                attempt=0
                while kill -0 "$pid" 2>/dev/null && [ "$attempt" -lt 25 ]; do
                    attempt=$((attempt + 1))
                    sleep 0.2
                done
            fi
            rm -f -- "$pid_file"
        fi
    done
}

case "${1:-}" in
    start)
        [ -r "$wifi_profile" ] || { echo '缺少 Wi-Fi 热点配置。' >&2; exit 1; }
        for command in wpa_supplicant wpa_passphrase wpa_cli dnsmasq ip; do
            command -v "$command" >/dev/null 2>&1 || { echo "缺少命令：$command" >&2; exit 1; }
        done
        ssid=$(sed -n '/^ssid=/{s/^ssid=//;p;q;}' "$wifi_profile")
        passphrase=$(sed -n '/^psk=/{s/^psk=//;p;q;}' "$wifi_profile")
        channel=$(sed -n '/^channel=/{s/^channel=//;p;q;}' "$wifi_profile")
        [ -n "$ssid" ] && [ "${#passphrase}" -ge 8 ] && [ "${#passphrase}" -le 63 ] || {
            echo '热点名称或密码无效，保持原有连接。' >&2; exit 1;
        }
        case "$channel" in
            [1-9]|1[0-3]) frequency=$((2407 + channel * 5)) ;;
            14) frequency=2484 ;;
            *) echo '热点频道无效，保持原有连接。' >&2; exit 1 ;;
        esac
        [ -d /sys/class/net/usb0 ] && [ -d /sys/class/net/wlan0 ] || {
            echo 'USB 或 Wi-Fi 网卡未就绪。' >&2; exit 1;
        }
        # dnsmasq 降权为 nobody 后仍需穿过运行目录写租约；配置文件始终只允许 root 读取。
        install -d -m 0711 "$run_dir"
        install -d -o nobody -g nogroup -m 0750 "$run_dir/leases"
        umask 077
        printf 'ctrl_interface=%s/ctrl\n' "$run_dir" > "$run_dir/wpa.conf"
        printf '%s\n' "$passphrase" | wpa_passphrase "$ssid" |
            awk -v frequency="$frequency" '
                /^#psk=/ {next}
                /^}/ {print "\tmode=2\n\tfrequency=" frequency "\n\tproto=RSN\n\tpairwise=CCMP\n\tgroup=CCMP"}
                {print}
            ' >> "$run_dir/wpa.conf"
        unset passphrase
        # 只在 NM 已停用后接管，防止两个管理器同时操作同一块网卡。
        if systemctl is-active --quiet NetworkManager.service; then
            echo 'NetworkManager 仍在运行，拒绝并行接管网卡。' >&2; exit 1
        fi
        trap 'stop_services; ip address del 10.42.0.1/24 dev wlan0 2>/dev/null || true; ip address del 192.168.68.1/24 dev usb0 2>/dev/null || true' EXIT
        ip link set usb0 up
        ip address replace 192.168.68.1/24 dev usb0
        wpa_supplicant -B -P "$run_dir/wpa.pid" -D nl80211 -i wlan0 -c "$run_dir/wpa.conf"
        attempt=0
        while ! wpa_cli -p "$run_dir/ctrl" -i wlan0 status 2>/dev/null | grep -q '^wpa_state=COMPLETED$'; do
            attempt=$((attempt + 1))
            [ "$attempt" -lt 12 ] || { echo 'Wi-Fi 热点未就绪。' >&2; exit 1; }
            sleep 1
        done
        ip link set wlan0 up
        ip address replace 10.42.0.1/24 dev wlan0
        # 接续 NM 原有租约，避免切换后 DHCP 客户端续租收到 NAK。
        lease_file="$run_dir/leases/dnsmasq.leases"
        install -o nobody -g nogroup -m 0600 /dev/null "$lease_file"
        for previous in /var/lib/NetworkManager/dnsmasq-usb0.leases \
            /var/lib/NetworkManager/dnsmasq-wlan0.leases; do
            if [ -r "$previous" ]; then
                awk -v now="$(date +%s)" '$1 ~ /^[0-9]+$/ && $1 > now && NF >= 4 { print }' \
                    "$previous" >> "$lease_file"
            fi
        done
        dnsmasq --conf-file=/dev/null --no-hosts --bind-interfaces --except-interface=lo \
            --interface=usb0 --interface=wlan0 --listen-address=192.168.68.1 \
            --listen-address=10.42.0.1 \
            --dhcp-range=usb0,192.168.68.10,192.168.68.254,60m \
            --dhcp-range=wlan0,10.42.0.10,10.42.0.254,60m \
            --dhcp-leasefile="$lease_file" \
            --pid-file="$run_dir/dnsmasq.pid"
        [ -s "$run_dir/dnsmasq.pid" ] || { echo 'USB/Wi-Fi DHCP 未就绪。' >&2; exit 1; }
        trap - EXIT
        echo 'Wi-Fi 热点与 USB DHCP 已由独立服务接管；蜂窝联网未启动。'
        ;;
    stop)
        stop_services
        ip address del 10.42.0.1/24 dev wlan0 2>/dev/null || true
        ip address del 192.168.68.1/24 dev usb0 2>/dev/null || true
        rm -f -- "$run_dir/wpa.conf"
        ;;
    *) echo '用法：ufi103s-local-network {start|stop}' >&2; exit 2 ;;
esac
