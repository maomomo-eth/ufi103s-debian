# UFI103S V02/V03：从原厂系统进入 9008 全盘刷入

本页的主流程用于**首次刷入、原厂 GPT 尚在、备份后没有再次启动原系统**的设备。`scripts/flash-edl-full-emmc.sh` 会核对 eMMC 容量、原厂 GPT 与原机当时的 `modemst1/modemst2/persist`；设备已经刷过 Debian 时，这些前提不成立，须使用下面单独说明的重刷模式。完整操作会覆盖整块 eMMC，绝不能把别的机器的原厂备份当作当前机器使用。

已实测板号 `UFI103S_V02`、`UFI103S_V03`；脚本**固定要求** eMMC 容量 `3909091328` 字节及匹配的原厂分区布局。其他 UFIx0x 板号仅可在自行验证 SoC、GPT/启动链、DTB、容量与基带兼容后另行适配，不能直接照抄本页命令。

## 1. 进入 9008 并确认 USB

关机状态按住 SIM 卡旁边的按键，再插入 USB；如果原系统 ADB 正常，也可尝试：

```bash
adb reboot edl
lsusb -d 05c6:9008
```

只允许**一台** `05c6:9008` 设备映射到本机。KVM 虚拟机每次 USB ID 切换都要重新映射，见 [USB 映射](KVM_USB.md)。刷写期间请保持供电和 USB 连接；不要通过 fastboot 写分区。

