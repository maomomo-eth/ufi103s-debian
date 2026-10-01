# 非 UFI103S 板（UFI001C 类）运行本固件的实测记录

> [!NOTE]
> **社区实测反馈，非官方支持声明。** 本文记录在两台**不是 UFI103S** 的 MSM8916 随身 Wi‑Fi 上运行本仓库 Debian 12 时遇到的问题和已验证的处理方法，供拿到其他板型的用户参考。本仓库的整盘刷机脚本仍然只支持 `UFI103S_V02/V03`。文中不含 IMEI、ICCID、IMSI、手机号或网络地址。

## 1. 如何判断自己不是 UFI103S

| 项目 | UFI103S V02/V03（本仓库支持） | 本文设备（UFI001C 类） |
| --- | --- | --- |
| eMMC 容量 | `3,909,091,328` 字节 | `3,959,422,976` 字节 |
| 原厂基带版本（`qmicli --dms-get-revision`） | `UFI103_CT 20220801` | `UFI001CT 20211106`（原厂安卓 `modem` 分区内即为此版本） |
| 网络能力（`--dms-get-capabilities`） | — | `cdma20001x, evdo, umts, lte`，**不含 GSM** |
| LTE 频段（`--dms-get-band-capabilities`） | — | 1、3、5、8、38、39、40、41 |

eMMC 容量不一致时，`flash-edl-full-emmc.sh` 会按设计拒绝写盘，这是正确的保护。本文设备是在已有 Debian v2 布局的基础上运行的，不是用整盘脚本刷入的。

## 2. 基带：UFI103_CT 在此板上崩溃，需换回板子自己的 UFI001CT

这与 [POSTMORTEM.md](POSTMORTEM.md) 中“UFI103S 上跑 UFI001CT 会离线”的现象正好对称。

- 使用 rootfs 自带的 `UFI103_CT 20220801`（构建分支 `MPSS.DPM.1.0.c7`）时，开机后 MPSS 反复报 `coex_interface.c:530`、`mcfg_utils.c:186` 致命错误；随后 DMS 永久停在 `offline`，执行 `--dms-set-operating-mode=online` 返回 `DeviceNotReady (52)`。
- 把 `/lib/firmware/` 中的 `mba.mbn`、`modem.mdt`、`modem.b*` 换成 UFI001C 版（OpenStick `firmware-ufi001c.zip`，`UFI001CT 20211106`，`MPSS.DPM.2.0.2`）后：无崩溃，可以 online，并能正常驻网。
- 我们把这套文件与该设备原厂安卓 `modem` 分区里的文件逐个做了 SHA‑256 比对，结果完全一致。也就是说，**用的就是这块板子出厂自带的基带**，不是从别的板型移植来的。
- 整个过程没有写入 `fsc/fsg/modemst1/modemst2`；rmtfs 保持 `-r -P -s`。

> [!WARNING]
> 换基带前请先把原文件移到备份目录，例如 `/lib/firmware/ufi103ct-backup/`。重刷或升级 rootfs 会把基带还原成 UFI103_CT，之后需要重新替换。

## 3. 在此板上实测的 SIM 结果

两台同型号设备，外置卡槽（`sim:sel=1`），固件为 UFI001CT。下表中的“漫游网络”指在中国大陆驻留的网络。

| 卡 | 读卡 | 驻网 | 收短信 | 备注 |
| :--- | :---: | :---: | :---: | :--- |
| HahaSim 香港实体卡（`+852`） | ✅ | ✅ 漫游中国移动 LTE | ✅ | 已用 VoCat + Bark 端到端验证；两张不同的 HahaSim 都成功 |
| 中国移动 5G 实体卡 | ❌ | — | — | 两台都读不出：先报 `unknown (0)`，再报 `no-atr-received (3)`，手机上正常 |
| T‑Mobile eSIM 小白卡 | ❌ | — | — | 同上 |
| Red Pocket 美国实体卡（AT&T GSMA 线路，`310280`） | ✅ | ❌ | ❌ | 能收到中国移动 LTE 信号，但注册只得到 `limited`，`+CEER: EMM attach failed`；同一张卡在手机上可以漫游中国移动。根因未查明 |

对读不出的卡，用引脚采样能看到卡已经回应了完整 ATR 和 PPS，但初始化中途失败。换过四套 MPSS、试过 16 种选卡 GPIO 组合、调整过时序和驱动强度，都没有改善。目前推测与此板外置卡槽的电路或电压有关，**未证实**。

其中一台插 HahaSim 时射频完全不工作（`NoRadio`，网络扫描返回 `InvalidOperation`），同一张卡在另一台上正常，属于个体问题，原因未明。

## 4. VoCat 相关注意事项（与板型无关）

1. **新卡会被自动开启飞行模式。** VoCat v0.3.1 第一次见到某个 ICCID 时，会写入 `vowifi=1, airplane=1, source=default` 的卡策略（日志：`new SIM protected by default VoWiFi/airplane policy`），基带随后进入 low‑power 或 `shutting-down`，看起来就像“插卡后搜不到网”。如果要走蜂窝方式收短信，需要停止 VoCat，把该卡在 `card_policies` 中的策略改为 `network=0, vowifi=0, airplane=0`，再启动 VoCat。**每换一张新卡都要处理一次。**
2. 设备级 `sms_enabled` 在我们的设备上初始值为 `0`，需要改为 `1` 才能收短信。
3. 短信转发渠道（Bark 等）配置在 `notification_settings` 表中。VoCat 每 2 秒轮询一次，修改后无需重启。只有启用之后收到的短信才会转发。
4. Red Pocket（GID1 以 `42` 开头）走 VoWiFi 时，VoCat 实际解析的 ePDG 主机名是 `epdg.epc.mnc170.mcc311.pub.3gppnetwork.org`。这个主机名在公共 DNS 上解析为 `127.0.0.1`，而内置规则 `ipcc-redpocket-310170` 指向的 `epdg.epc.att.net` 没有被用上。手动指向 `epdg.epc.att.net` 后，IKE 能连上，但随后 USIM AUTHENTICATE 返回 QMI UIM 错误 `0x30`。这个问题或许应该报给 VoCat 上游。

## 5. 会让此板内核卡死的操作

以下操作在此板上实测会导致内核卡死：ADB shell、SSH、`adb reboot` 全部无响应，只能拔插断电。

- 系统运行中执行 `systemctl restart rmtfs`（会连带重启 MPSS）；
- 把 `rpmsg_chrdev` 绑定到 `remoteproc1:smd-edge.DIAG.-1.-1`。

两次都没有损坏数据，断电重启后恢复正常。在同类板子上排障时，建议用整机重启代替单独重启 rmtfs 或基带。

## 6. 其他观察

- 开机后基带经常停在 `shutting-down`，需要手动执行一次 `--dms-set-operating-mode=online`。可以写一个开机服务做有限次数的重试（务必先确认数据防护已生效）。
- `openstick-sim-changer` 在 ModemManager 被 mask 后，最后一步重启 MM 会失败退出；不过选卡 GPIO 在此之前已经设置好，不影响读卡。它的 `modprobe -r qcom-q6v5-mss` 会在开机约 40 秒时引发一次 `sys_m.c:603 INTENTIONAL RESET`，属于预期现象。
