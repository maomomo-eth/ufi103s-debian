#!/bin/sh

sleep 10

LED_PATH=/sys/class/leds
SIM_ENABLED=${SIM_ENABLED:-sim0}

get_sims() {
  # 只返回 SIM 控制 LED，避免匹配其他设备。
  ls "$LED_PATH" | grep sim
}

disable_all_sim() {
  for sim in $(get_sims); do
    echo 0 > "$LED_PATH/$sim/brightness"
  done
}

enable_sim() {
  disable_all_sim

  # 必须完整匹配。原脚本的前缀匹配会让 sim:sel 同时命中 sim:sel2，
  # 生成带换行的无效 sysfs 路径并关闭全部 SIM 槽位。
  sim="$(get_sims | grep -F -x -- "$1" | head -n 1)"
  if [ -z "$sim" ]; then
    echo "找不到 SIM 控制 GPIO：$1" >&2
    return 1
  fi

  echo 1 > "$LED_PATH/$sim/brightness"
  modprobe -r qcom-q6v5-mss
  modprobe qcom-q6v5-mss
  systemctl restart rmtfs
  systemctl restart dbus-org.freedesktop.ModemManager1.service
}

enable_sim "$SIM_ENABLED"
