# UFI103S V02/V03：从原厂系统进入 9008 全盘刷入

本页用于**首次刷入、原厂 GPT 尚在、备份后没有再次启动原系统**的设备。`scripts/flash-edl-full-emmc.sh` 会核对 eMMC 容量、原厂 GPT 与原机当时的 `modemst1/modemst2/persist`；设备已经刷过 Debian 时，这些前提不成立，不能绕过校验或把别的机器的原厂备份当作当前机器使用。完整操作会覆盖整块 eMMC。

已实测板号 `UFI103S_V02`、`UFI103S_V03`；脚本**固定要求** eMMC 容量 `3909091328` 字节及匹配的原厂分区布局。其他 UFIx0x 板号仅可在自行验证 SoC、GPT/启动链、DTB、容量与基带兼容后另行适配，不能直接照抄本页命令。

## 1. 进入 9008 并确认 USB

关机状态按住 SIM 卡旁边的按键，再插入 USB；如果原系统 ADB 正常，也可尝试：

```bash
adb reboot edl
lsusb -d 05c6:9008
```

只允许**一台** `05c6:9008` 设备映射到本机。KVM 虚拟机每次 USB ID 切换都要重新映射，见 [USB 映射](KVM_USB.md)。刷写期间请保持供电和 USB 连接；不要通过 fastboot 写分区。

准备当前仓库的脚本、[bkerler/edl](https://github.com/bkerler/edl)、`uv`、`rg`、`lsusb`、`sha256sum`。从 [v2.1.0 Release](https://github.com/maomomo-eth/ufi103s-debian/releases/tag/v2.1.0) 下载两个文件：`ufi103s-debian-v2.1.0-base.tar.gz`（GPT、启动链、boot 及 `SHA256SUMS`）与已实测的 `rootfs-debian12-usb-wifi-ssh-local-network.img`。解压基础包并指定其实际路径：

```bash
export EDL=/绝对路径/edl
export BACKUP=/仓库外/stock-本机-日期
export RELEASE=/绝对路径/ufi103s-debian-v2.1.0-base
export ROOTFS=/绝对路径/rootfs-debian12-usb-wifi-ssh-local-network.img
export PREPARE=/仓库外/首次离线组装-本机-日期
export FLASH=/仓库外/正式刷机-本机-日期
```

以上目录的父目录必须已存在，`BACKUP`、`PREPARE`、`FLASH` 自身**不得已存在**；它们必须位于 Git 仓库外。不要直接把 rootfs `.img` 当成全盘执行 `edl wf`。下载后按实际位置填写绝对路径，不必把镜像放入 Git 仓库。

## 2. 完整备份原机

```bash
EDL="$EDL" ./scripts/backup-full-emmc.sh "$BACKUP"
(cd "$BACKUP" && sha256sum -c SHA256SUMS)
```

备份必须有 `original-full-emmc.bin`（此板实测 `3909091328` 字节）、`partitions/modem.bin`、`partitions/persist.bin` 及 `partitions/fsc.bin`、`fsg.bin`、`modemst1.bin`、`modemst2.bin`。缺失、容量不同或校验失败应停止。建议复制一份到另一块存储介质。不要使用 `--reset`，也不要在备份与首次刷写间重启原系统，否则 NV 可能改变，脚本会拒绝非同机状态的写盘。

备份内可能有设备身份、SIM 与密码，不要发到 Issue、Git 或 Release。

## 3. 使用同机备份和最新 rootfs 组装整盘镜像

先核对基础包文件的清单及实测 rootfs 的 SHA-256；实际整盘镜像由 `--rootfs-override` 指向独立下载的 rootfs：

```bash
(cd "$RELEASE" && sha256sum -c SHA256SUMS)
printf '%s  %s\n' '5c1770b27d70aae9a4c475b6b8f8a1f037b2d7bc1f11f38ddfaaa995f08aff50' "$ROOTFS" | sha256sum -c -

./scripts/flash-edl-full-emmc.sh \
  --backup-dir "$BACKUP" --release-dir "$RELEASE" \
  --rootfs-override "$ROOTFS" \
  --rootfs-sha256 5c1770b27d70aae9a4c475b6b8f8a1f037b2d7bc1f11f38ddfaaa995f08aff50 \
  --output-dir "$PREPARE" --prepare-only
```

这个离线步骤**不连接设备、不写盘**；会从同一份原厂完整备份复制原机数据，补入经校验的 GPT/启动链/boot/rootfs，并从该机备份放入四个 NV/校准分区，再校验主备 GPT、分区边界和整盘哈希。原机 `modem` 数据来自原厂全盘，Linux 运行时的 MPSS 从 rootfs `/lib/firmware` 加载；不要把他机 `modem.bin` 填进镜像。

## 4. 9008 写入、单独恢复校准并整盘回读

保持原机仍处于 `05c6:9008`，使用**另一个尚不存在**的输出目录执行：

```bash
EDL="$EDL" ./scripts/flash-edl-full-emmc.sh \
  --backup-dir "$BACKUP" --release-dir "$RELEASE" \
  --rootfs-override "$ROOTFS" \
  --rootfs-sha256 5c1770b27d70aae9a4c475b6b8f8a1f037b2d7bc1f11f38ddfaaa995f08aff50 \
  --output-dir "$FLASH" --reset
```

脚本再次组装镜像，比对当前设备的原厂 GPT 和同机 NV，输入指定确认字符串后才执行 EDL `wf` 全盘写入；随后单独恢复 `fsc/fsg/modemst1/modemst2` 并逐项回读，再 EDL `rf` **回读整块 eMMC** 与目标镜像逐字节比较。只有这些都成功后 `--reset` 才让设备尝试启动。镜像 `debian-v2-full-emmc.bin` 与 `device-readback.bin` 都留在 `$FLASH`，含私有数据，绝不上传。任何阶段失败，保持 9008、保存日志、不要强行启动部分写入的系统。

> 已刷入 Debian 的设备重刷时 GPT 已变，首次原厂脚本会拒绝；必须单独核对当前 GPT、容量、同机校准身份，才能执行新的全盘操作。本仓库不提供跳过身份校验的一键重刷参数。本次 V02 重刷日志与回读保存在仓库外，没有当作公开镜像发布。

## 5. 首次启动、USB 与 SSH

设备重启约需 1–2 分钟。USB 会从 `05c6:9008` 变成 `18d1:d001`（Debian ADB + RNDIS；`lsusb` 显示“fastboot”字样也不代表真进入 fastboot）；虚拟机要重新映射。宿主机加载 `rndis_host` 后经 USB DHCP 获取 `192.168.68.x`，设备地址 `192.168.68.1`。热点为 `4G-WIFI/12345678`，设备 Wi‑Fi 网关 `10.42.0.1`。

```bash
ssh user@192.168.68.1
sudo ufi103s-modem-test
```

初始用户为 `user/1`。首启自动生成**本机** SSH 主机密钥，不生成登录强密码；SSH 接受 USB/Wi‑Fi 密码登录，但阻止蜂窝接口接入。请自行修改默认用户和热点密码。独立关闭 NetworkManager 的脚本仍保留热点/USB DHCP；VoCat 使用方式见[短信转发说明](SMS_TROUBLESHOOTING.md)。

如果只有存储回读通过、没有 USB 或热点，不能称为系统启动成功；先保留 EDL 回读与错误日志，再从 ADB/串口检查启动服务。
