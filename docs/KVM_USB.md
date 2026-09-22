# KVM / virt-manager USB 穿透指南

在 Linux KVM 虚拟机（搭配 virt-manager 或 libvirt）中进行随身 Wi-Fi 刷机时，设备在不同运行阶段的 USB Vendor:Product ID 会发生切换，导致静态映射的 USB 设备在重启或切换模式时失效。

---

## 1. 设备模式与 USB ID 对照表

| 运行阶段 / 模式 | USB ID | 说明 |
| :--- | :--- | :--- |
| **EDL 9008 刷机模式** | `05c6:9008` | 按键插入或 `adb reboot edl` 后的模式，用于刷机与备份 |
| **Android 原系统** | `05c6:90b4` | 原厂系统的默认 ADB / Modem 复合设备 |
| **Debian 12 正常运行** | `18d1:d001` | Debian 下的 ADB + RNDIS 复合设备（部分工具可能显示 fastboot 字样） |

> 整个 9008 全盘刷机流程**全程保持在 `05c6:9008`**，不需要映射 fastboot 设备。

---

## 2. 虚拟机内部 udev 权限配置

在 Linux 虚拟机内创建 udev 规则，确保无须 root 权限即可直接读写 USB 设备：

```bash
sudo tee /etc/udev/rules.d/51-openstick.rules >/dev/null <<'EOF'
SUBSYSTEM=="usb", ATTR{idVendor}=="05c6", ATTR{idProduct}=="90b4", MODE:="0666"
SUBSYSTEM=="usb", ATTR{idVendor}=="05c6", ATTR{idProduct}=="9008", MODE:="0666"
SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", ATTR{idProduct}=="d001", MODE:="0666"
EOF

# 重载规则生效
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=usb
```

---

## 3. 宿主机动态穿透脚本

当设备在宿主机发生重枚举时，可通过仓库自带的脚本将设备热插拔挂载到虚拟机（无需重启虚拟机）：

```bash
# 查看虚拟机名称与设备列表
virsh list --all
lsusb

# 将 9008 设备热插拔挂载到正在运行的虚拟机
sudo ./scripts/kvm-attach-usb.sh <虚拟机名> edl

# 刷写完毕重启后，将 Debian 复合设备挂载到虚拟机
sudo ./scripts/kvm-attach-usb.sh <虚拟机名> debian
```

> [!TIP]
> - `kvm-attach-usb.sh` 底层使用 `virsh attach-device --live`，仅对当前运行中的虚拟机生效，不会永久修改虚拟机 XML 硬件配置。
> - 若宿主机 `lsusb` 都无法看到 `05c6:9008`，请检查物理 USB 供电、线材或延长线质量。
