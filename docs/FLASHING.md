# UFI103S V02/V03：9008 全盘刷机指南

本手册适用于从**原厂 Android 系统**通过 EDL 9008 全盘刷入 Debian 12，以及后续在同一台机器上**二次重刷 Debian**。

> [!CAUTION]
> **安全红线**：
> 1. 全盘刷入会**彻底清空**原厂系统及所有用户数据。
> 2. 射频校准与 NV 分区（`fsc`, `fsg`, `modemst1`, `modemst2`, `persist`）具有唯一硬件绑定特性，**严禁将机器 A 的备份刷入机器 B**！
> 3. 刷机工具链严格校验 eMMC 容量为 `3,909,091,328` 字节，非此容量或非 V02/V03 原厂 GPT 布局将被脚本安全拦截。

---

## ⚡ 极速上手：一键交互式向导（推荐）

如果您希望以最简单、安全的方式完成刷机，可以直接运行仓库根目录的交互式向导：

```bash
./flash.sh
# 或执行：./scripts/interactive-flash.sh
```

**向导特性**：
- **9008 掉线守护**：中途无论因接触不良、重启复位还是虚拟机映射断开，脚本都会暂停并等待您在宿主机重新映射 9008，识别后自动无缝继续；
- **IMEI 模 10 算法校验**：防止输错 IMEI 导致同机校准与备份混乱；
- **历史备份识别**：已备份过的设备支持直接复用，免去重复耗时；
- **全自动恢复校准与首启配置**。

如果您需要了解详细的每一步底层逻辑，请继续阅读下方的分步手动说明。

---

## 1. 准备工作

