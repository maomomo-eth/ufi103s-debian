# v2.1.0：UFI103S V02 实测 Debian 12 USB／热点／SSH rootfs

本次发布的唯一镜像是 `rootfs-debian12-usb-wifi-ssh-local-network.img`（Android sparse 格式，861512128 字节），SHA-256：

```text
5c1770b27d70aae9a4c475b6b8f8a1f037b2d7bc1f11f38ddfaaa995f08aff50  rootfs-debian12-usb-wifi-ssh-local-network.img
530cdbb4fcb83fd48c273ca883dc37187896e0eb8a00b4951ec63dfb78670897  ufi103s-debian-v2.1.0-base.tar.gz
```

这是**分区镜像，不是整盘镜像**。同一 Release 的 `ufi103s-debian-v2.1.0-base.tar.gz` 提供 GPT／boot／启动链；结合**目标设备自身**的完整原厂 eMMC 备份，由当前仓库的 `scripts/flash-edl-full-emmc.sh` 组装整盘并在 9008 写入；随后单独恢复同机 `fsc/fsg/modemst1/modemst2`、逐项回读、整盘回读验证。不要执行 `edl wf` 直接写入本文件，不要通过 fastboot 刷写。完整操作请从 [README](https://github.com/maomomo-eth/ufi103s-debian/blob/main/README.md) 和 [9008 刷机指南](https://github.com/maomomo-eth/ufi103s-debian/blob/main/docs/FLASHING.md) 开始。

## 已验证的行为与边界

- UFI103S V02：本镜像完成 9008 整盘重刷、四个同机 NV/校准分区单独恢复、整盘回读逐字节一致、冷启动、USB RNDIS/DHCP、Wi‑Fi 热点和密码 SSH；MPSS、蜂窝联网正常。
- 使用者反馈 UFI103S V02/V03 刷入 Debian 12 并安装 VoCat 后，短信转发可以正常使用；这不是对其他 `UFIx0x` 版本的验证。
- 首次启动自动生成 SSH 主机密钥，USB 网卡设备侧 `192.168.68.1`、Wi‑Fi 热点 `4G-WIFI/12345678`，SSH 登录 `user/1`。默认密码公开且较弱，使用后应修改。
- 镜像内已有 `ufi103s-modem-test`、`ufi103s-nm-disable`、`ufi103s-nm-enable`。禁用 NetworkManager 后仍可保留热点、USB DHCP/SSH，但会断开蜂窝数据；Wi‑Fi 要改客户端模式时，先保留或恢复 NetworkManager。
- 当前仓库新增 `ufi103s-modemmanager`（为 VoCat 独占端口关闭／恢复 ModemManager）；**此已实测镜像不内置该新增脚本**，按 README 中的说明通过 SSH 复制安装即可。重新构建得到的镜像哈希将不同，不应称作本次实测镜像。

脚本对 UFI103S V02/V03 的固定 eMMC 容量和原厂 GPT 进行检查；其他板号即使外形相同，也必须另行确认 SoC、GPT、boot／DTB、容量、基带兼容。备份校准数据是必要条件，不保证跨型号通刷。发布资源不包含任何一台实机的整盘镜像、回读、NV/校准文件、SIM 或私人 Wi‑Fi／SSH 数据。
