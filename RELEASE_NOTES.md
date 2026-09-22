# UFI103S Debian 12 (v2.2.0) - USB/Wi-Fi/SSH 与内置 ModemManager 管理

专为 `UFI103S_V02` / `UFI103S_V03` 硬件定制的 Debian 12 系统固件包，开箱即用支持 USB RNDIS、Wi-Fi 热点、SSH 远程访问与 VoCat 短信转发。

---

## 📦 发布文件校验 (Assets)

| 文件名 | 类型 | SHA-256 校验和 | 说明 |
| :--- | :--- | :--- | :--- |
| `ufi103s-debian-v2.2.0-base.tar.gz` | 基础包 | `c1949cc0cb96b1b77ae26ff170d72712e2af9aaca198115e98e90f4e2f07977f` | 包含 GPT 布局、启动链与 boot 镜像 |
| `rootfs-debian12-usb-wifi-ssh-vocat-mm-wifi.img` | 分区镜像 | `65fa6962951cafd1fc38d886d6e8df714904b61c2443cdfb7c4e436f3c31e2d6` | Android sparse 格式 rootfs（约 861MB） |

> [!CAUTION]
> **刷机重要警示**：
> 1. 本 Release 提供的 `.img` 为 **rootfs 分区镜像**而非整盘镜像，**切勿直接执行 `edl wf rootfs-*.img`**！
> 2. 刷机前必须使用脚本对当前设备进行**全盘备份**，再使用仓库工具组装出带有当前设备独立射频校准（`fsc/fsg/modemst1/modemst2`）的整盘镜像进行 9008 写入。
> 3. 详细刷机步骤请严格遵照 [📖 9008 全盘刷机指南](https://github.com/maomomo-eth/ufi103s-debian/blob/main/docs/FLASHING.md)。

---

## 🚀 核心特性与变更

- **系统升级**：基于精简版 Debian 12 (Bookworm)，启动自动加载 WCNSS Wi-Fi 驱动。
- **开箱即用网络**：
  - USB RNDIS 网卡：设备地址 `192.168.68.1`（宿主机自动获取 `192.168.68.x`）。
  - Wi-Fi AP 热点：SSID 为 `4G-WIFI`（密码 `12345678`），网关 `10.42.0.1`。
  - SSH 远程管理：默认账户 `user`（密码 `1`），仅对内网 (USB / Wi-Fi) 开放。
- **VoCat 短信解耦管理**：
  - 内置 `ufi103s-modemmanager`：支持一键持久屏蔽 ModemManager 并释放 AT/QMI 串口给 VoCat 独占，同时保持 NetworkManager 正常管理 Wi-Fi 与 USB DHCP。
  - 内置 `ufi103s-modem-test`：开箱即用的基带与驱动只读诊断工具。

---

## 📋 快速凭据参考

| 项目 | 默认值 | 登录说明 |
| :--- | :--- | :--- |
| **USB 网关** | `192.168.68.1` | `ssh user@192.168.68.1` |
| **Wi-Fi 热点** | `4G-WIFI` / `12345678` | `ssh user@10.42.0.1` |
| **默认密码** | `user` / `1` | 提权执行 `sudo -i`（密码同为 `1`） |

> [!WARNING]
> 以上密码为公开默认值，部署至生产或不受信任环境前请务必使用 `passwd` 修改。

---

## 📖 相关文档

- [项目主页与快速上手 (README)](https://github.com/maomomo-eth/ufi103s-debian/blob/main/README.md)
- [9008 备份与刷机指南 (FLASHING.md)](https://github.com/maomomo-eth/ufi103s-debian/blob/main/docs/FLASHING.md)
- [VoCat 短信与基带排错指南 (SMS_TROUBLESHOOTING.md)](https://github.com/maomomo-eth/ufi103s-debian/blob/main/docs/SMS_TROUBLESHOOTING.md)
- [KVM / 虚拟机 USB 穿透说明 (KVM_USB.md)](https://github.com/maomomo-eth/ufi103s-debian/blob/main/docs/KVM_USB.md)