### 1.1 硬件与依赖环境
- **待刷设备**：已核对背面标签 15 位 IMEI 的 `UFI103S_V02` 或 `UFI103S_V03`。
- **系统依赖**：Linux 环境，并已安装以下命令行工具：
  - [bkerler/edl](https://github.com/bkerler/edl)（推荐 Python 虚拟环境安装）
  - `lsusb`、`sha256sum`、`rg`（ripgrep）、`curl`
- **虚拟机用户注意**：若在 KVM / virt-manager 下操作，USB 重新枚举时需动态映射，详见 [KVM USB 映射说明](KVM_USB.md)。

### 1.2 下载官方 Release 资产
从 [v2.2.0 Release](https://github.com/maomomo-eth/ufi103s-debian/releases/tag/v2.2.0) 下载以下两份文件，并解压基础包：
- `ufi103s-debian-v2.2.0-base.tar.gz`（包含 GPT、启动链、boot 镜像及 SHA256SUMS）
- `rootfs-debian12-usb-wifi-ssh-vocat-mm-wifi.img`（Debian 12 根文件系统 sparse 镜像）

---

## 2. 环境变量配置与进入 9008

### 2.1 设定全局环境变量
为了保证备份与临时文件不污染代码仓库，所有输出目录**建议放置在 Git 仓库外**：

```bash
# 1. 指定 edl 工具可执行路径
export EDL="/绝对路径/edl"

# 2. 询问并录入当前设备的 15 位 IMEI
read -r -p '请输入机身背贴上的 15 位 IMEI: ' IMEI

# 3. 设定各阶段工作目录 (BACKUP/PREPARE/FLASH 必须为尚不存在的新目录)
export BACKUP="/仓库外目录/ufi103s-v02/bak-$IMEI"
export RELEASE="/绝对路径/ufi103s-debian-v2.2.0-base"
export ROOTFS="/绝对路径/rootfs-debian12-usb-wifi-ssh-vocat-mm-wifi.img"
export PREPARE="/仓库外目录/work-prepare-$IMEI"
export FLASH="/仓库外目录/work-flash-$IMEI"
```

### 2.2 进入 EDL 9008 模式
- **按键法（推荐）**：拔出棒子，**按住 SIM 卡槽旁边的按键不放**，插入电脑 USB 端口，保持 2 秒后松开。
- **ADB 法**：若原厂系统 ADB 可用，执行：
  ```bash
  adb reboot edl
  ```

验证是否成功识别到高通 9008 设备：
```bash
lsusb -d 05c6:9008
```
> 必须确保宿主机（或直通虚拟机）内**仅有且只有一台** `05c6:9008` 设备。

---

## 3. 完整备份原机 eMMC (必备步骤)

在对设备进行任何写操作前，必须进行全盘与关键分区物理备份并生成 SHA-256 校验和：

```bash
# 执行备份脚本
EDL="$EDL" ./scripts/backup-full-emmc.sh "$BACKUP"

# 验证备份完整性
(cd "$BACKUP" && sha256sum -c SHA256SUMS)
```

> [!IMPORTANT]
> 备份目录下必须完整包含 `original-full-emmc.bin`（大小精确为 `3909091328` 字节）及 `partitions/` 目录下的 `modem.bin`、`persist.bin`、`fsc.bin`、`fsg.bin`、`modemst1.bin`、`modemst2.bin`。
> **备份完成后切勿给棒子断电重启原厂系统**，避免 NV 数据发生变动导致后续同机校验失败。

---

## 4. 离线组装整盘镜像

在正式刷写前，使用离线校验模式 `--prepare-only`，结合同机备份与 Release 固件组装全盘镜像并校验主备 GPT、分区对齐及 Hash：

```bash
# 1. 校验 Release 资源哈希
(cd "$RELEASE" && sha256sum -c SHA256SUMS)
printf '%s  %s\n' '65fa6962951cafd1fc38d886d6e8df714904b61c2443cdfb7c4e436f3c31e2d6' "$ROOTFS" | sha256sum -c -

# 2. 离线组装
./scripts/flash-edl-full-emmc.sh \
  --backup-dir "$BACKUP" \
  --release-dir "$RELEASE" \
  --rootfs-override "$ROOTFS" \
  --rootfs-sha256 65fa6962951cafd1fc38d886d6e8df714904b61c2443cdfb7c4e436f3c31e2d6 \
  --output-dir "$PREPARE" \
  --prepare-only
```
此步骤完全在本地离线执行，不会连接设备，也不会写入任何数据。

---

## 5. 9008 全盘写入、校准恢复与回读校验

保持设备连接在 9008 模式下，执行正式写入命令：

```bash
EDL="$EDL" ./scripts/flash-edl-full-emmc.sh \
  --backup-dir "$BACKUP" \
  --release-dir "$RELEASE" \
  --rootfs-override "$ROOTFS" \
  --rootfs-sha256 65fa6962951cafd1fc38d886d6e8df714904b61c2443cdfb7c4e436f3c31e2d6 \
  --output-dir "$FLASH" \
  --reset
```

### 刷写流程解析：
1. **二次安全比对**：脚本连接 9008 读取设备实际 GPT 与 NV，核验与 `$BACKUP` 一致后弹出确认提示。
2. **全盘写入 (`edl wf`)**：写入整块组装后的 eMMC 镜像。
3. **关键分区单独恢复**：从同机备份单独回写 `fsc`、`fsg`、`modemst1`、`modemst2` 并逐项回读核验。
4. **全盘回读比对 (`edl rf`)**：将整块 eMMC 完整回读并与组装源文件进行逐字节哈希比对。
5. **安全重启 (`--reset`)**：仅在所有校验 100% 通过后触发设备重启。

---

## 6. 特殊场景：同机二次重刷 Debian

若设备**已经刷过 Debian**，此时设备的 GPT 已经变为 Debian 布局，再次运行原厂刷机命令会被安全拦截。需改用 `--reflash-debian` 模式：

```bash
export REFLASH="/仓库外目录/work-reflash-$IMEI"

EDL="$EDL" ./scripts/flash-edl-full-emmc.sh \
  --backup-dir "$BACKUP" \
  --release-dir "$RELEASE" \
  --rootfs-override "$ROOTFS" \
  --rootfs-sha256 65fa6962951cafd1fc38d886d6e8df714904b61c2443cdfb7c4e436f3c31e2d6 \
  --output-dir "$REFLASH" \
  --reflash-debian \
  --reset
```

> [!NOTE]
> **原厂备份缺失硬件 Serial 的情况**：
> 若早期备份日志中未记录 `Serial: 0x...`，可附加 `--force-no-serial`。此参数要求在终端中手动输入机身背贴 IMEI 进行人工核验，杜绝错刷。

---

## 7. 首次开机与验收

设备重启约需 1~2 分钟。观察系统状态：
1. **USB 状态**：USB ID 将从 `05c6:9008` 变为 `18d1:d001`（Debian ADB + RNDIS）。
2. **网络分配**：宿主机获取到 `192.168.68.x`，设备 IP 为 `192.168.68.1`；周围出现 Wi-Fi 热点 `4G-WIFI`（密码 `12345678`）。
3. **SSH 登录与自检**：
   ```bash
   ssh user@192.168.68.1
   # 默认密码: 1

   # 运行基带自检脚本
   sudo ufi103s-modem-test
   ```
   预期 `MPSS` 状态为 `running`，`rmtfs` 与 `ModemManager` 均为 `active`。
