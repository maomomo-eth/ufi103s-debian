# UFI103S Debian 刷机与射频故障复盘

## 硬件与恢复基线

目标板丝印为 `UFI103S_V03`，SoC 为 MSM8916，eMMC 实测容量 `3909091328` 字节。写盘前完成完整 eMMC 备份和 `fsc/fsg/modemst1/modemst2` 分区备份，并复核 SHA-256。所有设备回读数据均保存在仓库之外。

## 自行构建版本为何没有继续使用

最初用 OpenStick Builder 构建 Debian 13，并修正 lk2nd compatible。boot、rootfs 和 aboot 的分区回读均与写入文件一致，但冷启动后只有红灯，没有 USB gadget 或热点。

这证明写入校验成功只能说明存储层正确，不能证明 boot chain、kernel、DTB 和 firmware 的组合适配该板。由于没有串口日志，无法把红灯故障继续缩小到单一启动阶段，因此回到已知可启动的第三方启动链建立恢复基线。

## Debian 11 阶段：boot DTB 缺少 MPSS 内存节点

第三方 Debian 11 的 `1.2.img` 可以启动系统和 Wi‑Fi，但内核报错：

```text
qcom-q6v5-mss 4080000.remoteproc: unable to resolve mpss region
```

对比同包 `1.2.img` 与 `1.4.img` 后确认，1.2 GHz DTB 缺少 MPSS reserved-memory 和 memshare 节点。修复版只补入这两类节点，不加入 1.3/1.4 GHz OPP，因此 CPU 上限仍为 1.2 GHz。该版本形成了 `v1.0.x` 的可用基线。

## Debian 12 阶段：MPSS firmware 不匹配

Debian 12 原始 rootfs 只有 MBA 和 WCNSS 文件，缺少完整 `modem.mdt`、`modem.b*`。原归档另附的“替换基带”文件虽然能被 remoteproc 加载，但实机 modem revision 变为：

```text
UFI001CT 20211106
```

随后 radio 停留在离线状态，QMI online 操作返回 `DeviceNotReady`。这不是 SIM 校准分区丢失，因为本次升级只写了 boot/rootfs，四个设备专属校准分区没有被覆盖。

把已经在同一型号 Debian 11 上验证过的 22 个 MPSS 文件复制到 Debian 12 `/lib/firmware` 后，modem revision 恢复为：

```text
UFI103_CT 20220801
```

此后能识别 SIM、注册运营商、附着分组网络并连接。由此确认 Debian 12 的核心射频故障是 rootfs 中 MPSS 文件集不完整/不匹配，不需要刷入其他设备的基带或校准分区。

## SIM 脚本为何会关闭全部槽位

原脚本使用：

```sh
sim="$(get_sims | grep -e "^$1")"
```

当 `SIM_ENABLED=sim:sel` 时，前缀匹配同时返回 `sim:sel` 与 `sim:sel2`。变量中出现换行，后续生成无效 sysfs 路径，而 `disable_all_sim` 已先关闭所有槽位。

修复方式是完整匹配并限制单行：

```sh
sim="$(get_sims | grep -F -x -- "$1" | head -n 1)"
```

修复后开机服务正常退出，对应 SIM GPIO 保持启用。

## 最终实测

- Debian 12 bookworm，kernel `6.4.0-rc4-jsbsbxjxh66-compile+`
- rootfs 扩展到约 3.3 GB
- MPSS 与 WCNSS remoteproc 均为 `running`
- RMTFS、ModemManager、NetworkManager、ADB 服务正常
- SIM ready，LTE 注册、附着和数据连接正常
- `wwan0` 获得 IPv4/IPv6
- 强制 IPv4/IPv6 走 `wwan0` 均无丢包
- Wi‑Fi 热点 DHCP、DNS、IPv4 forwarding 与 MASQUERADE 正常
- 冷启动后 firmware 和 SIM 脚本修复持续生效

一次手动重复激活蜂窝连接时，旧版 QMI/ModemManager 会话卡在 `disconnecting`，重启 ModemManager 后端口没有立即重新发现；整机启动路径可恢复。因此日常不应在 NetworkManager 自动拨号过程中重复运行 `nmcli connection up modem`。

## 不应采取的做法

- 不要因为 `DeviceNotReady` 就覆盖 `fsc/fsg/modemst1/modemst2`。
- 不要把 Android 原厂 `modem.bin` 按分区刷入本 Release 的 GPT；Linux MPSS 来自 `/lib/firmware/modem.*`。
- 不要使用其他 UFI/OpenStick 板型的 SBL1、CDT、aboot 或 firmware 试错。
- 不要用已个性化、含密码或设备标识的运行中 rootfs 回读制作公共镜像。
