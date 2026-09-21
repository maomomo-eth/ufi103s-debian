#!/bin/sh
# 每次启动确保 USB 网络和防火墙就绪；主机密钥只在首次启动时生成。
# 不生成或修改任何用户密码。
set -eu
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

ssh-keygen -A

# USB gadget 由 linux-adbd-utils.service 建立；开机未接宿主机时也要能绑定 SSH 地址。
attempt=0
while [ ! -d /sys/class/net/usb0 ]; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 30 ]; then
        echo 'USB gadget 未创建 usb0，SSH 不会启动。' >&2
        exit 1
    fi
    sleep 1
done

# 无条件插到 INPUT 顶部，避免系统原有规则让蜂窝接口先于拦截规则放行。
# 若防火墙不可用，则失败关闭 SSH，避免将密码登录暴露到蜂窝接口。
iptables -w -I INPUT 1 -p tcp --dport 22 -j DROP
iptables -w -I INPUT 1 -i wlan0 -p tcp --dport 22 -j ACCEPT
iptables -w -I INPUT 1 -i usb0 -p tcp --dport 22 -j ACCEPT

# shared 模式提供 DHCP/DNS；未连接宿主机时先确保本机 USB IP 存在。
if ! nmcli -w 15 connection up uuid c114f48e-be80-4e4f-b942-666e354233f0 ifname usb0; then
    ip link set usb0 up
    ip address replace 192.168.68.1/24 dev usb0
    echo 'USB DHCP 暂不可用，宿主机接入后由 NetworkManager 自动连接。' >&2
fi

sshd -t
