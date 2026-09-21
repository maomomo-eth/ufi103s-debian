# UFI103S V02/V03 Debian 12：9008 全盘刷机指南

本文只使用 `05c6:9008`：先备份原厂整块 eMMC，再将 v2.0.0 写入整块 eMMC，最后从**同一台设备**的原厂备份单独恢复 `fsc/fsg/modemst1/modemst2`，并回读验证。无需进入 fastboot，也不要使用仓库历史 fastboot 刷写脚本。

V03 已验证 Debian 系统、Wi‑Fi 和蜂窝网络；V02 实测原厂 GPT 与 V03 布局相同、全盘写入并逐字节回读一致，启动与网络仍需独立确认。不要把存储层写入验证当作正常启动的证明。

## 1. 核对设备和工具

仅适用于 PCB 丝印为 `UFI103S_V02` 或 `UFI103S_V03`、Qualcomm MSM8916、原厂 GPT 符合脚本内校验布局、实际 eMMC 容量为 `3909091328` 字节的设备。刷机脚本逐项验证这些存储条件；板号仍需自己观察，不能仅凭 USB ID 或外壳判断。

准备 Linux、[bkerler/edl](https://github.com/bkerler/edl)、`uv`、`lsusb`、`rg`、`sha256sum`，以及 v2.0.0 发布包。Git 仓库提供脚本，解压后的 v2.0.0 发布包提供已验证的镜像和 `SHA256SUMS`；旧发布包内自带的 fastboot 说明不适用于本流程。

```bash
lsusb -d 05c6:9008
uv --version
/绝对路径/edl --help
```

只有一台 `05c6:9008` 设备映射到当前 Linux 后再继续。KVM 用户先把 9008 映射进虚拟机，完成刷写与回读之前不要断开 USB 或供电，见 [KVM USB 映射](KVM_USB.md)。

## 2. 在 9008 完整备份原厂 eMMC

备份目录必须是仓库外**尚不存在**的新目录，所在磁盘要留出额外至少一整块 eMMC 的空间：

```bash
EDL=/绝对路径/edl \
./scripts/backup-full-emmc.sh /仓库外/stock-本机-日期

cd /仓库外/stock-本机-日期
sha256sum -c SHA256SUMS
```

确认备份含 `original-full-emmc.bin`（`3909091328` 字节）、`partitions/persist.bin`，以及该设备自己的 `partitions/fsc.bin`、`fsg.bin`、`modemst1.bin`、`modemst2.bin`。保存原始备份；**不要**指定备份脚本的 `--reset`，也不要在备份与刷机之间启动原系统，以免 NV 自行变化。不要使用其他设备的校准文件。

## 3. 解压 v2.0.0 镜像并校验

```bash
tar -xzf ufi103s-debian-v2.0.0-private.tar.gz
cd /绝对路径/ufi103s-debian-v2.0.0
sha256sum -c SHA256SUMS
```

从**本仓库最新版本**运行后续 `scripts/flash-edl-full-emmc.sh`；`--release-dir` 指向上述解压目录。旧发布包内的刷机脚本没有更新为 9008 全盘流程，不能直接运行。

## 4. 先做离线组装（建议）

回到 Git 仓库根目录，输出目录必须在仓库外、尚不存在，且文件系统额外至少有约 9.5 GB 空间：

```bash
./scripts/flash-edl-full-emmc.sh \
  --backup-dir /仓库外/stock-本机-日期 \
  --release-dir /绝对路径/ufi103s-debian-v2.0.0 \
  --output-dir /仓库外/v2-离线检查-日期 \
  --prepare-only
```

离线模式不连接设备、不写 eMMC。脚本会核对原厂 GPT、同一份原厂整盘备份中的校准数据、发布包所有文件 SHA-256、主备 GPT CRC、分区边界与镜像大小，并生成完整的 `debian-v2-full-emmc.bin`。原发布包的 GPT 模板会动态填写末尾 rootfs 和保护 MBR 大小，同时将条目数量、CRC 一起修正后再写盘；不要将未修补的 `gpt_both0.bin` 直接写进 eMMC。

离线检查目录可保留，但正式刷机必须使用**另一个全新输出目录**，不覆盖原文件。

## 5. 在 9008 全盘写入、恢复校准并回读

保持设备仍处于 9008，从仓库根目录执行：

```bash
EDL=/绝对路径/edl ./scripts/flash-edl-full-emmc.sh \
  --backup-dir /仓库外/stock-本机-日期 \
  --release-dir /绝对路径/ufi103s-debian-v2.0.0 \
  --output-dir /仓库外/v2-正式刷机-日期
```

脚本要求键入 `UFI103S-EDL-ERASE` 才开始写盘（无人值守时才使用 `--yes`），流程为：

1. 校验原厂备份、Release 和组装镜像；检查当前仅有一台 9008，实际 eMMC 容量与原厂 GPT 匹配。
2. 再比对当前设备的原厂 `modemst1/modemst2/persist` 与备份，以阻止将别的设备的私有数据写错目标。
3. 通过 EDL `wf` 从扇区 0 写入整块 eMMC；新分区表、启动链、Debian boot/rootfs 同时落盘。
4. 通过 EDL `w` **再从原厂备份**单独恢复本机 `fsc/fsg/modemst1/modemst2`；逐项 `r` 回读核对。
5. 通过 EDL `rf` 回读整块 eMMC，并用 `cmp` 与目标镜像逐字节比较。只有全部一致才报告成功。

默认完成后仍留在 9008；需要验证成功后自动尝试启动时可事先加 `--reset`。即使 `edl` 写入命令退出码为零，也不能跳过设备回读。任一步骤失败应保持 9008、保留私有日志和原厂备份，不要启动不完整系统。

全盘写入会清除原有系统和用户数据。原厂全盘备份、回读镜像及日志含设备身份和密码，不能提交到 Git 或上传 Release。程序会拒绝把工作目录放进本 Git 仓库。

## 6. 启动与验证

整盘回读通过后，再物理断电、重新上电，等待约 60–120 秒。检查 `4G-WIFI` 热点及 `18d1:d001`（Debian ADB + RNDIS）；KVM 下 USB PID 改变需重新映射。`usb.ids` 把 `18d1:d001` 显示为 “Nexus 4 (fastboot)” 不代表设备真的进入 fastboot。

基础镜像的初始凭据为 `4G-WIFI / 12345678`，Debian `user / 1`；首次登录立即修改。不要把个性化配置或设备回读 rootfs 打包发布。

```bash
./scripts/check-device.sh
./scripts/check-device.sh --network-test
```

预期 MPSS/WCNSS 为 `running`，`rmtfs`、ModemManager、NetworkManager 为 `active`，`mmcli -L` 可见 modem，插卡后 `wwan0` 可联网，热点有 DHCP/DNS/NAT。存储回读通过但不出现热点或 USB 时，应继续排查启动阶段，不能直接宣称系统工作正常。

## 7. 恢复原厂系统

若设备无法启动但还能进入 `05c6:9008`，优先使用这台设备的原厂完整 eMMC 备份，核对目标设备、容量、原厂 SHA-256 后再人工评估恢复。不要把其他板型的 GPT、SBL1、CDT、aboot 或别人设备的校准分区混刷。
