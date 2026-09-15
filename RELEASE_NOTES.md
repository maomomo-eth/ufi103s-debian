# v2.0.0：UFI103S V03 Debian 12 实机验证版

这是面向 PCB 丝印 `UFI103S_V03`、MSM8916、512 MB RAM、4 GB eMMC 设备的私有恢复包。

## 本版内容

- Debian 12（bookworm）sparse rootfs
- `6.4.0-rc4-jsbsbxjxh66-compile+` 内核与 `ufix0x` DTB boot image
- 已验证的 UFI103S MPSS firmware 文件集
- 修复后的 `openstick-sim-changer.sh`
- UFI103S 对应 GPT、CDT 与启动链
- 全量刷写及 Debian 11 → Debian 12 升级脚本
- fastboot 校准备份与 9008/EDL 完整 eMMC 备份脚本
- 完整 SHA-256 清单

## 实机结果

- Debian 12 与默认 `4G-WIFI` 热点正常启动
- rootfs 扩展至约 3.3 GB
- MPSS、WCNSS、RMTFS、ModemManager 正常
- 中国电信 SIM 的 LTE 数据注册成功，IPv4/IPv6 与互联网访问正常；本项不包含短信能力
- 热点 DHCP、DNS、IPv4 forwarding 和 MASQUERADE 正常
- 冷启动后 firmware 与 SIM 修复持续生效

## v2.0.0 关键修复

Debian 12 原始 rootfs 缺少完整 `modem.*`；原包附带的替换 firmware 与本机不匹配，modem 会停留在离线状态。本版改用已在同一型号实机验证的 UFI103S MPSS 文件集。

原 SIM 脚本用前缀匹配查找 sysfs LED，`sim:sel` 会同时命中 `sim:sel2`，形成无效路径并关闭全部 SIM 槽。本版改用完整字符串匹配。

## 刷写选择

已有本仓库 `v1.0.x` 且 GPT/lk2nd 正常时，使用：

```bash
./scripts/flash-debian12-upgrade.sh
```

需要重建 GPT 和启动链时，使用目标设备自己的校准备份：

```bash
./scripts/flash-fastboot.sh --calibration-dir /绝对路径/本机校准备份
```

刷写完成后物理断电再上电。完整步骤见 `docs/FLASHING.md`。

## 隐私边界

Release 不包含 `fsc/fsg/modemst1/modemst2`、完整 eMMC 备份、设备回读 rootfs、SIM 标识、IMEI、SSH 私钥或私人 Wi‑Fi 配置。发布镜像保留通用默认热点 `4G-WIFI/12345678`，首次登录后必须更改默认凭据。
