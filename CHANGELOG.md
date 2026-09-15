# 更新记录

## 未发布

- 增加 UFI103S V03 短信、基带与 ModemManager 实机排障记录。
- 明确中国电信 LTE 数据可用不代表短信可用，并记录中国移动 AT/PDU 短信收发成功的对照结果。
- 记录 giffgaff 在设备和手机上均无法接收测试短信，避免把 SIM/漫游问题误判为 VoCat 故障。
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

## v1.0.1 - 2026-09-15

- 增加 9008/EDL 完整 eMMC 备份脚本。
- 自动保存 GPT、全盘镜像和当前 GPT 中存在的关键分区。
- 增加容量、可用空间、输出大小和 SHA-256 完整性校验。
- 增加完整备份隐私与恢复风险说明。

## v1.0.0 - 2026-09-15

- 增加 UFI103S V03 私有完整刷机包。
- 修复 1.2 GHz boot DTB 缺少 MPSS reserved-memory 与 memshare 节点的问题。
- 保留 1.2 GHz CPU 上限。
- 增加 Linux fastboot 刷机、校准备份、KVM USB 映射和设备检查脚本。
- 实机验证 Debian、Wi‑Fi、ADB、LTE、IPv4/IPv6、DNS 与热点 NAT。
