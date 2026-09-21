# UFI103S V02/V03 Debian 12 刷机与修复

这是 UFI103S 系列（Qualcomm MSM8916、512 MB RAM、4 GB eMMC）4G 随身 Wi‑Fi 的 Debian 刷机、备份和排障仓库。V03 已验证系统启动、热点和蜂窝网络；V02 已验证原厂分区布局与 V03 一致，以及从 9008 全盘写入 v2.0.0 并逐字节回读一致。V02 的实际启动状态仍需另行核验。

`v2.0.0` 已在实机上验证 Debian 12、Wi‑Fi 热点、ADB、Qualcomm MPSS、RMTFS、ModemManager 与中国电信 LTE。修正版解决了 Debian 12 原包缺少适配 UFI103S 的 MPSS firmware，以及 SIM 切换脚本误选多个 GPIO 的问题。

## 已验证状态

- 板号：`UFI103S_V03`；`UFI103S_V02` 已通过整盘刷写回读验证
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

已发布的可刷包见仓库的 [Releases](../../releases)。`v2.0.0` 包含：

- 与实机匹配的 GPT 和启动链
- `ufix0x` Debian 12 boot image
- 已补齐 UFI103S MPSS firmware、修复 SIM 选择脚本的 sparse rootfs
- 9008/EDL 完整 eMMC 备份脚本；本仓库另提供全盘组装、刷写、同机校准恢复及回读校验脚本
- SHA-256 校验文件

发布包**不包含设备专属校准分区、全盘备份、Wi‑Fi 私有配置、SIM 信息或设备身份信息**。
已发布的 v2.0.0 压缩包仍带有旧 fastboot 文件；刷机必须以本仓库最新脚本和文档为准，不要运行压缩包里的旧刷机脚本。

## 刷机流程：只使用 9008 全盘写入

先在 `05c6:9008` 完整备份原机，保持设备处于 9008；从本仓库运行脚本，镜像文件使用解压后的 v2.0.0 发布包：

```bash
EDL=/绝对路径/edl ./scripts/backup-full-emmc.sh /仓库外/新建的原厂备份目录

EDL=/绝对路径/edl ./scripts/flash-edl-full-emmc.sh \
  --backup-dir /仓库外/新建的原厂备份目录 \
  --release-dir /绝对路径/ufi103s-debian-v2.0.0 \
  --output-dir /仓库外/新建的私有刷机目录
```

第二条命令会验证备份和发布包、检查同机原厂数据，生成整盘镜像，直接通过 9008 写入整块 eMMC，再单独恢复本机 `fsc/fsg/modemst1/modemst2`，最后将整盘回读与目标镜像逐字节比较。默认不复位，验证成功后再物理断电上电，或按需加 `--reset`。旧 fastboot 写入脚本已停用。完整步骤与风险见[刷机指南](docs/FLASHING.md)。

## 刷机前备份

至少备份每台设备自己的：

```text
fsc.bin
fsg.bin
modemst1.bin
modemst2.bin
```

在 `05c6:9008` 下完成完整 eMMC 备份后才能刷写：

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

## USB / Wi-Fi 密码 SSH（待实机验证的本地镜像改版）

当前 `v2.0.0` Release **不包含**下面的新功能；不要把本节当成已发布镜像的行为。仓库中的构建脚本现在会在改版 rootfs 中启用 RNDIS/ADB、USB 网络 `192.168.68.1/24` 和 SSH；首次启动仅生成设备专属 SSH 主机密钥，不生成或修改登录密码。允许普通用户从 `usb0` 与 `wlan0` 使用密码登录，拒绝 root SSH 登录，并封闭其他接口（包括蜂窝网络）的 TCP 22 端口。USB 地址使用 NetworkManager 的共享连接，宿主机接入后自动获取地址；Wi-Fi 请连接设备热点后从其网关地址登录。

```bash
ssh user@192.168.68.1                       # USB 网卡
ssh user@热点网关地址                          # Wi-Fi
sudo ufi103s-modem-test                       # 只读测试 modem/射频服务
sudo ufi103s-nm-stop                          # 临时停止 NetworkManager
sudo ufi103s-nm-disable                       # 持久禁用 NetworkManager
sudo ufi103s-nm-enable                        # 解除禁用并立即启动
```

