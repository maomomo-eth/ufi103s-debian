# UFI103S V03 Debian 刷机与修复记录

这是 `UFI103S_V03`（Qualcomm MSM8916、512 MB RAM、4 GB eMMC）4G 随身 Wi‑Fi 的 Debian 刷机仓库。

本仓库记录了一次实机刷写、失败定位和修复过程，并提供经过实机验证的私有 Release。最终系统可正常启动 Debian、开启 Wi‑Fi 热点、识别中国电信 SIM、注册 LTE 并访问互联网。

## 已验证状态

- 板号：`UFI103S_V03`
- SoC：Qualcomm MSM8916
- 系统：Debian 11（bullseye）
- 内核：`5.15.0-jsbsbxjxh66+`
- CPU：最高保留在 1.2 GHz
- rootfs：自动扩展至约 3.3 GB
- Wi‑Fi 热点：正常
- Qualcomm MPSS：正常启动
- `rmtfs.service`：正常
- ModemManager：正常识别 LTE modem
- 中国电信 LTE：实测注册、拨号、IPv4/IPv6、DNS 和 NAT 正常
- USB gadget：ADB + RNDIS，USB ID 为 `18d1:d001`

## Release

私有可刷包见仓库的 [Releases](../../releases)。发布包包含：

- GPT 与 UFI103S 启动链
- 修复后的 1.2 GHz boot image
- Debian sparse rootfs
- Linux fastboot 刷写脚本
- 9008/EDL 完整 eMMC 备份脚本
- SHA-256 校验文件

发布包**不包含任何设备专属校准分区**。刷机时必须使用目标设备自己的：

- `fsc.bin`
- `fsg.bin`
- `modemst1.bin`
- `modemst2.bin`

这些文件可能包含设备身份及射频校准数据，禁止互相混刷或上传公开仓库。

## 快速使用

详细步骤见 [刷机指南](docs/FLASHING.md)。从 Release 解压后：

```bash
sha256sum -c SHA256SUMS
./scripts/flash-fastboot.sh --calibration-dir /绝对路径/本机校准备份
```

脚本会要求输入 `UFI103S` 二次确认。写完后需要物理断电再上电，不能依赖部分 lk2nd 环境中的 `fastboot reboot`。

完整 eMMC 备份方法见 [EDL 备份指南](docs/EDL_BACKUP.md)：

```bash
EDL=/绝对路径/edl \
./scripts/backup-full-emmc.sh /绝对路径/新备份目录
```

## 默认访问信息

首次启动默认值：

- Wi‑Fi SSID：`4G-WIFI`
- Wi‑Fi 密码：`12345678`
- Debian 用户：`user`
- Debian 密码：`1`

请在首次登录后立即修改：

```bash
adb shell
passwd user
```

## USB 模式

| USB ID | 模式 |
| --- | --- |
| `05c6:90b4` | 原 Android/诊断模式 |
| `05c6:9008` | Qualcomm EDL/QDL |
| `18d1:d00d` | lk2nd fastboot |
| `18d1:d001` | Debian ADB + RNDIS gadget |

`usb.ids` 可能把 `18d1:d001` 错误显示为 “Nexus 4 (fastboot)”，实际并不是 fastboot。

## 关键修复

第三方包原始 `1.2.img` 的设备树引用了 MPSS 内存区域，却漏掉对应的 `mpss@86800000` 节点，导致：

```text
qcom-q6v5-mss 4080000.remoteproc: unable to resolve mpss region
```

表现为 Debian 和 Wi‑Fi 可用，但 `rmtfs` 失败、ModemManager 找不到 modem。

修复版只补入同包 `1.4.img` 已有的 MPSS reserved-memory 和 memshare 节点，不加入 1.3/1.4 GHz OPP，保留 1.2 GHz 上限。修复过程见 [故障复盘](docs/POSTMORTEM.md)。

## 安全边界

- 仅针对 `UFI103S_V03`；相似外壳不代表硬件相同。
- 写 GPT 会清空现有系统，操作前必须保留完整 eMMC 和关键分区备份。
- 不要把原厂 `modem.bin` 写入本 Release 的 GPT：该 GPT 没有 `modem` 分区。
- 当前 Linux 从 `/lib/firmware/modem.*` 加载 MPSS firmware；设备专属数据保存在校准分区。
- 9008 通常可恢复，但错误写入 boot chain 仍可能要求拆机短接测试点。

## 来源与许可说明

刷机基础工具参考：

- [OpenStick Builder](https://github.com/kinsamanka/OpenStick-Builder)
- [bkerler/edl](https://github.com/bkerler/edl)

第三方 Debian 镜像的批处理文件标注作者为 `jsbsbxjxh66`。原包没有附带许可证，因此完整二进制仅放在用户指定的私有仓库 Release 中，不主张其版权，也不授权再次公开分发。仓库中原创脚本和文档采用 MIT License；第三方 firmware、bootloader、kernel 和 rootfs 不在 MIT License 覆盖范围内。
