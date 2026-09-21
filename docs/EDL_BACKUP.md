# 9008/EDL 完整 eMMC 备份

完整备份用于恢复 GPT、启动链、Android/Debian 系统和关键分区。它不能被四个校准分区备份代替。

## 前提

- 设备必须处于 `05c6:9008`。
- Linux 能直接访问该 USB 设备。
- 已安装 [bkerler/edl](https://github.com/bkerler/edl)。
- 目标磁盘至少有“eMMC 容量 + 512 MB”的可用空间。
- 输出目录必须尚不存在，脚本不会覆盖旧备份。

KVM 用户需要先在宿主机把 `05c6:9008` 映射到虚拟机。

## 执行

```bash
EDL=/绝对路径/edl \
./scripts/backup-full-emmc.sh \
  /绝对路径/stock-$(date +%F)
```

如果设备必须使用指定 Firehose loader：

```bash
EDL=/绝对路径/edl \
./scripts/backup-full-emmc.sh \
  --loader /绝对路径/prog_emmc_firehose.mbn \
  /绝对路径/stock-$(date +%F)
```

备份完成后如需尝试自动复位：

```bash
EDL=/绝对路径/edl \
./scripts/backup-full-emmc.sh \
  --reset \
  /绝对路径/stock-$(date +%F)
```

## 输出

```text
BACKUP_INFO.txt
SHA256SUMS
edl-printgpt.log
original-full-emmc.bin
gpt/
partitions/
```

- `original-full-emmc.bin`：完整 eMMC 镜像。
- `gpt/`：EDL 导出的 GPT 文件。
- `partitions/`：当前 GPT 中存在的关键分区副本。
- 原厂 `persist.bin` 与 `fsc/fsg/modemst1/modemst2` 必须来自同一次同一台设备备份，9008 全盘刷机脚本会核对备份与目标设备。
- `SHA256SUMS`：整个备份的完整性校验。

脚本会确认全盘镜像字节数与 EDL 报告的磁盘容量完全一致，然后生成并立即复核 SHA-256。

## 二次校验

```bash
cd /绝对路径/备份目录
sha256sum -c SHA256SUMS
```

建议复制到另一块物理存储后再次校验。

如果备份完马上通过 9008 全盘刷入 v2.0.0，不要使用 `--reset`，也不要让原系统再次启动：原系统可能更新 `modemst1/modemst2/persist`，造成刷机脚本的同机身份比对失败。完整流程见[9008 全盘刷机指南](FLASHING.md)。

## 隐私与恢复风险

全盘镜像、校准分区、GPT 日志可能包含 IMEI、序列号、SIM/网络配置、密码或其他设备数据：

- 不得提交 Git。
- 不得放入 Release。
- 不得与其他设备混刷。
- 建议使用加密存储。

仓库提供 v2.0.0 的 9008 全盘安装脚本，但**不**提供一键恢复原厂全盘的脚本。原厂全盘恢复也会无条件覆盖目标 eMMC，必须在确认目标设备、容量和备份 SHA-256 后人工执行。