默认 `user/1` 与热点 `4G-WIFI/12345678` 都已公开；按你的要求不自动换密码，因此开启密码 SSH 后必须在可信环境中立即执行 `passwd user` 并更换热点密码。`ufi103s-nm-stop` 只停止到下一次重启；`ufi103s-nm-disable` 会持久屏蔽服务，防止再次被拉起；`ufi103s-nm-enable` 解除屏蔽、设为开机启动并立即启动。停止或禁用均可能断开 Wi-Fi 热点、USB DHCP、蜂窝联网以及当前 SSH 会话；**禁用前先确认 ADB/串口可用，恢复时通过 ADB/串口执行 `sudo ufi103s-nm-enable`**。禁用 NetworkManager 不等于释放 ModemManager 占用的 AT/QMI 端口，安装 VoCat 前仍需按[端口所有权说明](docs/SMS_TROUBLESHOOTING.md#vocat-与-modemmanager-的所有权)处理。测试脚本不发送 AT 命令、不改基带、不写校准分区。

无需重新构建 MPSS，可以对原版 v2.0.0 sparse rootfs 的**副本**生成本地改版镜像：

```bash
./tools/enable-usb-wifi-ssh-rootfs.sh \
  --source /绝对路径/ufi103s-debian-v2.0.0/images/rootfs-debian12-ufi103s-fixed.img \
  --output /仓库外/新建目录/rootfs-usb-wifi-ssh.img
```

输出镜像尚未刷机验证；不要覆盖原版 Release、设备原厂备份或已有镜像，也不要在未经验证前宣称此版已通过实机测试。

今后若按[9008 全盘流程](docs/FLASHING.md)刷入此改版，仍需先备份原机，使用原版 v2.0.0 `--release-dir`，并在刷机脚本原有参数后显式追加：

```bash
--rootfs-override /仓库外/新建目录/rootfs-usb-wifi-ssh.img \
--rootfs-sha256 "$(sha256sum /仓库外/新建目录/rootfs-usb-wifi-ssh.img | cut -d ' ' -f 1)"
```

先用 `--prepare-only` 做不连接设备的整盘组装复核。这个参数只替换 rootfs 来源，不绕过 Release 完整性校验、原厂备份检查或同机校准恢复；不可混用别人的原厂分区。

## USB 模式

| USB ID | 模式 |
| --- | --- |
| `05c6:90b4` | 原 Android/诊断模式 |
| `05c6:9008` | Qualcomm EDL/QDL |
| `18d1:d001` | Debian ADB + RNDIS gadget |

`usb.ids` 可能把 `18d1:d001` 显示为 “Nexus 4 (fastboot)”，不能据此判断设备真的处于 fastboot。KVM 用户见 [USB 映射说明](docs/KVM_USB.md)。

## 关键修复

Debian 12 原包的 rootfs 只有 MBA/WCNSS firmware，缺少 `modem.mdt` 和对应的 `modem.b*`，另附的“替换基带”文件在本机上会把 modem 留在离线状态。`v2.0.0` 改用已经在同一块 UFI103S 上验证过的 MPSS 文件集。

原 `/usr/sbin/openstick-sim-changer.sh` 使用前缀匹配，`sim:sel` 会同时命中 `sim:sel2`，最后关闭所有 SIM 槽。修正版改为完整字符串匹配，开机可稳定选择配置的 SIM GPIO。

这两处修复都位于 rootfs；没有写入或发布任何设备专属基带校准分区。

后续短信对照还确认：同一设备使用中国移动 SIM 时，VoCat 的普通 AT/PDU 收发链路正常；中国电信 LTE 数据可用不能外推为短信可用。运营商结论、`AT+CGSMS`、ModemManager 端口所有权及原机 firmware/NV 恢复边界见[短信排障记录](docs/SMS_TROUBLESHOOTING.md)。

## 安全边界

- 仅针对 PCB 丝印明确为 `UFI103S_V02` 或 `UFI103S_V03`、原厂 GPT 与脚本预期布局一致、eMMC 容量为 `3909091328` 字节的设备。V02 刷写后是否正常启动仍需核验。
- 全量脚本会重写整块 eMMC；不通过 fastboot 刷写，不提供原有分区不变的升级模式。
- 写入前必须做完整备份，并把备份保存在仓库目录之外。
- 不要把 Android 原厂 `modem.bin` 写到本 Release 的 GPT；Linux 从 `/lib/firmware/modem.*` 加载 MPSS。
- 9008 通常可恢复，但错误的 SBL1、CDT、GPT 或 Firehose 操作仍可能使设备无法启动。

## 来源说明

原创脚本和文档采用 MIT License。第三方 rootfs、kernel、firmware 和 bootloader 的来源摘要见 [第三方组件说明](THIRD_PARTY.md)。
