# virt-manager/KVM USB 映射

原 Android 进入 9008、刷机完成并启动 Debian 时，USB 会切换 PID，因此单次图形界面映射通常不会持续。刷机过程始终留在 9008，不需要映射 fastboot。

## 虚拟机内 udev 权限

```bash
sudo tee /etc/udev/rules.d/51-openstick.rules >/dev/null <<'EOF'
SUBSYSTEM=="usb", ATTR{idVendor}=="05c6", ATTR{idProduct}=="90b4", MODE:="0666"
SUBSYSTEM=="usb", ATTR{idVendor}=="05c6", ATTR{idProduct}=="9008", MODE:="0666"
SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", ATTR{idProduct}=="d001", MODE:="0666"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=usb
```

规则只解决虚拟机内权限，不能代替宿主机的 libvirt USB 映射。

## 宿主机命令行映射

先确认宿主机能看到设备：

```bash
lsusb
virsh list --all
```

然后使用本仓库脚本：

```bash
sudo ./scripts/kvm-attach-usb.sh <虚拟机名> edl
sudo ./scripts/kvm-attach-usb.sh <虚拟机名> debian
```

每次 PID 改变后执行对应模式。脚本使用 `virsh attach-device --live`，只影响正在运行的虚拟机，不永久修改虚拟机定义。

如果宿主机 `lsusb` 根本看不到设备，libvirt 无法映射；应先检查物理供电、USB 口、线材和设备是否停留在无 USB 输出的启动阶段。
