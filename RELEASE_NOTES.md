# v2.2.0：UFI103S Debian 12、USB/Wi‑Fi/SSH 与 ModemManager 开关

本次发布两份配套文件：

```text
65fa6962951cafd1fc38d886d6e8df714904b61c2443cdfb7c4e436f3c31e2d6  rootfs-debian12-usb-wifi-ssh-vocat-mm-wifi.img
c1949cc0cb96b1b77ae26ff170d72712e2af9aaca198115e98e90f4e2f07977f  ufi103s-debian-v2.2.0-base.tar.gz
```

`.img` 是 Android sparse 格式的 **rootfs 分区镜像**（861512128 字节），不是整盘镜像，不能直接执行 `edl wf rootfs-*.img`。基础包包含 GPT、boot 和启动链，不包含单机校准数据。先按[刷机指南](https://github.com/maomomo-eth/ufi103s-debian/blob/main/docs/FLASHING.md)完整备份当前设备的原厂 eMMC，再用本仓库脚本将基础包、rootfs 和**该设备自身**的备份组装成整盘镜像，从 9008 写入并恢复同机 `fsc/fsg/modemst1/modemst2`；不要通过 fastboot 写盘。

本版 rootfs 内置 `ufi103s-modem-test` 和 `ufi103s-modemmanager`，**无需另外下载或安装管理脚本**。VoCat 需要独占 AT/QMI 端口时运行 `sudo ufi103s-modemmanager disable`，该操作会持久屏蔽 ModemManager，但保留管理 Wi‑Fi 热点和 USB DHCP 的 NetworkManager；停用 VoCat 后可执行 `sudo ufi103s-modemmanager enable` 恢复。首启自动生成设备专属 SSH 主机密钥，自动加载无线驱动；USB 网关 `192.168.68.1`，热点 `4G-WIFI/12345678`，初始 SSH 用户 `user/1`。这些默认密码是公开的，请部署后自行修改。

V02 已实测整盘写入、同机校准分区单独写回、冷启动、USB DHCP、Wi‑Fi 热点、密码 SSH、MPSS/蜂窝驻网及 ModemManager 的禁用/启用；**本次按使用者要求跳过整盘回读**，不声称完成逐字节刷写校验。V03 在以往 Debian 12 设备上有 VoCat 短信转发反馈，但本版尚未在 V03 单独重刷实测；其他 `UFIx0x` 板号仅属兼容性推测，必须先核对 GPT、eMMC 容量、SoC、boot/DTB 与基带适配。

公开资产不含任何设备的原厂整盘备份、回读镜像、IMEI、SIM、校准/NV 或私人 Wi‑Fi/SSH 数据。完整步骤见 [README](https://github.com/maomomo-eth/ufi103s-debian/blob/main/README.md)、[9008 刷机指南](https://github.com/maomomo-eth/ufi103s-debian/blob/main/docs/FLASHING.md) 与 [VoCat 说明](https://github.com/maomomo-eth/ufi103s-debian/blob/main/docs/SMS_TROUBLESHOOTING.md)。
