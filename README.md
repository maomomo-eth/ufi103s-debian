# UFI103S V02/V03 Debian 12：9008 备份与刷机

本仓库只推荐 **9008 全盘流程**。`UFI103S_V02`、`UFI103S_V03` 已实测刷入 Debian 12、USB 网卡、Wi‑Fi 热点、SSH、蜂窝射频与 VoCat 短信转发；VoCat 在两种板号上的结果来自设备使用者的实测反馈。VoCat 需要独占 modem 时只禁用 ModemManager，保留 NetworkManager 管理 Wi‑Fi 与 USB DHCP。

`UFIx0x` 其他数字组合**仅是兼容性推测，不是已验证设备清单**。本仓库组装和刷写脚本只接受已核对原厂 GPT 布局、容量恰为 `3909091328` 字节的 V02/V03；其他板即使能进入 9008，也必须先独立确认 SoC、Firehose、GPT/启动链、DTB、eMMC 容量与 MPSS 兼容。完整备份原机基带和校准数据是必要条件，**不是跨板通刷的充分条件**，绝不能把一台设备的 NV/校准分区写到另一台。

## 镜像与备份

- [v2.2.0 Release](https://github.com/maomomo-eth/ufi103s-debian/releases/tag/v2.2.0) 的 rootfs：`rootfs-debian12-usb-wifi-ssh-vocat-mm-wifi.img`，SHA-256：`65fa6962951cafd1fc38d886d6e8df714904b61c2443cdfb7c4e436f3c31e2d6`。V02 实测开机自动加载 WCNSS/Wi‑Fi 驱动；USB DHCP、热点、密码 SSH、蜂窝驻网及 ModemManager 开关正常。本次重刷按使用者要求直接写盘、未做整盘回读；V03 尚未对**此版本**单独重刷测试。
- 同一 Release 的 `ufi103s-debian-v2.2.0-base.tar.gz` 提供组装整盘所需的 GPT、启动链、`ufix0x` boot 及校验清单；使用**本仓库当前脚本**，并显式指定上述 rootfs。
- `.img` 是 Android sparse 格式的 **rootfs 分区镜像，不是整盘镜像**；不能直接执行 `edl wf 此文件`。正式刷入的是脚本结合原机备份生成的 `debian-v2-full-emmc.bin`。
- 原厂完整 eMMC、`modem.bin`/固件及 `fsc/fsg/modemst1/modemst2/persist` 等数据必须来自**正在刷的这一台设备**；备份和整盘输出放在仓库之外，不能上传 Release。
- 本地按板号分别存放设备备份；同板号的每台设备各使用一个 `bak-<15位IMEI>` 目录。构建、刷写日志和回读等中间产物放在独立的私有 `work/` 目录，不混入按设备命名的原厂备份。

## 从原厂系统刷入：七步

完整命令、安全检查与 KVM 说明见 [刷机指南](docs/FLASHING.md)。本节是操作顺序，不省略原机完整备份。

1. 按住 **SIM 卡旁的按键**插入 USB，或在原系统 ADB 可用时运行 `adb reboot edl`。USB 重新枚举后，以 `lsusb -d 05c6:9008` 确认进入 EDL；若 ADB 命令不生效，使用按键。KVM 需重新映射这个 USB ID。
2. 先从设备标签或原系统核对 **15 位 IMEI**；在对应板号的私有目录下使用 `bak-<IMEI>` 命名备份目录，再于 9008 使用 `scripts/backup-full-emmc.sh` **完整备份原机 eMMC**、GPT 和关键分区；运行 `sha256sum -c SHA256SUMS` 复核。脚本校验目录格式和 IMEI 校验位，但不能从 9008 自动核实其与当前设备一致。不要把不同设备的备份放在同一个目录；备份后不要让原厂系统再次启动或断开同机校验条件。
3. 用 v2.2.0 配套基础包的 GPT/boot、实测 rootfs 及这台设备的原厂全盘备份组装整盘镜像。原机 `modem` 分区随原厂全盘备份保留，`fsc/fsg/modemst1/modemst2` 来自同一备份；Linux MPSS 固件由 rootfs 中的 `/lib/firmware` 提供。先使用刷机脚本 `--prepare-only` 离线验证；**不要把 Android 的 `modem.bin` 直接写到 rootfs 或其他分区**。
4. 设备仍处于 9008 时，使用本仓库的 `scripts/flash-edl-full-emmc.sh` 写入**整块 eMMC**，然后从同机备份单独恢复四个校准/NV 分区；每项回读、整盘回读并逐字节比较后再重启。不进入 fastboot。刷写会清除原机系统和用户数据。
5. 首次启动会生成本机专属 SSH 主机密钥，开启 RNDIS/ADB USB 网卡（设备 `192.168.68.1/24`）、SSH 与 Wi‑Fi 热点。默认热点 `4G-WIFI` / `12345678`；默认用户名 `user`、密码 `1`。USB 连接后用 `ssh user@192.168.68.1`，Wi‑Fi 连接后用 `ssh user@10.42.0.1`。仅允许从 USB/Wi‑Fi 接入 SSH，蜂窝接口不开放密码 SSH；首次使用应修改默认用户和热点密码。
6. SSH 登录后运行 `sudo ufi103s-modem-test`，只读检查 MPSS、`rmtfs`、ModemManager、注册状态与 `wwan0`；不向 modem 发送 AT 命令，不写入基带或校准分区。
7. 按需安排用途：可以自行把 Wi‑Fi 改为客户端上网。安装 VoCat 仅做短信转发、需要独占 AT/QMI 端口时，运行 `sudo ufi103s-modemmanager disable`；**不要禁用 NetworkManager**，否则 Wi‑Fi 和 USB DHCP 可能中断。

## ModemManager 与 VoCat

v2.2.0 镜像**已经内置** `ufi103s-modemmanager`；不需要下载、复制或另行安装脚本。安装 VoCat、需要独占 modem 的 AT/QMI 端口时运行：

```bash
sudo ufi103s-modemmanager disable
ufi103s-modemmanager status
```

`disable` 会持久屏蔽 ModemManager，重启后不会自动启动。恢复前先停 VoCat，再运行 `sudo ufi103s-modemmanager enable`。脚本只管理 ModemManager，**不会停止 NetworkManager 或主动关闭 Wi‑Fi 热点/USB 网络**。原有蜂窝数据连接可能随 ModemManager 停止而失效；VoCat 需要上网时建议自行设置 Wi‑Fi 客户端。短信测试边界见[短信与 VoCat 说明](docs/SMS_TROUBLESHOOTING.md)。

## 安全与隐私

- 密码 `1` 和热点密码 `12345678` 是公开的默认值；按要求**不在首启自动生成强密码**，部署到不可信环境前请手动修改。
- 备份、回读镜像、日志可能含 IMEI/序列号、SIM、Wi‑Fi、SSH 信息。公开文档或 Release 只能使用从干净基础镜像生成并通过隐私检查的文件，不能使用运行中设备回读的 rootfs。
- 原厂首次刷机会比对**原厂 GPT 和当时的 NV**。已刷过 Debian 的同机重刷须指定 `--reflash-debian`，默认核对 Debian GPT、容量、原厂/当前 EDL 串号及 `fsc`；原厂日志没有串号时可按[刷机指南](docs/FLASHING.md)显式选择 `--force-no-serial` 强刷。强刷仍核对 GPT、容量及备份完整性并要求人工输入机身 IMEI，但**不再自动证明是同一台设备**；V02/V03 原厂 `fsc/fsg` 相同，绝不可仅凭它们识别设备。
- 遇到无线/短信异常，先确认设备端口所有权、运营商短信能力、rootfs 固件和原机校准备份；不要盲目刷入他机基带。

构建与故障原因保留在 [Debian 12 历史记录](docs/DEBIAN12.md)和[问题复盘](docs/POSTMORTEM.md)；这些记录不是当前刷机步骤。虚拟机 USB 映射见 [KVM 说明](docs/KVM_USB.md)。

## 初始化后常用命令

### 配置WIFI客户端模式
```bash
#删除WIFI热点
nmcli connection delete WIFI

#进入WIFI客户端连接交互界面
nmtui-connect

#清除锁定WIFI频道，避免路由器换了频道没自动连上
nmcli connection modify {WIFI名} 802-11-wireless.channel ""
nmcli connection modify  {WIFI名} 802-11-wireless.band ""
nmcli connection modify  {WIFI名} connection.autoconnect yes connection.autoconnect-priority 100

nmcli -f 802-11-wireless.ssid,802-11-wireless.band,802-11-wireless.channel,connection.autoconnect connection show  {WIFI名}

### 关闭4G数据
ufi103s-modemmanager disable
```

### 设置ROOT密码
```bash
passwd root
```

### 允许ROOT登录并删除user
```bash
rm /etc/ssh/sshd_config.d/20-ufi103s-usb.conf
pkill -u user
userdel -r user
getent group user
```
