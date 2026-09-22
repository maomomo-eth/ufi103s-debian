# Debian 12 构建与实机验证记录

> 历史构建记录：描述早期 boot/rootfs 升级试验，**不是当前刷机步骤**。刷机请从 [README](../README.md) 和 [9008 指南](FLASHING.md) 开始。

## 输入文件

从 `debian12-jsbsbxjxh66` 解压内容中选用：

- `debian12-酷安-jsbsbxjxh66/jsbsbxjxh66/rootfs.img`：原始 Debian 12 sparse rootfs。
- `debian12-酷安-jsbsbxjxh66/jsbsbxjxh66-boot/msm8916-jsbsbxjxh66-ufix0x-1.0.dtb-boot.img`：boot 镜像。

DTB model 明确包含 `ufi-103x`，并具备 `rmtfs`、MPSS 和 memshare 节点。boot command line 的 root UUID 与 Debian 12 rootfs 一致。

## rootfs 修正

1. 将 sparse image 转成 raw ext4，并完成 `e2fsck` 修复。
2. 从已验证的 UFI103S Debian 11 rootfs 取出 `mba.mbn`、`modem.mdt` 和 `modem.b*`，共 22 个文件。
3. 覆盖 Debian 12 `/lib/firmware` 中相应文件。
4. 安装修复后的 `/usr/sbin/openstick-sim-changer.sh`。
5. 删除预生成 SSH host keys、固定 machine-id、shell history、random seed 和旧日志。
6. 再次执行 `e2fsck`，重建 ext4 journal，并用 `zerofree` 清零已释放块。
7. 转回 Android sparse image，并做 sparse → raw 回环校验。

发布用修正版 rootfs：

```text
文件：rootfs-debian12-ufi103s-fixed.img
大小：861458880 字节
SHA-256：e4f56e1b4ccb93f4847788c3429a898fa343130281337634251a45fd9c5462ef
```

转换回 raw 后执行 `e2fsck -f -n`，结果为干净文件系统：

```text
29107/64000 files
231648/256000 blocks
```

仓库的 `tools/build-debian12-rootfs.sh` 记录了同样的构建过程。它只接受干净的基础镜像和通用 firmware 目录，不读取设备分区或运行中的系统。

## 刷写范围

实机从已工作的 Debian 11 基线升级时只写入：

- `rootfs`
- `boot`

未写入 GPT、SBL1、CDT、aboot、`fsc`、`fsg`、`modemst1` 或 `modemst2`。这既缩小风险，也能明确区分 firmware 问题和设备校准数据问题。

## 热点验证

默认 `4G-WIFI` 连接启动后验证：

- WLAN 地址位于 `10.42.0.0/24`
- dnsmasq 提供 DHCP 和 DNS
- `net.ipv4.ip_forward=1`
- `POSTROUTING` 存在热点网段的 `MASQUERADE`
- FORWARD 规则允许 WLAN 与 WWAN 之间转发
- 仅 WWAN 作为外网出口时，域名解析和互联网访问成功

## SIM 卡短信验证

在同一台 UFI103S V03 上追加验证了两张 eSIM 小白卡和一张 HahaSim 实体 SIM：

| 服务/号码国家码 | 连接网络 | 接收短信 |
| --- | --- | --- |
| 中国移动，`+86` | 中国移动 | 正常 |
| 中国电信，`+86` | 中国电信 | 能连接LTE数据，无法收发短信。 |
| Saily，`+1` 美国号码 | 中国移动 | 正常 |
| A1，`+385` 克罗地亚号码 | 中国联通 | 正常 |
| HahaSim 实体 SIM，`+852` 号码 | 中国联通 | 正常 |

这里只记录号码国家码，不包含完整手机号、ICCID、IMSI 或其他 SIM 标识。本次结论仅覆盖接收短信，不代表发送短信也已验证。

## 隐私检查范围

发布内容来自未启动、未个性化的基础 rootfs，不使用设备回读镜像。打包前检查以下内容不得出现：

- 私人 Wi‑Fi SSID 和连接文件
- 非默认密码或密钥
- IMSI、IMEI、ICCID、序列号
- SSH host/private keys
- `fsc/fsg/modemst1/modemst2`
- 完整 eMMC 备份或 GPT 读取日志

通用默认热点 `4G-WIFI/12345678` 属于上游基础镜像的公开初始配置，保留用于首次连接；使用者必须在首次登录后修改。
