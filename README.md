# UFI103S V03 Debian 12 刷机与修复

这是 `UFI103S_V03`（Qualcomm MSM8916、512 MB RAM、4 GB eMMC）4G 随身 Wi‑Fi 的 Debian 刷机、备份和排障仓库。

`v2.0.0` 已在实机上验证 Debian 12、Wi‑Fi 热点、ADB、Qualcomm MPSS、RMTFS、ModemManager 与中国电信 LTE。修正版解决了 Debian 12 原包缺少适配 UFI103S 的 MPSS firmware，以及 SIM 切换脚本误选多个 GPIO 的问题。

## 已验证状态

- 板号：`UFI103S_V03`
- SoC：Qualcomm MSM8916
- 系统：Debian 12（bookworm）
- 内核：`6.4.0-rc4-jsbsbxjxh66-compile+`
- rootfs：首次启动后扩展至约 3.3 GB
- Wi‑Fi 热点：`4G-WIFI`，DHCP、DNS 与 NAT 正常
- Qualcomm MPSS、WCNSS：均正常运行
- `rmtfs`、ModemManager：正常
- 中国电信 LTE 数据：实测注册、拨号、IPv4/IPv6 和联网正常；这不代表电信短信可用
- 中国移动短信：实测通过普通 AT/PDU 路径接收、发送均正常
- eSIM 小白卡漫游短信：Saily（`+1` 美国号码）漫游中国移动，A1（`+385` 克罗地亚号码）和 HahaSim（`+852` 号码）漫游中国联通，接收短信均正常
- USB gadget：ADB + RNDIS，USB ID 为 `18d1:d001`

详细测试与故障原因见 [Debian 12 实机记录](docs/DEBIAN12.md)、[故障复盘](docs/POSTMORTEM.md)和[短信、基带与 ModemManager 排障记录](docs/SMS_TROUBLESHOOTING.md)。

## Release

私有可刷包见仓库的 [Releases](../../releases)。`v2.0.0` 包含：

- 与实机匹配的 GPT 和启动链
- `ufix0x` Debian 12 boot image
- 已补齐 UFI103S MPSS firmware、修复 SIM 选择脚本的 sparse rootfs
- 全量刷写和 Debian 11 → Debian 12 安全升级脚本
- fastboot 校准备份与 9008/EDL 完整 eMMC 备份脚本
- SHA-256 校验文件

发布包**不包含设备专属校准分区、全盘备份、Wi‑Fi 私有配置、SIM 信息或设备身份信息**。

## 两种刷法

已有与本包分区布局兼容的 Debian 11，且 GPT、lk2nd 和启动链工作正常时，优先只更新 boot 与 rootfs：

```bash
sha256sum -c SHA256SUMS
./scripts/flash-debian12-upgrade.sh
```

原系统、GPT 或启动链损坏时才执行全量刷写；必须传入目标设备自己的校准备份：

```bash
./scripts/flash-fastboot.sh --calibration-dir /绝对路径/本机校准备份
```

完整步骤、适用条件和恢复方法见 [刷机指南](docs/FLASHING.md)。

## 刷机前备份

至少备份每台设备自己的：

```text
fsc.bin
fsg.bin
modemst1.bin
modemst2.bin
```

强烈建议在 `05c6:9008` 下做完整 eMMC 备份：

```bash
EDL=/绝对路径/edl \
./scripts/backup-full-emmc.sh /绝对路径/新备份目录
```

完整说明见 [EDL 备份指南](docs/EDL_BACKUP.md)。这些文件可能包含设备身份和射频校准数据，不能互相混刷或提交 Git。

## 默认访问信息

发布镜像保留第三方基础镜像的初始配置：

- Wi‑Fi SSID：`4G-WIFI`
- Wi‑Fi 密码：`12345678`
- Debian 用户：`user`
- Debian 密码：`1`

首次登录后必须修改密码，按需删除或锁定默认账号，并更改热点凭据：

```bash
adb shell
passwd user
```

不要把修改后的 NetworkManager 连接文件或设备回读 rootfs 放入 GitHub Release。

## USB 模式

| USB ID | 模式 |
| --- | --- |
| `05c6:90b4` | 原 Android/诊断模式 |
| `05c6:9008` | Qualcomm EDL/QDL |
| `18d1:d00d` | lk2nd fastboot |
| `18d1:d001` | Debian ADB + RNDIS gadget |

`usb.ids` 可能把 `18d1:d001` 显示为 “Nexus 4 (fastboot)”，不能据此判断设备真的处于 fastboot。KVM 用户见 [USB 映射说明](docs/KVM_USB.md)。

## 关键修复

Debian 12 原包的 rootfs 只有 MBA/WCNSS firmware，缺少 `modem.mdt` 和对应的 `modem.b*`，另附的“替换基带”文件在本机上会把 modem 留在离线状态。`v2.0.0` 改用已经在同一块 UFI103S 上验证过的 MPSS 文件集。

原 `/usr/sbin/openstick-sim-changer.sh` 使用前缀匹配，`sim:sel` 会同时命中 `sim:sel2`，最后关闭所有 SIM 槽。修正版改为完整字符串匹配，开机可稳定选择配置的 SIM GPIO。

这两处修复都位于 rootfs；没有写入或发布任何设备专属基带校准分区。

后续短信对照还确认：同一设备使用中国移动 SIM 时，VoCat 的普通 AT/PDU 收发链路正常；中国电信 LTE 数据可用不能外推为短信可用。运营商结论、`AT+CGSMS`、ModemManager 端口所有权及原机 firmware/NV 恢复边界见[短信排障记录](docs/SMS_TROUBLESHOOTING.md)。

## 安全边界

- 仅针对 PCB 丝印明确为 `UFI103S_V03` 的设备。
- 全量脚本会重写 GPT；升级脚本只适用于 GPT、lk2nd 与分区布局兼容的 Debian 11 系统。
- 写入前必须做完整备份，并把备份保存在仓库目录之外。
- 不要把 Android 原厂 `modem.bin` 写到本 Release 的 GPT；Linux 从 `/lib/firmware/modem.*` 加载 MPSS。
- 9008 通常可恢复，但错误的 SBL1、CDT、GPT 或 Firehose 操作仍可能使设备无法启动。

## 来源说明

原创脚本和文档采用 MIT License。第三方 rootfs、kernel、firmware 和 bootloader 的来源摘要见 [第三方组件说明](THIRD_PARTY.md)。
