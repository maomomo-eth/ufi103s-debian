# UFI103S V03 刷机指南

## 1. 确认机型

仅在 PCB 丝印明确为 `UFI103S_V03` 时继续。推荐同时确认：

- Qualcomm MSM8916
- 512 MB RAM
- 4 GB eMMC
- EDL USB ID `05c6:9008`

不要仅凭白色外壳或商品名称判断机型。

## 2. 准备工具

Linux 需要 Android platform-tools 中的 `adb`、`fastboot`。9008 备份/恢复可使用 `bkerler/edl`。

检查：

```bash
adb version
fastboot --version
```

若工具不在 `PATH`，可指定：

```bash
export FASTBOOT=/绝对路径/fastboot
```

## 3. 必须先备份

至少保存：

```text
fsc.bin
fsg.bin
modemst1.bin
modemst2.bin
```

强烈建议在 9008 下额外保存完整 eMMC。实测设备容量为 `3909091328` 字节，但应以目标设备实际容量为准。

完整备份脚本会自动读取实际容量、导出 GPT 和关键分区、校验全盘镜像大小并生成 SHA-256：

```bash
EDL=/绝对路径/edl \
./scripts/backup-full-emmc.sh /绝对路径/新备份目录
```

详细说明见 [9008/EDL 完整备份](EDL_BACKUP.md)。

如果当前已处于支持 `oem dump` 的 lk2nd fastboot，可执行：

```bash
./scripts/backup-calibration.sh /绝对路径/备份目录
```

备份后必须执行：

```bash
sha256sum -c /绝对路径/备份目录/SHA256SUMS
```

不要继续使用其他设备导出的校准文件。

## 4. KVM/virt-manager 注意事项

USB PID 会随模式变化。每次重新枚举后，可能需要再次映射到虚拟机：

- EDL：`05c6:9008`
- fastboot：`18d1:d00d`
- Debian gadget：`18d1:d001`

详见 [KVM USB 映射](KVM_USB.md)。

## 5. 校验 Release

```bash
tar -xzf ufi103s-debian-v1.0.0-private.tar.gz
cd ufi103s-debian-v1.0.0
sha256sum -c SHA256SUMS
```

所有项目必须显示 `OK`。

## 6. 进入 fastboot

目标状态：

```bash
fastboot devices
```

应显示一个序列号，USB ID 应为 `18d1:d00d`。

如果设备只能进入 `05c6:9008`，应先通过 EDL 恢复可启动的 UFI103S lk2nd。不要在不清楚当前 GPT 布局时按固定偏移写 bootloader。

## 7. 执行刷写

```bash
./scripts/flash-fastboot.sh --calibration-dir /绝对路径/本机校准备份
```

刷写顺序：

1. fastboot 动态修补并写入 GPT。
2. 写入 CDT、HYP、RPM、SBL1、TZ。
3. 恢复本机 `fsc/fsg/modemst1/modemst2`。
4. 擦除 boot 和 rootfs。
5. 写入修复版 1.2 GHz boot。
6. 写入 sparse rootfs。
7. 最后写入 aboot。

rootfs 写入约需数分钟，中途不能拔线或退出虚拟机。

## 8. 首次启动

脚本完成后：

1. 物理断电。
2. 重新上电并等待约 60 秒。
3. 搜索热点 `4G-WIFI`。
4. 如 USB 重新枚举，在 KVM 中映射 `18d1:d001`。

访问凭据：

```text
SSID: 4G-WIFI
Wi-Fi password: 12345678
Debian user: user
Debian password: 1
```

立即修改登录密码：

```bash
adb shell
passwd user
```

## 9. 验证 4G

```bash
adb shell systemctl is-active rmtfs ModemManager
adb shell mmcli -L
adb shell mmcli -m 0
adb shell ip route
adb shell ping -c 3 1.1.1.1
```

预期：

- `rmtfs` 和 `ModemManager` 均为 `active`
- `mmcli -L` 能看到 `/Modem/0`
- 插卡后状态为 `connected`
- `wwan0` 获得地址和默认路由

## 10. 恢复

如果无法启动但还能进入 `05c6:9008`，优先从完整 eMMC 备份恢复。不要先反复尝试其他板型的 SBL1、CDT 或 aboot。
