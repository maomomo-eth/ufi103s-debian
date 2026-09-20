# UFI103S V03 Debian 12 刷机指南

## 1. 确认机型

仅在 PCB 丝印明确为 `UFI103S_V03` 时继续。推荐同时确认 Qualcomm MSM8916、512 MB RAM、4 GB eMMC，以及 EDL USB ID `05c6:9008`。不要只凭外壳判断。

## 2. 准备工具

Linux 需要 Android platform-tools 中的 `adb`、`fastboot`；9008 备份需要 `bkerler/edl`。

```bash
adb version
fastboot --version
```

工具不在 `PATH` 时可指定：

```bash
export ADB=/绝对路径/adb
export FASTBOOT=/绝对路径/fastboot
```

## 3. 必须先备份

强烈建议在任何写入前进入 `05c6:9008`，完成全盘备份：

```bash
EDL=/绝对路径/edl \
./scripts/backup-full-emmc.sh /绝对路径/新备份目录
```

实测 eMMC 容量为 `3909091328` 字节，但脚本会读取目标设备的实际容量。备份成功后必须验证：

```bash
cd /绝对路径/新备份目录
sha256sum -c SHA256SUMS
```

至少需要保留目标设备自己的：

```text
fsc.bin
fsg.bin
modemst1.bin
modemst2.bin
```

支持 `oem dump` 的 lk2nd 也可运行：

```bash
./scripts/backup-calibration.sh /绝对路径/新备份目录
```

这些文件不能从别的设备复制，也不能上传 Git。完整说明见 [9008/EDL 完整备份](EDL_BACKUP.md)。

## 4. 校验 Release

```bash
tar -xzf ufi103s-debian-v2.0.0-private.tar.gz
cd ufi103s-debian-v2.0.0
sha256sum -c SHA256SUMS
```

所有项目必须显示 `OK`。

## 5. KVM/virt-manager 用户

USB PID 会在 EDL、fastboot 和 Debian 之间变化，每次重新枚举后都可能需要在宿主机重新映射：

- EDL：`05c6:9008`
- fastboot：`18d1:d00d`
- Debian gadget：`18d1:d001`

命令见 [KVM USB 映射](KVM_USB.md)。

## 6. 选择刷写方式

### A. 从兼容分区布局的 Debian 11 升级

仅当以下条件全部满足时使用升级脚本：

- 当前 GPT 和 lk2nd/fastboot 能正常工作；
- 当前 Debian 11 使用与本包兼容的 GPT、lk2nd 和分区布局；
- `fastboot getvar product` 为 `LK1ST_MSM8916`；
- 已另行保存完整 eMMC 与校准分区备份。

执行：

```bash
./scripts/flash-debian12-upgrade.sh
```

该脚本只擦除并写入 `rootfs` 和 `boot`，不会触碰 GPT、启动链或校准分区。它先写 rootfs，最后写 boot，避免新旧系统不匹配。

### B. 全量安装或恢复

GPT、启动链或原系统不可信时使用：

```bash
./scripts/flash-fastboot.sh --calibration-dir /绝对路径/本机校准备份
```

该脚本会：

1. 重写 GPT；
2. 写入 CDT、HYP、RPM、SBL1、TZ；
3. 恢复本机 `fsc/fsg/modemst1/modemst2`；
4. 写入 Debian 12 rootfs；
5. 最后写入 boot 与 aboot。

全量脚本具有破坏性，绝不能使用其他设备的校准文件。

## 7. 进入 fastboot

USB ID 应为 `18d1:d00d`：

```bash
fastboot devices
fastboot getvar product
```

如果只有 `05c6:9008`，应先恢复已知匹配的 UFI103S lk2nd。不要在不清楚 GPT 布局时按固定偏移写 bootloader。

## 8. 首次启动

脚本结束后：

1. 物理断电；
2. 重新上电并等待约 60–120 秒；
3. 搜索默认热点 `4G-WIFI`；
4. KVM 中重新映射 `18d1:d001`。

基础镜像的初始凭据：

```text
SSID: 4G-WIFI
Wi-Fi password: 12345678
Debian user: user
Debian password: 1
```

首次登录后立即更改密码和热点配置。不要把个性化连接文件打包回 Release。

## 9. 验证

```bash
./scripts/check-device.sh
./scripts/check-device.sh --network-test
```

预期结果：

- MPSS/WCNSS 状态为 `running`；
- `rmtfs`、ModemManager、NetworkManager 为 `active`；
- `mmcli -L` 能看到 modem；
- 插卡后 `wwan0` 获得 IPv4/IPv6；
- 指定 `wwan0` 的联网测试成功；
- 热点存在 DHCP、DNS 和 MASQUERADE 规则。

不要在自动拨号尚未结束时反复执行 `nmcli connection up modem`。旧版 QMI 栈偶尔会卡在 `disconnecting`；若停止/重启 ModemManager 后端口没有重新出现，优先整机重启，不要改刷 firmware。

## 10. 恢复

无法启动但还能进入 `05c6:9008` 时，优先使用刷机前的完整 eMMC 备份恢复。不要连续尝试其他板型的 GPT、SBL1、CDT、aboot 或“替换基带”文件。
