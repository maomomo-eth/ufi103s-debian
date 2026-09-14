# 实机刷机复盘

## 硬件与备份

目标板丝印为 `UFI103S_V03`，SoC 是 MSM8916，eMMC 容量为 3,909,091,328 字节。开始写盘前完成了全盘备份和关键分区拆分备份，并校验 SHA-256。

完整备份没有进入 Git 仓库或 Release。

## 第一次构建为何失败

最初使用 OpenStick Builder 构建 Debian 13，并把 lk2nd compatible 修正为 `thwc,ufi001c`。boot、rootfs 和 aboot 的分区回读均能与构建文件匹配，但设备冷启动后只有红灯，没有 USB gadget 或热点。

这说明“写入成功”不等于“整套 firmware 与该板兼容”。最终可确认自构建的 boot chain/boot 组合与实机存在兼容问题，但没有串口日志，无法把故障进一步缩小到单一 stage。

## 第三方镜像验证

第三方归档 SHA-256：

```text
1ec268a72c679d0126d4b94f93141efa6d0220eebfcfa8ec8324e83a340e2593
```

归档中的 boot DTB model 明确为：

```text
Handsome OpenStick jsbsbxjxh66-bianyi UFI103s
```

使用第三方 GPT、CDT、SBL1、RPM、TZ、HYP、aboot、boot 和 rootfs，并恢复目标设备自己的四个校准分区后，Debian 与 Wi‑Fi 热点成功启动。

## 1.2 GHz boot 的 modem 缺陷

原始 `1.2.img` 启动后：

```text
qcom-q6v5-mss 4080000.remoteproc: unable to resolve mpss region
```

`rmtfs.service` 因 `Failed to get rprocfd` 失败，ModemManager 看不到 modem。

对比同包 `1.2.img` 与 `1.4.img` 的 DTB，差异只有：

1. `1.4.img` 多出 MPSS reserved-memory 节点。
2. `1.4.img` 多出 memshare MPSS/GPS 子节点。
3. `1.4.img` 多出 1.3 GHz 和 1.4 GHz CPU OPP。

修复版在 `1.2.img` 中只补入前两项。kernel、ramdisk、ramdisk 偏移和 boot image 总大小保持不变，CPU OPP 仍以 1.2 GHz 为上限。

修复后内核日志显示：

```text
remoteproc remoteproc0: Booting fw image mba.mbn
qcom-q6v5-mss 4080000.remoteproc: MBA booted without debug policy, loading mpss
remoteproc remoteproc0: remote processor 4080000.remoteproc is now up
```

随后 `rmtfs` 正常、ModemManager 发现 modem，插入 SIM 后成功注册 LTE 并建立数据连接。

## 基带与校准数据

第三方 GPT 没有 Android 风格的 `modem` 分区。Linux 内核从 rootfs 的 `/lib/firmware/modem.*` 加载 MPSS firmware。因此：

- 不应把原厂 `modem.bin` 按分区名刷回。
- 必须保留目标设备自己的 `fsc/fsg/modemst1/modemst2`。
- firmware 能启动但 `sim-missing` 时，应先确认 SIM 卡是否插入及接触，不要立即混刷基带。

## 最终实测

- Debian 11 正常启动
- rootfs 约 3.3 GB
- Wi‑Fi AP 地址 `10.42.1.1/24`
- MPSS 与 WCNSS remoteproc 均正常
- LTE 连接获得 IPv4/IPv6
- 默认路由指向 `wwan0`
- `ping 1.1.1.1` 三次全部成功
- DNS 解析正常
- `net.ipv4.ip_forward=1`
- 热点网段存在 MASQUERADE 规则
- systemd 无失败单元

