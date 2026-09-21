# 更新记录

## v2.1.0 - 2026-09-22

- 发布实测 sparse rootfs（SHA-256 `5c1770b27d70aae9a4c475b6b8f8a1f037b2d7bc1f11f38ddfaaa995f08aff50`）及 GPT／启动链／boot 配套包；两个文件都可从同一 Release 获取，不含实机私有备份。
- V02 9008 整盘写入、同机四个校准分区恢复、整盘逐字节回读成功；冷启动后 USB RNDIS/DHCP、热点、密码 SSH 与蜂窝联网正常。首次启动生成独立 SSH 主机密钥。
- 使用者反馈 V02/V03 安装 VoCat 后短信转发正常；其他 UFIx0x 板型尚未验证。
- 将文档收敛为 9008 完整备份 → 同机备份与配套文件组装整盘 → 写盘并恢复四个校准分区 → 回读 → 首启及 VoCat；删除不适用的 fastboot 刷机入口与重复脚本。
- 更新 `ufi103s-nm-disable`／`ufi103s-nm-enable`：关闭蜂窝数据时保留 Wi‑Fi 热点、USB DHCP/SSH。新增独立 ModemManager 开关脚本供 VoCat 使用；**本次实测 img 不含新脚本**，可按 README 手动安装。
- 测试记录：Saily `+1` 漫游中国移动、A1 `+385` 与 HahaSim `+852` 漫游中国联通，均可接收短信。

早期排障背景见 [技术复盘](docs/POSTMORTEM.md)。
