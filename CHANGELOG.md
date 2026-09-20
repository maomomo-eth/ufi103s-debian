# 更新记录

## 未发布

- 增加 Saily（`+1` 美国号码）漫游中国移动，A1（`+385` 克罗地亚号码）和 HahaSim（`+852` 号码）漫游中国联通的 eSIM 小白卡接收短信实测。
- 增加 UFI103S V03 短信、基带与 ModemManager 实机排障记录。
- 明确中国电信 LTE 数据可用不代表短信可用，并记录中国移动 AT/PDU 短信收发成功的对照结果。
- 补充 `modem.bin` 提取、同机 NV 恢复、remoteproc/分区动态识别、回读校验和隐私边界。
- 明确本次刷写前蜂窝 MPSS 与有效 NV 已匹配原机备份，不能把更换 SIM 后的成功错误归因于重复刷写。

## v2.0.0 - 2026-09-15

- 升级为经过实机验证的 Debian 12（bookworm）rootfs 和 `ufix0x` boot。
- 从已验证的 UFI103S Debian 11 镜像补齐 22 个 MPSS firmware 文件。
- 修复 SIM 切换脚本对 `sim:sel` 和 `sim:sel2` 的错误前缀匹配。
- 增加 Debian 11 → Debian 12 的 boot/rootfs 安全升级脚本，不触碰校准分区。
- 更新全量刷写脚本、设备检查脚本、刷机指南和射频初始化复盘。
- 实测 LTE 注册、IPv4/IPv6、指定 WWAN 出口、Wi‑Fi 热点 DHCP/DNS/NAT 和冷启动持久化。
- 发布包使用干净基础镜像构建，不包含设备回读数据和私有网络配置。
