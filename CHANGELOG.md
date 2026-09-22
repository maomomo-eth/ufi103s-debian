# 更新记录

## v2.2.0 - 2026-09-22

- 发布配套的 Android sparse rootfs 和 GPT／启动链／boot 基础包；rootfs 内不包含任何单机备份。
- 移除 NetworkManager 停用命令及其热点接管服务，保留 NetworkManager 管理 Wi‑Fi 热点与 USB DHCP。
- 内置 `ufi103s-modemmanager`，可持久屏蔽／恢复 ModemManager，便于 VoCat 独占 modem；禁用、启用时 USB 与 Wi‑Fi 网络均保持运行。
- 冷启动自动加载 `qcom_wcnss_pil`、`wcn36xx`，修复首次启动后缺少 `wlan0` 的问题。
- V02 本地整盘重刷、单独恢复同机四个校准/NV 分区后，USB DHCP、Wi‑Fi 热点、密码 SSH、蜂窝驻网与 ModemManager 开关实测通过；按本次操作要求未进行整盘回读。V03 尚未对本版单独重刷测试。
- 延续此前设备使用者的短信测试记录：Saily eSIM 小白卡（`+1`）漫游中国移动、A1 eSIM 小白卡（`+385`）与 HahaSim 实体 SIM（`+852`）漫游中国联通，均可接收短信；**这些卡尚未针对本版重新测试**。

早期排障背景见 [技术复盘](docs/POSTMORTEM.md)。
