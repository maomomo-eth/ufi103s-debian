#!/usr/bin/env bash
set -Eeuo pipefail

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

adb_bin="${ADB:-adb}"

"$adb_bin" devices -l
"$adb_bin" shell uname -a
"$adb_bin" shell cat /etc/os-release
"$adb_bin" shell df -hT /
"$adb_bin" shell systemctl --failed --no-pager --plain
"$adb_bin" shell systemctl is-active rmtfs ModemManager NetworkManager mobian-usb-gadget
"$adb_bin" shell mmcli -L
"$adb_bin" shell mmcli -m 0
"$adb_bin" shell ip -br address
"$adb_bin" shell ip route