准备当前仓库的脚本、[bkerler/edl](https://github.com/bkerler/edl)、`uv`、`rg`、`lsusb`、`sha256sum`。从 [v2.2.0 Release](https://github.com/maomomo-eth/ufi103s-debian/releases/tag/v2.2.0) 下载两个文件：`ufi103s-debian-v2.2.0-base.tar.gz`（GPT、启动链、boot 及 `SHA256SUMS`）与已实测的 `rootfs-debian12-usb-wifi-ssh-vocat-mm-wifi.img`。解压基础包并指定其实际路径：

```bash
export EDL=/绝对路径/edl
read -r -p '请核对设备标签并输入 15 位 IMEI：' IMEI
export BACKUP="/仓库外/ufi103s-v02/bak-$IMEI"
export RELEASE=/绝对路径/ufi103s-debian-v2.2.0-base
export ROOTFS=/绝对路径/rootfs-debian12-usb-wifi-ssh-vocat-mm-wifi.img
export PREPARE=/仓库外/首次离线组装-本机-日期
export FLASH=/仓库外/正式刷机-本机-日期
```

将 `ufi103s-v02` 换成实际板号（例如 V03）；从标签或原系统核对 IMEI，不能靠 EDL 自动确认。以上目录的父目录必须已存在，`BACKUP`、`PREPARE`、`FLASH` 自身**不得已存在**；它们必须位于 Git 仓库外。同一板号下每台设备各有自己的 `bak-<IMEI>` 目录，备份和校准分区绝不混用。不要直接把 rootfs `.img` 当成全盘执行 `edl wf`。下载后按实际位置填写绝对路径，不必把镜像放入 Git 仓库。

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
printf '%s  %s\n' '65fa6962951cafd1fc38d886d6e8df714904b61c2443cdfb7c4e436f3c31e2d6' "$ROOTFS" | sha256sum -c -

./scripts/flash-edl-full-emmc.sh \
  --backup-dir "$BACKUP" --release-dir "$RELEASE" \
  --rootfs-override "$ROOTFS" \
  --rootfs-sha256 65fa6962951cafd1fc38d886d6e8df714904b61c2443cdfb7c4e436f3c31e2d6 \
  --output-dir "$PREPARE" --prepare-only
```

这个离线步骤**不连接设备、不写盘**；会从同一份原厂完整备份复制原机数据，补入经校验的 GPT/启动链/boot/rootfs，并从该机备份放入四个 NV/校准分区，再校验主备 GPT、分区边界和整盘哈希。原机 `modem` 数据来自原厂全盘，Linux 运行时的 MPSS 从 rootfs `/lib/firmware` 加载；不要把他机 `modem.bin` 填进镜像。

## 4. 9008 写入、单独恢复校准并整盘回读

保持原机仍处于 `05c6:9008`，使用**另一个尚不存在**的输出目录执行：

```bash
EDL="$EDL" ./scripts/flash-edl-full-emmc.sh \
  --backup-dir "$BACKUP" --release-dir "$RELEASE" \
  --rootfs-override "$ROOTFS" \
  --rootfs-sha256 65fa6962951cafd1fc38d886d6e8df714904b61c2443cdfb7c4e436f3c31e2d6 \
  --output-dir "$FLASH" --reset
```

脚本再次组装镜像，比对当前设备的原厂 GPT 和同机 NV，输入指定确认字符串后才执行 EDL `wf` 全盘写入；随后单独恢复 `fsc/fsg/modemst1/modemst2` 并逐项回读，再 EDL `rf` **回读整块 eMMC** 与目标镜像逐字节比较。只有这些都成功后 `--reset` 才让设备尝试启动。镜像 `debian-v2-full-emmc.bin` 与 `device-readback.bin` 都留在 `$FLASH`，含私有数据，绝不上传。任何阶段失败，保持 9008、保存日志、不要强行启动部分写入的系统。

### 已装 Debian 的同机重刷

当前设备的 GPT 已变，首次原厂模式会拒绝。保留原厂完整备份，先按第 3 步离线运行 `--prepare-only`；正式重刷使用**全新的私有** `--output-dir`，在第 4 步写盘命令上增加 `--reflash-debian`。默认会核对当前 Debian GPT、eMMC 容量、备份时与当前的 EDL 硬件串号以及 `fsc`。Debian GPT 没有 `persist` 分区；基带运行后可能改变 `fsg/modemst1/modemst2`，因此不强求这些文件仍与旧原厂备份相同。正式写盘会再次单独恢复同机四个校准/NV 分区、逐项回读，并回读整盘。

如果**原厂日志没有 `Serial: 0x...`**（例如 V03 备份的 `gpt.txt` 只有分区表），可以显式增加 `--force-no-serial` 强刷。此选项仅适用于 `--reflash-debian`，不允许与 `--yes` 同用，并要求在交互式终端输入**机身标签上的 IMEI**，与 `bak-<IMEI>` 目录一致才能继续；不能把新取得的串号伪称为原厂历史日志。强刷**仍会检查 GPT、容量、原厂备份和 Release 校验清单、`fsc`，并在刷写后逐项/整盘回读**，但这些检查不能证明当前设备就是该备份所属设备：已有 V02/V03 备份中的 `fsc` 与 `fsg` 相同。一定要亲自辨认机身与备份，错刷他机校准可能导致基带或射频失常。以下命令只示范已装 Debian 的设备，无需再备份原厂系统；`$FLASH` 必须换成尚不存在的新私有目录：

```bash
EDL="$EDL" ./scripts/flash-edl-full-emmc.sh \
  --backup-dir "$BACKUP" --release-dir "$RELEASE" \
  --rootfs-override "$ROOTFS" \
  --rootfs-sha256 65fa6962951cafd1fc38d886d6e8df714904b61c2443cdfb7c4e436f3c31e2d6 \
  --output-dir "$FLASH" --reflash-debian --force-no-serial --reset
```

v2.2.0 在 V02 的本地功能测试成功，但该次按使用者要求跳过整盘回读；不能把那次测试称为已完成整盘验证。上述公开脚本的正式刷写**不会跳过**回读。

## 5. 首次启动、USB 与 SSH

设备重启约需 1–2 分钟。USB 会从 `05c6:9008` 变成 `18d1:d001`（Debian ADB + RNDIS；`lsusb` 显示“fastboot”字样也不代表真进入 fastboot）；虚拟机要重新映射。宿主机加载 `rndis_host` 后经 USB DHCP 获取 `192.168.68.x`，设备地址 `192.168.68.1`。热点为 `4G-WIFI/12345678`，设备 Wi‑Fi 网关 `10.42.0.1`。

```bash
ssh user@192.168.68.1
sudo ufi103s-modem-test
```

初始用户为 `user/1`。首启自动生成**本机** SSH 主机密钥，不生成登录强密码；SSH 接受 USB/Wi‑Fi 密码登录，但阻止蜂窝接口接入。请自行修改默认用户和热点密码。使用 VoCat 时保持 NetworkManager 运行，执行镜像**内置**的 `sudo ufi103s-modemmanager disable`；恢复方法见[短信转发说明](SMS_TROUBLESHOOTING.md)。

如果只有存储回读通过、没有 USB 或热点，不能称为系统启动成功；先保留 EDL 回读与错误日志，再从 ADB/串口检查启动服务。
